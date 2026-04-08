"""elk.bzl - Zero-codegen Python package management for Buck2.

Selects platform-appropriate wheels from a lock file and creates download +
library targets, without any code generation step.

Usage in a BUCK file:

    load("elk//:elk.bzl", "elk_packages")
    load("elk//:elk.bzl", "poetry_packages")  # parse poetry.lock format

    elk_packages(
        packages = poetry_packages(lock),
        platform_tags = { "linux-x86_64": tags, ... },
    )
"""

load("@prelude//:prelude.bzl", "native")
load("@prelude//rust:cargo_package.bzl", "get_reindeer_platforms")
load("@prelude//utils:selects.bzl", "selects")

# ---------------------------------------------------------------------------
# Record types
# ---------------------------------------------------------------------------

WheelInfo = record(
    name = str,
    version = str,
    python = str,
    python_tags = list[str],
    abi_tags = list[str],
    platform_tags = list[str],
)

WheelFile = record(
    file = str,
    hash = str,
    url = field(str | None, None),
)

Package = record(
    name = str,
    version = str,
    files = list[WheelFile],
    deps = list[str],
)

# ---------------------------------------------------------------------------
# Wheel filename parsing
# ---------------------------------------------------------------------------

def _parse_wheel_filename(filename: str) -> [WheelInfo, None]:
    """Parse a wheel filename into tag components.

    Format: {name}-{version}(-{build})?-{python}-{abi}-{platform}.whl
    """
    if not filename.endswith(".whl"):
        return None
    parts = filename[:-4].split("-")
    if len(parts) == 5:
        name, version, python, abi, plat = parts
    elif len(parts) == 6:
        name, version, _build, python, abi, plat = parts
    else:
        return None
    return WheelInfo(
        name = name,
        version = version,
        python = python,
        python_tags = python.split("."),
        abi_tags = abi.split("."),
        platform_tags = plat.split("."),
    )

def _wheel_matches_tag(wheel: WheelInfo, tag_str: str) -> bool:
    """True if a parsed wheel is compatible with a tag string."""
    parts = tag_str.split("-", 2)
    if len(parts) != 3:
        return False
    interp, abi, plat = parts
    return (interp in wheel.python_tags and
            abi in wheel.abi_tags and
            plat in wheel.platform_tags)

def _choose_wheel(files: list[WheelFile], tags: list[str]) -> [WheelFile, None]:
    """Pick the highest-priority wheel for a platform.

    Iterates tags in priority order (best first), returns the first file
    whose wheel filename matches.
    """
    parsed = []
    for f in files:
        w = _parse_wheel_filename(f.file)
        if w != None:
            parsed.append((f, w))
    for tag in tags:
        for f, w in parsed:
            if _wheel_matches_tag(w, tag):
                return f
    return None

# ---------------------------------------------------------------------------
# URL construction
# ---------------------------------------------------------------------------

def _pypi_url(filename: str) -> str:
    """Build a PyPI download URL from a wheel filename.

    Uses the redirect-capable path layout:
      https://files.pythonhosted.org/packages/{python}/{initial}/{name}/{filename}
    which 302-redirects to the canonical blake2b-hashed path.
    """
    w = _parse_wheel_filename(filename)
    if w == None:
        fail("Not a wheel: " + filename)
    return "https://files.pythonhosted.org/packages/{}/{}/{}/{}".format(
        w.python,
        w.name[0],
        w.name,
        filename,
    )

def _wheel_url(wf: WheelFile) -> str:
    """Return the download URL for a wheel file, constructing one if needed."""
    if wf.url != None:
        return wf.url
    return _pypi_url(wf.file)

# ---------------------------------------------------------------------------
# Name helpers
# ---------------------------------------------------------------------------

def _normalize(name: str) -> str:
    """PEP 503 normalize a package name (lowercase, collapse [-_.] to -)."""
    return name.lower().replace("_", "-").replace(".", "-")

# ---------------------------------------------------------------------------
# Lock-file adapters
# ---------------------------------------------------------------------------

def poetry_packages(lock_data: dict) -> list[Package]:
    """Adapt poetry.lock data (loaded as TOML) into the elk package list."""
    result = []
    for pkg in lock_data["package"]:
        deps = []
        for dep_name in pkg.get("dependencies", {}).keys():
            deps.append(_normalize(dep_name))

        files = []
        for f in pkg.get("files", []):
            files.append(WheelFile(
                file = f["file"],
                hash = f["hash"],
            ))

        result.append(Package(
            name = pkg["name"],
            version = pkg["version"],
            files = files,
            deps = deps,
        ))
    return result

def _url_filename(url: str) -> str:
    """Extract the filename from a URL."""
    return url.rsplit("/", 1)[-1]

def uv_packages(lock_data: dict) -> list[Package]:
    """Adapt uv.lock data (loaded as TOML) into the elk package list.

    uv.lock includes full blake2b URLs, which are passed through directly.
    """
    result = []
    for pkg in lock_data["package"]:
        # Skip the root project (virtual source)
        source = pkg.get("source", {})
        if type(source) == "dict" and (source.get("virtual") != None or source.get("editable") != None):
            continue

        deps = []
        for dep in pkg.get("dependencies", []):
            deps.append(_normalize(dep["name"]))

        files = []
        for w in pkg.get("wheels", []):
            files.append(WheelFile(
                file = _url_filename(w["url"]),
                hash = w["hash"],
                url = w["url"],
            ))

        result.append(Package(
            name = pkg["name"],
            version = pkg["version"],
            files = files,
            deps = deps,
        ))
    return result

def uv_workspace_aliases(lock_data: dict, visibility: list[str] = ["PUBLIC"]):
    """Create alias targets for uv workspace members in a flat namespace.

    Reads editable packages from uv.lock and for each creates an alias from
    the normalized name to the member's python_library target, e.g.:
        :lib-common -> //example/uv_workspace/packages/lib-common:lib-common

    The target path is derived automatically from get_cell_name() and
    package_name(). Each member's BUCK file must define a python_library
    with name matching the normalized package name.

    Args:
        lock_data: Parsed uv.lock TOML data.
        visibility: Visibility for the alias targets.
    """
    members = {}
    for pkg in lock_data["package"]:
        source = pkg.get("source", {})
        if type(source) == "dict" and source.get("editable") != None:
            members[_normalize(pkg["name"])] = source["editable"]
    _elk_workspace_aliases(members, visibility)

def create_workspace_member_macro(*, lock_data: dict, root: str):
    """Return a workspace_member function with lock_data and root curried in.

    Precomputes all workspace members' dependency labels in a single pass over
    the lock file so each call to the returned function is a pure dict lookup.

    Call this once in a ``.bzl`` file at the workspace root and export the
    result; each member package then imports and calls the returned function
    with only ``name`` (and any ``**kwargs`` for ``python_library``).

    Example ``workspace.bzl``::

        load("@elk//:elk.bzl", "create_workspace_member_macro")
        load(":uv.lock.toml", lock = "value")
        workspace_member = create_workspace_member_macro(
            lock_data = lock,
            root = "//my/workspace",
        )

    Args:
        lock_data: Parsed uv.lock TOML data.
        root: The Buck2 target path of the workspace root BUCK package,
              e.g. ``"//example/uv_workspace"``.
    """

    # Single pass: build {normalized_name: [dep_label, ...]} for all packages.
    all_deps = {}
    for pkg in lock_data["package"]:
        all_deps[_normalize(pkg["name"])] = [
            "{}:{}".format(root, _normalize(dep["name"]))
            for dep in pkg.get("dependencies", [])
        ]

    def workspace_member(*, name, **kwargs):
        _uv_workspace_member(name = name, deps = all_deps, root = root, **kwargs)

    return workspace_member

def _uv_workspace_member(*, name: str, deps: dict, root: str, **kwargs):
    """Create a python_library for a uv workspace member.

    Follows the uv_build backend's ``src/`` layout convention
    (https://docs.astral.sh/uv/concepts/build-backend): globs all
    ``src/**/*.py`` and strips the ``src/`` prefix so modules are
    importable at their natural paths, including dotted namespace
    packages configured via ``[tool.uv.build-backend] module-name``.

    Args:
        name: The package name (will be normalized).
        deps: Precomputed {normalized_name: [dep_label, ...]} dict from
              create_workspace_member_macro.
        root: Unused here but kept for symmetry; deps are already resolved.
        **kwargs: Passed through to python_library (e.g. visibility).
    """
    if name != _normalize(name):
        fail("name must be normalised so it can be referenced by other packages in the workspace (got '{}', expected '{}')".format(name, _normalize(name)))
    srcs = {p.removeprefix("src/"): p for p in glob(["src/**/*.py"])}
    native.python_library(
        name = name,
        srcs = srcs,
        base_module = "",
        deps = deps.get(name, []),
        **kwargs
    )

# ---------------------------------------------------------------------------
# Target creation
# ---------------------------------------------------------------------------

def _apply_platform(platforms: dict, platform_dict: dict, default: str):
    return selects.apply(
        platforms,
        lambda platform: platform_dict.get(platform, default),
    )

def _elk_workspace_aliases(members: dict[str, str], visibility: list[str]):
    cell = get_cell_name()
    pkg = package_name()
    prefix = "{}//{}".format(cell, pkg) if cell else "//{}".format(pkg)
    for name, path in members.items():
        native.alias(
            name = name,
            actual = "{}/{}:{}".format(prefix, path, name),
            visibility = visibility,
        )

def elk_packages(packages: list[Package], platform_tags: dict[str, list[str]], platforms = None, visibility: list[str] = ["PUBLIC"]):
    """Create Buck2 targets for every package in *packages*.

    For each package the macro creates:
      - ``remote_file``  (download the wheel)
      - ``prebuilt_python_library``  (make it importable)
      - ``alias``  (select the right wheel per-platform)

    Args:
        packages: Use ``poetry_packages()`` or ``uv_packages()`` to build this
                  from a lock file.
        platform_tags: ``{"linux-x86_64": ["cp312-cp312-manylinux...", ...], ...}``
        platforms: Custom platform select dict. Falls back to
                   ``get_reindeer_platforms()`` from the prelude.
        visibility: visibility list for the alias targets.
    """
    if platforms == None:
        platforms = get_reindeer_platforms()

    # sentinel for platforms that don't match any wheel
    native.filegroup(name = "_elk_null", srcs = [])

    # First pass: build a name set for dependency resolution.
    known = {}
    for pkg in packages:
        known[_normalize(pkg.name)] = True

    for pkg in packages:
        pkg_name = _normalize(pkg.name)
        pkg_deps = [":{}".format(d) for d in pkg.deps if d in known]

        # --- choose wheels per platform ---
        platform_chosen = {}  # platform_name -> WheelFile
        all_chosen = {}  # filename -> WheelFile (dedup)

        for plat_name, tags in platform_tags.items():
            chosen = _choose_wheel(pkg.files, tags)
            if chosen != None:
                platform_chosen[plat_name] = chosen
                all_chosen[chosen.file] = chosen

        if len(all_chosen) == 0:
            continue

        # --- create remote_file + prebuilt_python_library ---
        built = {}  # filename -> target label string
        for filename in all_chosen:
            wf = all_chosen[filename]
            sha = wf.hash
            if sha.startswith("sha256:"):
                sha = sha[7:]

            native.remote_file(
                name = filename,
                url = _wheel_url(wf),
                sha256 = sha,
            )
            bname = filename + "-built"
            native.prebuilt_python_library(
                name = bname,
                binary_src = ":" + filename,
                deps = pkg_deps,
            )
            built[filename] = ":" + bname

        # --- alias ---
        if len(all_chosen) == 1:
            actual = built[all_chosen.keys()[0]]
        else:
            actual_map = {}
            for pn, ch in platform_chosen.items():
                actual_map[pn] = built[ch.file]
            actual = _apply_platform(platforms, actual_map, ":_elk_null")

        native.alias(
            name = pkg_name,
            actual = actual,
            visibility = visibility,
        )

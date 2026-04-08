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
        if type(source) == "dict" and source.get("virtual") != None:
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

# ---------------------------------------------------------------------------
# Target creation
# ---------------------------------------------------------------------------

def _apply_platform(platform_dict: dict, default: str):
    return selects.apply(
        get_reindeer_platforms(),
        lambda platform: platform_dict.get(platform, default),
    )

def elk_packages(packages: list[Package], platform_tags: dict[str, list[str]], visibility: list[str] = ["PUBLIC"]):
    """Create Buck2 targets for every package in *packages*.

    For each package the macro creates:
      - ``remote_file``  (download the wheel)
      - ``prebuilt_python_library``  (make it importable)
      - ``alias``  (select the right wheel per-platform)

    Args:
        packages: Use ``poetry_packages()`` or ``uv_packages()`` to build this
                  from a lock file.
        platform_tags: ``{"linux-x86_64": ["cp312-cp312-manylinux...", ...], ...}``
        visibility: visibility list for the alias targets.
    """

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
            actual = _apply_platform(actual_map, ":_elk_null")

        native.alias(
            name = pkg_name,
            actual = actual,
            visibility = visibility,
        )

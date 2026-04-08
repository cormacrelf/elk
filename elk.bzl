"""elk.bzl - Zero-codegen Python package management for Buck2.

Selects platform-appropriate wheels from a lock file and creates download +
library targets, without any code generation step.

Usage in a BUCK file:

    load("@elk//:elk.bzl", "elk_packages")
    load("@elk//:elk.bzl", "poetry_packages")  # parse poetry.lock format

    elk_packages(
        packages = poetry_packages(lock),
        platform_tags = { "linux-x86_64": tags, ... },
    )
"""

load("@prelude//:prelude.bzl", "native")
load("@prelude//rust:cargo_package.bzl", "get_reindeer_platforms")
load("@prelude//utils:selects.bzl", "selects")

# ---------------------------------------------------------------------------
# Wheel filename parsing
# ---------------------------------------------------------------------------

def _parse_wheel_filename(filename):
    """Parse a wheel filename into tag components.

    Format: {name}-{version}(-{build})?-{python}-{abi}-{platform}.whl
    Returns struct(name, version, python, abi_tags, platform_tags) or None.
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
    return struct(
        name = name,
        version = version,
        python = python,
        python_tags = python.split("."),
        abi_tags = abi.split("."),
        platform_tags = plat.split("."),
    )

def _wheel_matches_tag(wheel, tag_str):
    """True if a parsed wheel is compatible with a tag like 'cp312-cp312-manylinux_2_28_x86_64'."""
    parts = tag_str.split("-", 2)
    if len(parts) != 3:
        return False
    interp, abi, plat = parts
    return (interp in wheel.python_tags and
            abi in wheel.abi_tags and
            plat in wheel.platform_tags)

def _choose_wheel(files, tags):
    """Pick the highest-priority wheel for a platform.

    Args:
        files: list of {"file": "x.whl", "hash": "sha256:..."}
        tags:  ordered tag strings, best first.
    Returns: matching file dict, or None.
    """
    wheels = []
    for f in files:
        w = _parse_wheel_filename(f["file"])
        if w != None:
            wheels.append((f, w))
    for tag in tags:
        for f, w in wheels:
            if _wheel_matches_tag(w, tag):
                return f
    return None

# ---------------------------------------------------------------------------
# URL construction
# ---------------------------------------------------------------------------

def _pypi_url(filename):
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

# ---------------------------------------------------------------------------
# Name helpers
# ---------------------------------------------------------------------------

def _normalize(name):
    """PEP 503 normalize a package name (lowercase, collapse [-_.] to -)."""
    return name.lower().replace("_", "-").replace(".", "-")

# ---------------------------------------------------------------------------
# Lock-file adapters
#
# Each adapter turns a lock-file-specific data structure into a uniform list:
#   [ { "name": "requests", "version": "2.31.0",
#       "files": [ {"file": "...", "hash": "sha256:..."} ],
#       "deps": ["urllib3", "certifi"] }, ... ]
# ---------------------------------------------------------------------------

def poetry_packages(lock_data):
    """Adapt poetry.lock data (loaded as TOML) into the elk package list.

    Args:
        lock_data: the full poetry.lock parsed as TOML (a dict with a
            "package" key containing the array-of-tables).

    Returns:
        list of package dicts in elk's uniform format.
    """
    result = []
    for pkg in lock_data["package"]:
        deps = []
        for dep_name in pkg.get("dependencies", {}).keys():
            deps.append(_normalize(dep_name))
        result.append({
            "name": pkg["name"],
            "version": pkg["version"],
            "files": pkg.get("files", []),
            "deps": deps,
        })
    return result

def uv_packages(lock_data):
    """Adapt uv.lock data into the elk package list.

    TODO: implement once uv lock format support is added.
    """
    fail("uv_packages: not yet implemented")

# ---------------------------------------------------------------------------
# Target creation
# ---------------------------------------------------------------------------

def _apply_platform(platform_dict, default):
    return selects.apply(
        get_reindeer_platforms(),
        lambda platform: platform_dict.get(platform, default),
    )

def elk_packages(packages, platform_tags, visibility = ["PUBLIC"]):
    """Create Buck2 targets for every package in *packages*.

    For each package the macro creates:
      - ``remote_file``  (download the wheel)
      - ``prebuilt_python_library``  (make it importable)
      - ``alias``  (select the right wheel per-platform)

    Args:
        packages: list of dicts with "name", "version", "files", "deps".
                  Use ``poetry_packages()`` or ``uv_packages()`` to build this
                  from a lock file.
        platform_tags: ``{"linux-x86_64": ["cp312-cp312-manylinux...", ...], ...}``
        visibility: visibility list for the alias targets.
    """

    # sentinel for platforms that don't match any wheel
    native.filegroup(name = "_elk_null", srcs = [])

    # First pass: build a name -> True set so we know which packages exist
    # (needed for dependency resolution).
    known = {}
    for pkg in packages:
        known[_normalize(pkg["name"])] = True

    for pkg in packages:
        pkg_name = _normalize(pkg["name"])
        files = pkg.get("files", [])
        pkg_deps = [":{}".format(d) for d in pkg.get("deps", []) if d in known]

        # --- choose wheels per platform ---
        platform_chosen = {}  # platform_name -> file dict
        all_chosen = {}  # filename  -> file dict  (dedup)

        for plat_name, tags in platform_tags.items():
            chosen = _choose_wheel(files, tags)
            if chosen != None:
                platform_chosen[plat_name] = chosen
                all_chosen[chosen["file"]] = chosen

        if len(all_chosen) == 0:
            continue

        # --- create remote_file + prebuilt_python_library ---
        built = {}  # filename -> target label string
        for filename in all_chosen:
            sha = all_chosen[filename]["hash"]
            if sha.startswith("sha256:"):
                sha = sha[7:]

            native.remote_file(
                name = filename,
                url = _pypi_url(filename),
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
            # pure-python wheel or only one variant
            actual = built[all_chosen.keys()[0]]
        else:
            actual_map = {}
            for pn, ch in platform_chosen.items():
                actual_map[pn] = built[ch["file"]]
            actual = _apply_platform(actual_map, ":_elk_null")

        native.alias(
            name = pkg_name,
            actual = actual,
            visibility = visibility,
        )

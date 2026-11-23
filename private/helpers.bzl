"""Internal helpers for elk.bzl.

Only elk.bzl and //tests should load this file. Once buck2 supports load
visibility, restrict it to those.
"""

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

def parse_wheel_filename(filename: str) -> [WheelInfo, None]:
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

def wheel_matches_tag(wheel: WheelInfo, tag_str: str) -> bool:
    """True if a parsed wheel is compatible with a tag string."""
    parts = tag_str.split("-", 2)
    if len(parts) != 3:
        return False
    interp, abi, plat = parts
    return (interp in wheel.python_tags and
            abi in wheel.abi_tags and
            plat in wheel.platform_tags)

def choose_wheel(files: list[WheelFile], tags: list[str]) -> [WheelFile, None]:
    """Pick the highest-priority wheel for a platform.

    Iterates tags in priority order (best first), returns the first file
    whose wheel filename matches.
    """
    parsed = []
    for f in files:
        w = parse_wheel_filename(f.file)
        if w != None:
            parsed.append((f, w))
    for tag in tags:
        for f, w in parsed:
            if wheel_matches_tag(w, tag):
                return f
    return None

def pypi_url(filename: str) -> str:
    """Build a PyPI download URL from a wheel filename.

    Uses the redirect-capable path layout:
      https://files.pythonhosted.org/packages/{python}/{initial}/{name}/{filename}
    which 302-redirects to the canonical blake2b-hashed path.
    """
    w = parse_wheel_filename(filename)
    if w == None:
        fail("Not a wheel: " + filename)
    return "https://files.pythonhosted.org/packages/{}/{}/{}/{}".format(
        w.python,
        w.name[0],
        w.name,
        filename,
    )

def wheel_url(wf: WheelFile) -> str:
    """Return the download URL for a wheel file, constructing one if needed."""
    if wf.url != None:
        return wf.url
    return pypi_url(wf.file)

def normalize(name: str) -> str:
    """PEP 503 normalize a package name (lowercase, collapse [-_.] to -)."""
    return name.lower().replace("_", "-").replace(".", "-")

def module_name(name: str) -> str:
    """Derive the Python module name from a package name (hyphens/dots → underscores)."""
    return name.lower().replace("-", "_").replace(".", "_")

_HEX_DIGITS = "0123456789abcdefABCDEF"

# Characters a wheel filename can contain: names and tags are `[A-Za-z0-9._]`,
# versions add `+` (local) and `!` (epoch), and `-` separates the parts. All of
# them are valid in a target name.
_WHEEL_FILENAME_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-+!"

def percent_decode(s: str) -> str:
    """Decode `%XX` escapes, e.g. the `%2B` in PyTorch's `torch-2.11.0%2Bcpu-...whl`.

    Only escapes of characters that can appear in a wheel filename are accepted.
    Anything else, like `%2F` (`/`) or `%25` (`%`), would decode into an invalid
    target name, and decoding a UTF-8 byte sequence one byte per character would
    silently produce garbage.
    """
    chunks = s.split("%")
    decoded = [chunks[0]]
    for chunk in chunks[1:]:
        escape = chunk[:2]
        if len(escape) != 2 or escape[0] not in _HEX_DIGITS or escape[1] not in _HEX_DIGITS:
            fail("Malformed percent escape `%{}` in `{}`".format(escape, s))
        byte = int(escape, 16)
        if byte >= 0x80:
            fail("Non-ASCII percent escape `%{}` in `{}`".format(escape, s))
        char = chr(byte)
        if char not in _WHEEL_FILENAME_CHARS:
            fail("Percent escape `%{}` in `{}` decodes to {}, which cannot appear in a wheel filename".format(escape, s, repr(char)))
        decoded.append(char + chunk[2:])
    return "".join(decoded)

def url_filename(url: str) -> str:
    """Extract the filename from a URL, decoded: a target name cannot contain `%`.

    Drops any query string or fragment first, e.g. the signature on a
    pre-signed S3 URL, which would otherwise hide the `.whl` suffix.
    """
    path = url.split("#", 1)[0].split("?", 1)[0]
    return percent_decode(path.rsplit("/", 1)[-1])

def multi_version_set(lock_data: dict) -> dict:
    """Return {normalized_name: True} for packages that appear with multiple versions."""
    counts = {}
    for pkg in lock_data["package"]:
        source = pkg.get("source", {})
        if type(source) == "dict" and (source.get("virtual") != None or source.get("editable") != None):
            continue
        n = normalize(pkg["name"])
        counts[n] = counts.get(n, 0) + 1
    return {n: True for n, c in counts.items() if c > 1}

def versioned_dep_name(dep: dict, multi_version: dict) -> str:
    """Return the target name for a dep entry, versioned when the dep has multiple versions."""
    name = normalize(dep["name"])
    version = dep.get("version")
    if version != None and multi_version.get(name):
        return "{}-{}".format(name, version)
    return name

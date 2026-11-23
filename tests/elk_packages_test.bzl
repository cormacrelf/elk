"""Test for the elk_packages macro: which targets it declares and what it downloads.

Runs inside //tests:BUCK, since a macro can only declare targets while a BUCK
file is being evaluated. Downloads go to a recording fake, so nothing is fetched.
"""

load("@prelude//:asserts.bzl", "asserts")
load("//:elk.bzl", "elk_packages", "uv_packages")

_TORCH_LINUX_URL = "https://download.pytorch.org/whl/cpu/torch-2.11.0%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl"
_TORCH_LINUX = "torch-2.11.0+cpu-cp312-cp312-manylinux_2_28_x86_64.whl"
_TORCH_WIN_URL = "https://download.pytorch.org/whl/cpu/torch-2.11.0%2Bcpu-cp312-cp312-win_amd64.whl"
_TORCH_WIN = "torch-2.11.0+cpu-cp312-cp312-win_amd64.whl"
_SIX_URL = "https://files.pythonhosted.org/packages/ab/cd/six-1.16.0-py2.py3-none-any.whl?X-Amz-Signature=ab%2Fcd"
_SIX = "six-1.16.0-py2.py3-none-any.whl"

_LOCK = {
    "package": [
        {
            "name": "torch",
            "version": "2.11.0+cpu",
            "dependencies": [{"name": "six"}, {"name": "sdist-only"}],
            "wheels": [
                {"url": _TORCH_LINUX_URL, "hash": "sha256:00"},
                {"url": _TORCH_WIN_URL, "hash": "sha256:11"},
            ],
        },
        {
            "name": "six",
            "version": "1.16.0",
            "wheels": [{"url": _SIX_URL, "hash": "sha256:22"}],
        },
        {
            "name": "sdist-only",
            "version": "1.0",
            "sdist": {"url": "https://example.com/sdist-only-1.0.tar.gz", "hash": "sha256:33"},
        },
    ],
}

def _recording_downloader():
    """Return (downloader, calls): a fake http_file and the kwargs of each call to it."""
    calls = {}

    def downloader(*, name: str, urls: list[str], sha256: str):
        calls[name] = struct(urls = urls, sha256 = sha256)
        native.filegroup(name = name, srcs = [])

    return downloader, calls

def test_elk_packages():
    """Declares targets from a fake uv lock and checks them."""
    downloader, calls = _recording_downloader()
    elk_packages(
        packages = uv_packages(_LOCK),
        platform_tags = {
            "linux-x86_64": ["cp312-cp312-manylinux_2_28_x86_64", "py3-none-any"],
            "windows-msvc": ["cp312-cp312-win_amd64", "py3-none-any"],
        },
        downloader = downloader,
    )

    # Targets are named after decoded file names; URLs stay encoded, and the
    # `sha256:` prefix is stripped.
    asserts.equals({
        _TORCH_LINUX: struct(urls = [_TORCH_LINUX_URL], sha256 = "00"),
        _TORCH_WIN: struct(urls = [_TORCH_WIN_URL], sha256 = "11"),
        _SIX: struct(urls = [_SIX_URL], sha256 = "22"),
    }, calls)

    for name in [_TORCH_LINUX, _TORCH_WIN, _SIX]:
        asserts.true(native.rule_exists(name + "-built"), "missing :{}-built".format(name))
    for name in ["torch", "six", "_elk_null"]:
        asserts.true(native.rule_exists(name), "missing :" + name)

    # No wheels means no alias, so nothing can depend on it.
    asserts.false(native.rule_exists("sdist-only"), "unexpected :sdist-only")

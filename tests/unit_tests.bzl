"""Unit tests for elk.bzl's lock-file adapters and the pure helpers in
//private:helpers.bzl. Run by //tests:BUCK."""

load("@prelude//:asserts.bzl", "asserts")
load("//:elk.bzl", "poetry_packages", "uv_deps", "uv_packages")
load(
    "//private:helpers.bzl",
    "Package",
    "WheelFile",
    "WheelInfo",
    "choose_wheel",
    "module_name",
    "multi_version_set",
    "normalize",
    "parse_wheel_filename",
    "percent_decode",
    "pypi_url",
    "url_filename",
    "versioned_dep_name",
    "wheel_matches_tag",
)

_TORCH_CPU_URL = "https://download.pytorch.org/whl/cpu/torch-2.11.0%2Bcpu-cp312-cp312-manylinux_2_28_x86_64.whl"
_TORCH_CPU_FILE = "torch-2.11.0+cpu-cp312-cp312-manylinux_2_28_x86_64.whl"

def _test_normalize():
    asserts.equals("typing-extensions", normalize("Typing_Extensions"))
    asserts.equals("zope-interface", normalize("zope.interface"))
    asserts.equals("already-normal", normalize("already-normal"))

def _test_module_name():
    asserts.equals("lib_common", module_name("Lib-Common"))
    asserts.equals("zope_interface", module_name("zope.interface"))

def _test_parse_wheel_filename():
    asserts.equals(
        WheelInfo(
            name = "six",
            version = "1.16.0",
            python = "py2.py3",
            python_tags = ["py2", "py3"],
            abi_tags = ["none"],
            platform_tags = ["any"],
        ),
        parse_wheel_filename("six-1.16.0-py2.py3-none-any.whl"),
    )

    # Optional build tag is accepted and ignored.
    w = parse_wheel_filename("foo-1.0-1build-cp312-cp312-linux_x86_64.whl")
    asserts.equals(("foo", "1.0", "cp312"), (w.name, w.version, w.python))

    # Compressed platform tag sets.
    w = parse_wheel_filename("numpy-2.0.0-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl")
    asserts.equals(["manylinux_2_17_x86_64", "manylinux2014_x86_64"], w.platform_tags)

    # Local version and epoch survive, since they contain no `-`.
    asserts.equals("2.11.0+cpu", parse_wheel_filename(_TORCH_CPU_FILE).version)
    asserts.equals("1!2.0", parse_wheel_filename("foo-1!2.0-py3-none-any.whl").version)

    asserts.equals(None, parse_wheel_filename("foo-1.0.tar.gz"))
    asserts.equals(None, parse_wheel_filename("foo-1.0-py3-none.whl"))
    asserts.equals(None, parse_wheel_filename("a-b-c-d-e-f-g.whl"))

def _test_wheel_matches_tag():
    w = parse_wheel_filename("six-1.16.0-py2.py3-none-any.whl")
    asserts.true(wheel_matches_tag(w, "py3-none-any"))
    asserts.true(wheel_matches_tag(w, "py2-none-any"))
    asserts.false(wheel_matches_tag(w, "cp312-none-any"))
    asserts.false(wheel_matches_tag(w, "py3-none"))

def _test_choose_wheel():
    linux = WheelFile(file = "foo-1.0-cp312-cp312-manylinux_2_17_x86_64.whl", hash = "sha256:00")
    pure = WheelFile(file = "foo-1.0-py3-none-any.whl", hash = "sha256:11")
    sdist = WheelFile(file = "foo-1.0.tar.gz", hash = "sha256:22")
    files = [sdist, pure, linux]

    # Tag priority decides, not file order.
    asserts.equals(linux, choose_wheel(files, ["cp312-cp312-manylinux_2_17_x86_64", "py3-none-any"]))
    asserts.equals(pure, choose_wheel(files, ["py3-none-any", "cp312-cp312-manylinux_2_17_x86_64"]))
    asserts.equals(None, choose_wheel(files, ["cp312-cp312-win_amd64"]))
    asserts.equals(None, choose_wheel([sdist], ["py3-none-any"]))

def _test_pypi_url():
    asserts.equals(
        "https://files.pythonhosted.org/packages/py2.py3/s/six/six-1.16.0-py2.py3-none-any.whl",
        pypi_url("six-1.16.0-py2.py3-none-any.whl"),
    )

def _test_percent_decode():
    asserts.equals("no-escapes", percent_decode("no-escapes"))
    asserts.equals("", percent_decode(""))
    asserts.equals("a+b+c", percent_decode("a%2Bb%2bc"))
    asserts.equals("!start", percent_decode("%21start"))
    asserts.equals("end_", percent_decode("end%5F"))
    asserts.equals("a-b.c", percent_decode("a%2Db%2Ec"))

def _test_url_filename():
    asserts.equals(_TORCH_CPU_FILE, url_filename(_TORCH_CPU_URL))
    asserts.equals(
        "foo-1.0-py3-none-any.whl",
        url_filename("https://example.com/a/foo-1.0-py3-none-any.whl"),
    )

    # Query strings and fragments are dropped before decoding, including any
    # escapes inside them.
    asserts.equals(
        "foo-1.0-py3-none-any.whl",
        url_filename("https://bucket.s3.amazonaws.com/foo-1.0-py3-none-any.whl?X-Amz-Signature=ab%2Fcd&x=1"),
    )
    asserts.equals(
        "foo-1.0-py3-none-any.whl",
        url_filename("https://example.com/foo-1.0-py3-none-any.whl#sha256=abc"),
    )
    asserts.equals(
        "foo-1!2.0-py3-none-any.whl",
        url_filename("https://example.com/foo-1%212.0-py3-none-any.whl?a=b#c"),
    )

_UV_LOCK = {
    "package": [
        {
            "name": "example",
            "version": "0.1.0",
            "source": {"virtual": "."},
            "dependencies": [{"name": "torch"}, {"name": "Typing_Extensions"}],
        },
        {
            "name": "member",
            "version": "0.1.0",
            "source": {"editable": "packages/member"},
        },
        {
            "name": "torch",
            "version": "2.11.0+cpu",
            "source": {"registry": "https://download.pytorch.org/whl/cpu"},
            "dependencies": [{"name": "typing-extensions", "version": "4.12.2"}],
            "wheels": [{"url": _TORCH_CPU_URL, "hash": "sha256:00"}],
        },
        {
            "name": "typing-extensions",
            "version": "4.12.2",
            "source": {"registry": "https://pypi.org/simple"},
            "wheels": [{"url": "https://files.pythonhosted.org/packages/ab/cd/typing_extensions-4.12.2-py3-none-any.whl", "hash": "sha256:11"}],
        },
        {
            "name": "typing-extensions",
            "version": "4.5.0",
            "source": {"registry": "https://pypi.org/simple"},
            "wheels": [{"url": "https://files.pythonhosted.org/packages/ef/01/typing_extensions-4.5.0-py3-none-any.whl", "hash": "sha256:22"}],
        },
    ],
}

def _test_uv_packages():
    pkgs = uv_packages(_UV_LOCK)

    # The virtual root and editable workspace members are skipped.
    asserts.equals([
        ("torch", "2.11.0+cpu"),
        ("typing-extensions", "4.12.2"),
        ("typing-extensions", "4.5.0"),
    ], [(p.name, p.version) for p in pkgs])

    # File names are decoded; URLs are passed through untouched.
    asserts.equals(Package(
        name = "torch",
        version = "2.11.0+cpu",
        files = [WheelFile(file = _TORCH_CPU_FILE, hash = "sha256:00", url = _TORCH_CPU_URL)],
        # typing-extensions has two versions, so deps on it are versioned.
        deps = ["typing-extensions-4.12.2"],
    ), pkgs[0])

def _test_multi_version():
    multi = multi_version_set(_UV_LOCK)
    asserts.equals({"typing-extensions": True}, multi)
    asserts.equals("torch", versioned_dep_name({"name": "torch"}, multi))
    asserts.equals("typing-extensions-4.5.0", versioned_dep_name({"name": "Typing_Extensions", "version": "4.5.0"}, multi))

def _test_uv_deps():
    # A dep without a version stays unversioned, even if it is ambiguous.
    asserts.equals([":torch", ":typing-extensions"], uv_deps(_UV_LOCK, "Example"))
    asserts.equals([":typing-extensions-4.12.2"], uv_deps(_UV_LOCK, "torch"))
    asserts.equals([], uv_deps(_UV_LOCK, "missing"))

def _test_poetry_packages():
    lock = {
        "package": [{
            "name": "requests",
            "version": "2.32.3",
            "dependencies": {"Charset_Normalizer": ">=2", "idna": ">=2.5"},
            "files": [
                {"file": "requests-2.32.3-py3-none-any.whl", "hash": "sha256:33"},
                {"file": "requests-2.32.3.tar.gz", "hash": "sha256:44"},
            ],
        }],
    }
    asserts.equals([Package(
        name = "requests",
        version = "2.32.3",
        files = [
            WheelFile(file = "requests-2.32.3-py3-none-any.whl", hash = "sha256:33"),
            WheelFile(file = "requests-2.32.3.tar.gz", hash = "sha256:44"),
        ],
        deps = ["charset-normalizer", "idna"],
    )], poetry_packages(lock))

_TESTS = [
    _test_normalize,
    _test_module_name,
    _test_parse_wheel_filename,
    _test_wheel_matches_tag,
    _test_choose_wheel,
    _test_pypi_url,
    _test_percent_decode,
    _test_url_filename,
    _test_uv_packages,
    _test_multi_version,
    _test_uv_deps,
    _test_poetry_packages,
]

def run_unit_tests():
    """Runs every test above. The first failure aborts with its traceback."""
    for test in _TESTS:
        test()

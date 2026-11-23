"""Driver for //tests/expect_fail. See cases.bzl."""

# run.sh looks for this marker in the output to find the expected message.
_MARKER = "elk-expect-fail: "

def expect_fail(message: str):
    """Declares the fail() message the rest of the case must produce."""
    print(_MARKER + message)

def _case_name(case: typing.Callable) -> str:
    # str() of a def is `path/to/file.bzl._name`.
    return str(case).rsplit(".", 1)[-1].lstrip("_")

def expect_fail_package(cases: list[typing.Callable]):
    """Lists `cases` as targets, or runs the one named by `elk_tests.expect_fail`."""
    by_name = {_case_name(case): case for case in cases}
    selected = read_config("elk_tests", "expect_fail")
    if selected == None:
        # One target per case, so run.sh can list them.
        for name in by_name:
            native.filegroup(name = name, srcs = [])
        return

    case = by_name.get(selected)
    if case == None:
        fail("unknown expect_fail case `{}`".format(selected))
    case()
    fail(_MARKER + "case returned without failing")

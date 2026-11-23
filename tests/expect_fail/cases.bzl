"""Inputs that elk.bzl must reject.

Each case calls expect_fail() with the message it must fail() with, then does
the failing thing. fail() can't be caught in Starlark, so run.sh evaluates
//tests/expect_fail once per case, selected with `-c elk_tests.expect_fail=<case>`,
and checks the error. A case's name is its function name without the leading `_`.
"""

load("//private:helpers.bzl", "pypi_url", "url_filename")
load(":runner.bzl", "expect_fail")

def _percent_escape_bare():
    expect_fail("Malformed percent escape `%` in `foo%`")
    url_filename("https://example.com/foo%")

def _percent_escape_truncated():
    expect_fail("Malformed percent escape `%2` in `foo%2`")
    url_filename("https://example.com/foo%2")

def _percent_escape_not_hex():
    expect_fail("Malformed percent escape `%zz` in `foo%zz.whl`")
    url_filename("https://example.com/foo%zz.whl")

def _percent_escape_non_ascii():
    expect_fail("Non-ASCII percent escape `%C3`")
    url_filename("https://example.com/caf%C3%A9-1.0-py3-none-any.whl")

def _percent_escape_percent():
    expect_fail("Percent escape `%25` in `100%2541.whl` decodes to \"%\", which cannot appear in a wheel filename")
    url_filename("https://example.com/100%2541.whl")

def _percent_escape_slash():
    expect_fail("Percent escape `%2F` in `a%2Fb.whl` decodes to \"/\"")
    url_filename("https://example.com/a%2Fb.whl")

def _percent_escape_space():
    expect_fail("Percent escape `%20` in `a%20b.whl` decodes to \" \"")
    url_filename("https://example.com/a%20b.whl")

def _pypi_url_not_a_wheel():
    expect_fail("Not a wheel: foo-1.0.tar.gz")
    pypi_url("foo-1.0.tar.gz")

CASES = [
    _percent_escape_bare,
    _percent_escape_truncated,
    _percent_escape_not_hex,
    _percent_escape_non_ascii,
    _percent_escape_percent,
    _percent_escape_slash,
    _percent_escape_space,
    _pypi_url_not_a_wheel,
]

load("@prelude//:prelude.bzl", "native")
load("@prelude//rust:cargo_package.bzl", "get_reindeer_platforms")
load("@prelude//utils:selects.bzl", "selects")

prelude = native

def apply_platform_attr(platform_attr, default_value):
    """Resolve a {platform_name: value} dict using buck2's select() mechanism."""
    return selects.apply(
        get_reindeer_platforms(),
        lambda platform: platform_attr.get(platform, default_value),
    )

def _alias(name, **kwargs):
    actual = kwargs.pop("actual", ":null")
    if type(actual) == "dict":
        actual = apply_platform_attr(actual, ":null")
    return prelude.alias(name = name, actual = actual, **kwargs)

platform = struct(
    alias = _alias,
)

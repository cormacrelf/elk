load("@prelude//:prelude.bzl", "native")
load("@prelude//rust:cargo_package.bzl", "DEFAULT_PLATFORM_TEMPLATES")
load("@prelude//utils:selects.bzl", "selects")

prelude = native

# This code is based on @prelude//rust:cargo_package.bzl
# However it's only for a single attribute. Elk's BUCK output is cleaner this way.
# We can `apply_platform_attrs` for a `platform.prebuilt_python_library` macro
# if we want extra dependencies on some platforms only.
def apply_platform_attr(
        platform_attr,
        default_value,
        templates = DEFAULT_PLATFORM_TEMPLATES):
    chosen = default_value

    for platform, value in platform_attr.items():
        template = templates.get(platform, None)
        if template:
            chosen = selects.apply(template, lambda cond: value if cond else chosen)

    return chosen

def _alias(name, **kwargs):
    actual = kwargs.pop("actual", ":null")
    platform = kwargs.pop("platform", {})
    actual = apply_platform_attr(platform, actual)
    return prelude.alias(name = name, actual = actual, **kwargs)

platform = struct(
    alias = _alias,
)

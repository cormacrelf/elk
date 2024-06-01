prelude = native

# FIXME: gotta do more than this
#
def _alias(name, **kwargs):
    actual = kwargs.pop("actual", None)
    platform = kwargs.pop("platform", {})
    return prelude.alias(name = name, actual = actual or platform["macos-arm64"], **kwargs)

platform = struct(
    alias = _alias,
)

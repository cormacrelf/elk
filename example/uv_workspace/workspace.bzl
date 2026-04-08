load("@elk//:elk.bzl", "create_workspace_member_macro")
load(":uv.lock.toml", lock = "value")

workspace_member = create_workspace_member_macro(
    lock_data = lock,
    root = "//example/uv_workspace",
)

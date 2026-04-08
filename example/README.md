# Elk example

Elk manages Python dependencies for Buck2 with zero code generation.
Your lock file is read directly by Starlark at analysis time.

## Prerequisites

- A recent `buck2`
- One of: `uv`, `poetry`

## Quick start (uv)

1. Lock your dependencies and create the symlink Buck2 needs:

       uv lock
       ln -s uv.lock uv.lock.toml

2. Generate a platform tags file (once per target machine):

       buck2 run elk//tools:save_tags -- linux-x86_64.tags.json

3. The BUCK file loads everything directly - no codegen step:

       load("//:elk.bzl", "elk_packages", "uv_packages")
       load(":linux-x86_64.tags.json", linux_x86_64_tags = "value")
       load(":uv.lock.toml", lock = "value")

       elk_packages(
           packages = uv_packages(lock),
           platform_tags = {
               "linux-x86_64": linux_x86_64_tags,
           },
       )

   uv.lock includes full download URLs, so wheels are fetched directly
   without a redirect.

4. Build and run:

       buck2 run :main

### Adding dependencies

    uv add requests
    buck2 build //uv:requests

No regeneration step needed. Buck2 reads the updated lock file directly.

You still need to add `//uv:requests` to the `deps` of your
`python_binary` in `example/BUCK`.

## Quick start (poetry)

1. Lock your dependencies and create the symlink Buck2 needs:

       poetry lock
       ln -s poetry.lock poetry.lock.toml

2. Generate a platform tags file (once per target machine).
   With the elk poetry plugin installed:

       poetry elk-save-tags linux-x86_64

   Or without elk installed:

       buck2 run elk//tools:save_tags -- linux-x86_64.tags.json

3. The BUCK file loads everything directly - no codegen step:

       load("//:elk.bzl", "elk_packages", "poetry_packages")
       load(":linux-x86_64.tags.json", linux_x86_64_tags = "value")
       load(":poetry.lock.toml", lock = "value")

       elk_packages(
           packages = poetry_packages(lock),
           platform_tags = {
               "linux-x86_64": linux_x86_64_tags,
           },
       )

4. Build and run:

       buck2 run :main

### Adding dependencies

    poetry add requests
    poetry lock
    buck2 build //poetry:requests

No regeneration step needed. Buck2 reads the updated lock file directly.

You still need to add `//poetry:requests` to the `deps` of your
`python_binary` in `example/BUCK`.

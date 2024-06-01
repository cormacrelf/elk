#!/usr/bin/env bash

# Have buck build us a precise virtualenv for exactly the dependencies
# of a particular target, using e.g. the `:main[link-tree]` subtarget
#
# And then execute the rest of the arguments as a command in that
# virtualenv.
#
# Usage:
#
# ./venv.sh :main [command args]
#
# Example
#
# ./venv.sh :main nvim main.py          # lets you use LSP, like pyright

TARGET="$1"
shift
PYTHONPATH="$(buck2 root)/$(buck2 build "${TARGET}[link-tree]" --show-simple-output)"
export PYTHONPATH
exec "$@"

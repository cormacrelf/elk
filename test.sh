#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Set up a venv with poetry and elk installed together
python3 -m venv .venv --clear
source .venv/bin/activate
pip install poetry .

# Check the example builds
cd example
buck2 build :main :other

# Check elk produces the same BUCK file
poetry -C pypi elk
git diff --exit-code --color=always pypi/BUCK

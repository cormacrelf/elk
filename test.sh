#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Set up a venv with poetry and elk installed together
python3 -m venv .venv --clear
source .venv/bin/activate
pip install poetry .

# Generate tags file for the current platform
cd example/pypi
poetry elk-save-tags linux-x86_64

# Check the example builds
cd ..
buck2 build :main :other

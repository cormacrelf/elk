#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Generate tags file for the current platform
buck2 run elk//tools:save_tags example/poetry/linux-x86_64.tags.json
buck2 run elk//tools:save_tags example/uv/linux-x86_64.tags.json

# Check the example builds
buck2 run //example/poetry:main
buck2 run //example/poetry:other
buck2 run //example/uv:main
buck2 run //example/uv:other
buck2 run //example/custom_platforms:main

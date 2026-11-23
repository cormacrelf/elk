#!/usr/bin/env bash
# Runs the Starlark tests in //tests. No network access needed.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== unit tests"
buck2 targets //tests: >/dev/null

echo "== expect_fail tests"
cases=$(buck2 targets //tests/expect_fail: | sed 's/.*://')
failures=0
for case in $cases; do
    if out=$(buck2 targets //tests/expect_fail: -c elk_tests.expect_fail="$case" 2>&1); then
        echo "FAIL $case: evaluation succeeded"
        failures=$((failures + 1))
        continue
    fi
    expect=$(sed -n 's/.*elk-expect-fail: //p' <<<"$out" | head -n 1)
    if [[ -z "$expect" ]]; then
        echo "FAIL $case: no expect_fail() message was printed:"
        echo "$out"
        failures=$((failures + 1))
    elif ! grep -v 'elk-expect-fail: ' <<<"$out" | grep -qF -- "$expect"; then
        echo "FAIL $case: error does not contain: $expect"
        echo "$out"
        failures=$((failures + 1))
    else
        echo "ok   $case"
    fi
done

if ((failures > 0)); then
    echo "$failures expect_fail case(s) failed"
    exit 1
fi

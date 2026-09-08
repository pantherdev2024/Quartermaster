#!/bin/bash
# BarLayout.js is plain JavaScript with no QML in it, which is what lets node
# run it directly. Every other suite here drives a shell script; this one
# drives the bar layout model.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

skip() { printf 'barlayout-test: skipped (%s)\n' "$1"; exit 0; }

command -v node >/dev/null 2>&1 || skip "node not installed"

# node --test is chatty on success and the run script prints one line per
# suite, so the output is only worth showing when something fails.
if ! output=$(node --test "$ROOT/barlayout.test.js" 2>&1); then
  printf '%s\n' "$output" >&2
  printf 'FAIL: the bar layout model\n' >&2
  exit 1
fi

printf 'barlayout-test: ok\n'

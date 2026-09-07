#!/bin/bash
# The two checks the development guide pairs: Omarchy validates the manifest
# and the folder layout, qmllint checks every QML file against the shell's own
# imports. Both are expected to exit clean.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SHELL_DIR="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'qml-test: skipped (%s)\n' "$1"; exit 0; }

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$ROOT" || fail "omarchy plugin validate rejected the plugin"
fi

QMLLINT=$(command -v qmllint || true)
[[ -n $QMLLINT ]] || QMLLINT=$(ls /usr/lib/qt6/bin/qmllint 2>/dev/null || true)
[[ -n $QMLLINT ]] || skip "qmllint not installed"
[[ -d $SHELL_DIR ]] || skip "no Omarchy shell at $SHELL_DIR to lint against"

# Warnings are noise here: the shell's own plugins raise the same unqualified
# lookups and the same missing QProcess::ExitStatus on every Process.onExited.
# An Error is a file that will not load, which is the thing worth failing on.
status=0
for file in "$ROOT"/*.qml; do
  errors=$("$QMLLINT" -I "$SHELL_DIR" -I "$ROOT" "$file" 2>&1 | grep '^Error' || true)
  if [[ -n $errors ]]; then
    printf 'FAIL: %s\n%s\n' "${file##*/}" "$errors" >&2
    status=1
  fi
done
(( status == 0 )) || exit 1

printf 'qml-test: ok\n'

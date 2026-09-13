#!/bin/bash
# The two checks the development guide pairs: Omarchy validates the manifest
# and the folder layout, qmllint checks every QML file against the shell's own
# imports. Both are expected to exit clean. Before either, a check of our own:
# every Text that shows anything other than a fixed string is plain text.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SHELL_DIR="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'qml-test: skipped (%s)\n' "$1"; exit 0; }

# Names, descriptions and status strings come from the theme repository, the
# catalogue, the filesystem and synced loadouts, none of which this plugin
# controls. A Text renders those as styled text unless told otherwise, so any
# Text whose text is not a string literal has to carry textFormat:
# Text.PlainText. Text blocks are matched by their indentation, which is how
# every file here is laid out.
unguarded=$(awk '
  function close_block() {
    if (open && found && !literal && !plain) printf "%s:%d  %s\n", FILENAME, openline, txt
    open = 0
  }
  FNR == 1 { close_block() }
  /^ *(delegate: *)?Text *\{ *$/ {
    close_block()
    match($0, /^ */); ind = RLENGTH
    open = 1; openline = FNR; found = 0; literal = 0; plain = 0; txt = ""
    next
  }
  /^ *Text *\{.*\} *$/ {
    if ($0 !~ /textFormat: *Text\.PlainText/ && $0 !~ /text: *"([^"\\]|\\.)*" *[;}]/)
      printf "%s:%d  %s\n", FILENAME, FNR, $0
    next
  }
  open {
    if (substr($0, 1, ind + 1) == sprintf("%" ind "s}", "")) { close_block(); next }
    if (substr($0, 1, ind + 2) != sprintf("%" (ind + 2) "s", "")) next
    rest = substr($0, ind + 3)
    if (rest ~ /^textFormat: *Text\.PlainText/) plain = 1
    if (!found && rest ~ /^text:/) {
      found = 1; txt = rest
      if (rest ~ /^text: *"([^"\\]|\\.)*" *$/) literal = 1
    }
  }
  END { close_block() }
' "$ROOT"/*.qml)
[[ -z $unguarded ]] || fail "Text sinks showing untrusted strings without textFormat: Text.PlainText:
$unguarded"

# Wallpapers and previews are files a theme repository shipped. An Image with
# no sourceSize decodes one at whatever size it is, in the shell's process, so
# every Image whose source is not a fixed string has to bound its decode.
unbounded=$(awk '
  function close_block() {
    if (open && found && !literal && !bounded) printf "%s:%d  %s\n", FILENAME, openline, txt
    open = 0
  }
  FNR == 1 { close_block() }
  /^ *Image *\{ *$/ {
    close_block()
    match($0, /^ */); ind = RLENGTH
    open = 1; openline = FNR; found = 0; literal = 0; bounded = 0; txt = ""
    next
  }
  open {
    if (substr($0, 1, ind + 1) == sprintf("%" ind "s}", "")) { close_block(); next }
    if (substr($0, 1, ind + 2) != sprintf("%" (ind + 2) "s", "")) next
    rest = substr($0, ind + 3)
    if (rest ~ /^sourceSize(\.width|\.height)?:/) bounded = 1
    if (!found && rest ~ /^source:/) {
      found = 1; txt = rest
      if (rest ~ /^source: *"([^"\\]|\\.)*" *$/) literal = 1
    }
  }
  END { close_block() }
' "$ROOT"/*.qml)
[[ -z $unbounded ]] || fail "Image sources from outside the plugin without a sourceSize bound:
$unbounded"

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

#!/bin/bash
# safe-io.sh is the one place the plugin's scripts touch the filesystem, so it
# is the one place worth testing directly rather than only through its
# callers. Everything here runs against directories made for the test.

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

# shellcheck source=../safe-io.sh
source "$ROOT/safe-io.sh" || { echo "FAIL: cannot source safe-io.sh" >&2; exit 1; }

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
equals() {
  [[ $2 == "$3" ]] || fail "$1: expected $(printf '%q' "$3"), got $(printf '%q' "$2")"
}

# ---- io_dir ----------------------------------------------------------------

# A directory that is not there is created, and `private` means created shut.
io_dir "$TMP/fresh" private || fail "io_dir could not create a private directory"
equals "private dirs are created shut" "$(stat -c %a "$TMP/fresh")" "700"
io_dir "$TMP/shared" || fail "io_dir could not create a shared directory"
[[ -d "$TMP/shared" ]] || fail "io_dir did not create the shared directory"

# An existing private directory left open by an older version is tightened
# rather than refused, so an install that predates this keeps working.
chmod 755 "$TMP/fresh"
io_dir "$TMP/fresh" private || fail "io_dir refused a directory it could tighten"
equals "a loose private dir is tightened" "$(stat -c %a "$TMP/fresh")" "700"

# A directory this plugin shares with Omarchy keeps the mode Omarchy gave it.
chmod 755 "$TMP/shared"
io_dir "$TMP/shared" || fail "io_dir refused a normal shared directory"
equals "a shared dir keeps its mode" "$(stat -c %a "$TMP/shared")" "755"

# But not if anyone else can write into it, because then nothing inside it
# can be trusted to still be what this plugin put there.
# That holds whether or not the directory is one this plugin owns outright: a
# mode a normal umask never produces is evidence rather than an old default,
# so it is refused instead of quietly tightened.
chmod 777 "$TMP/shared"
io_dir "$TMP/shared" 2>/dev/null && fail "io_dir accepted a world-writable directory"
chmod 755 "$TMP/shared"
chmod 777 "$TMP/fresh"
io_dir "$TMP/fresh" private 2>/dev/null && fail "io_dir tightened a world-writable private dir instead of refusing"
equals "and left it as found" "$(stat -c %a "$TMP/fresh")" "777"
chmod 700 "$TMP/fresh"

# A link standing in for a directory is refused, however ordinary the thing it
# points at: following it would move every later read and write somewhere else.
mkdir -p "$TMP/real"
ln -s "$TMP/real" "$TMP/linked"
io_dir "$TMP/linked" 2>/dev/null && fail "io_dir accepted a link to a directory"
io_dir "$TMP/linked" private 2>/dev/null && fail "io_dir accepted a link as a private directory"

# So is a plain file wearing a directory's name.
: > "$TMP/notadir"
io_dir "$TMP/notadir" 2>/dev/null && fail "io_dir accepted a file"

# ---- io_plain --------------------------------------------------------------

: > "$TMP/fresh/plain"
io_plain "$TMP/fresh/plain" || fail "io_plain rejected a plain file"
io_plain "$TMP/fresh/absent" || fail "io_plain rejected a name with nothing at it"
ln -s "$TMP/fresh/plain" "$TMP/fresh/link"
io_plain "$TMP/fresh/link" 2>/dev/null && fail "io_plain accepted a link"
mkdir -p "$TMP/fresh/adir"
io_plain "$TMP/fresh/adir" 2>/dev/null && fail "io_plain accepted a directory"

# ---- io_publish ------------------------------------------------------------

io_publish "$TMP/fresh/doc" "hello" || fail "io_publish could not write"
equals "content lands with one trailing newline" "$(cat "$TMP/fresh/doc")" "hello"
equals "one line" "$(wc -l < "$TMP/fresh/doc")" "1"
equals "written shut by default" "$(stat -c %a "$TMP/fresh/doc")" "600"
io_publish "$TMP/fresh/doc" "again" || fail "io_publish could not replace"
equals "replacing works" "$(cat "$TMP/fresh/doc")" "again"
io_publish "$TMP/fresh/open" "x" 644 || fail "io_publish could not take a mode"
equals "the given mode is used" "$(stat -c %a "$TMP/fresh/open")" "644"

# The point of the whole exercise: a link at the destination is replaced, not
# written through, so whatever it pointed at is left alone.
victim="$TMP/victim"
printf 'do not touch\n' > "$victim"
ln -s "$victim" "$TMP/fresh/trap"
io_publish "$TMP/fresh/trap" "payload" 2>/dev/null && fail "io_publish wrote over a link"
equals "the link's target is untouched" "$(cat "$victim")" "do not touch"
[[ -L "$TMP/fresh/trap" ]] || fail "the link itself should be left in place"

# Nothing is left behind when a write cannot be finished.
before=$(find "$TMP/fresh" -maxdepth 1 -name '.*' | wc -l)
io_publish "$TMP/fresh/adir" "payload" 2>/dev/null && fail "io_publish wrote over a directory"
equals "no temporary is left behind" "$(find "$TMP/fresh" -maxdepth 1 -name '.*' | wc -l)" "$before"

# A temporary in flight is named so that nothing globbing for the real thing
# can pick it up while it is being written.
io_publish "$TMP/fresh/thing.json" '{"a":1}' || fail "io_publish could not write json"
equals "no temporary survives a good write" \
  "$(find "$TMP/fresh" -maxdepth 1 -name '.thing.json.*' | wc -l)" "0"

# ---- io_read ---------------------------------------------------------------

printf 'line one\nline two\n' > "$TMP/fresh/readme"
equals "reads what is there" "$(io_read "$TMP/fresh/readme")" "$(printf 'line one\nline two')"
equals "stops at the limit" "$(io_read "$TMP/fresh/readme" 4)" "line"
io_read "$TMP/fresh/absent" 2>/dev/null && fail "io_read read a file that is not there"
io_read "$TMP/fresh/adir" 2>/dev/null && fail "io_read read a directory"

# A link is not followed, so a file outside the directory cannot be read by
# leaving a pointer to it inside.
printf 'secret\n' > "$TMP/secret"
ln -s "$TMP/secret" "$TMP/fresh/peek"
out="$(io_read "$TMP/fresh/peek" 2>/dev/null)" && fail "io_read followed a link"
equals "and nothing came back" "$out" ""

# The bound holds however big the file is, and the cost of reading does not
# follow the size of what is on disk.
head -c 200000 /dev/zero | tr '\0' 'x' > "$TMP/fresh/big"
equals "a big file is read only up to the bound" "$(io_read "$TMP/fresh/big" 1000 | wc -c)" "1000"

printf 'safe-io-test: ok\n'

#!/bin/bash
# loadouts.sh owns the only user data the plugin creates. A saved fitting has
# to survive the round trip byte for byte, because equipping a loadout is
# staging what came back out of it.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export XDG_DATA_HOME="$TMP/data"
LOADOUTS="$ROOT/loadouts.sh"
DIR="$XDG_DATA_HOME/omarchy/loadouts"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
equals() {
  [[ $2 == "$3" ]] || fail "$1: expected $(printf '%q' "$3"), got $(printf '%q' "$2")"
}

# An empty store is an empty array, not an error and not null: the QML reads
# it straight into a model.
equals "empty list" "$("$LOADOUTS" list)" "[]"

# Saving prints the id it chose, and the id is a slug of the name.
id=$("$LOADOUTS" save "Desk Setup" '{"theme":"nord","font":"CaskaydiaMono Nerd Font"}')
equals "slugged id" "$id" "desk-setup"
[[ -f "$DIR/desk-setup.json" ]] || fail "no file written for desk-setup"

# The slots object comes back exactly as it went in.
slots=$(jq -c '.slots' "$DIR/desk-setup.json")
equals "slots round trip" "$slots" '{"theme":"nord","font":"CaskaydiaMono Nerd Font"}'
equals "name preserved" "$(jq -r '.name' "$DIR/desk-setup.json")" "Desk Setup"
jq -e '.savedAt | type == "string" and length > 0' "$DIR/desk-setup.json" >/dev/null \
  || fail "savedAt missing"

# A name is user input that becomes a filename, so the slug has to be unable
# to leave the loadouts directory however it is spelled. Accented characters
# survive or fold depending on the locale's collation, which is cosmetic; a
# path separator must not survive in any locale, which is not.
for hostile in '../../etc/passwd' 'a/b/c' './../x'; do
  slug=$("$LOADOUTS" save "$hostile" '{}')
  [[ $slug != */* && $slug != *..* && -n $slug ]] \
    || fail "slug escaped its directory: $hostile -> $slug"
  [[ -f "$DIR/$slug.json" ]] || fail "no file written for $hostile"
done
[[ ! -e "$TMP/data/etc" && ! -e "$DIR/../a" ]] || fail "a save wrote outside the loadouts directory"

# A name with nothing sluggable left in it still gets a usable id rather than
# an empty filename.
weird=$("$LOADOUTS" save '..' '{}')
[[ $weird == loadout-* ]] || fail "unsluggable name should fall back to loadout-<epoch>, got $weird"

# list is newest first, which is the order the dock draws.
sleep 1
"$LOADOUTS" save "Newest" '{}' >/dev/null
equals "newest first" "$("$LOADOUTS" list | jq -r '.[0].name')" "Newest"
equals "count" "$("$LOADOUTS" list | jq 'length')" "6"

# A file that is not a loadout is ignored rather than crashing the list. The
# directory is user-visible and syncable, so something else will end up in it.
printf 'not json at all\n' > "$DIR/junk.json"
printf '{"unrelated":true}\n' > "$DIR/other.json"
equals "junk ignored" "$("$LOADOUTS" list | jq 'length')" "6"

# Deleting is by id and is quiet about an id that is already gone.
"$LOADOUTS" delete desk-setup
equals "after delete" "$("$LOADOUTS" list | jq 'map(select(.id == "desk-setup")) | length')" "0"
"$LOADOUTS" delete desk-setup
"$LOADOUTS" delete never-existed

# A bad verb explains itself and fails, rather than silently doing nothing.
if "$LOADOUTS" nonsense >/dev/null 2>&1; then fail "unknown verb should exit non-zero"; fi

printf 'loadouts-test: ok\n'

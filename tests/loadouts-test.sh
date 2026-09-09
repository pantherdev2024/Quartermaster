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

# Saving with an id overwrites that loadout in place: same file, same id,
# the new name and slots, a fresh time, and nothing new beside it.
before=$("$LOADOUTS" list | jq 'length')
sleep 1
over=$("$LOADOUTS" save "Desk Setup v2" '{"theme":"gruvbox"}' desk-setup)
equals "overwrite keeps the id" "$over" "desk-setup"
equals "overwrite keeps the count" "$("$LOADOUTS" list | jq 'length')" "$before"
equals "overwrite takes the new name" "$(jq -r '.name' "$DIR/desk-setup.json")" "Desk Setup v2"
equals "overwrite takes the new slots" "$(jq -c '.slots' "$DIR/desk-setup.json")" '{"theme":"gruvbox"}'
equals "overwritten is newest" "$("$LOADOUTS" list | jq -r '.[0].id')" "desk-setup"
# An id that is not there, or not safe, is refused rather than created.
"$LOADOUTS" save "Ghost" '{}' never-saved 2>/dev/null && fail "overwriting a missing id should fail"
"$LOADOUTS" save "Escape" '{}' '../escape' 2>/dev/null && fail "an unsafe id should be refused"
[[ ! -e "$DIR/never-saved.json" && ! -e "$DIR/../escape.json" ]] || fail "a refused overwrite wrote a file"

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

# --- an id that arrived from somewhere else ----------------------------
# Saving slugs the name, so an id this script minted cannot escape. Ids also
# come back in off the disk, and the directory is documented as syncable: a
# loadout file from elsewhere carries whatever id it likes, and that id is
# what the delete cross is handed. It must not name a path out of here.
outside="$XDG_DATA_HOME/omarchy/victim.json"
printf 'important\n' > "$outside"
cat > "$DIR/innocent.json" <<'JSON'
{"id":"../victim","name":"Looks Normal","slots":{"theme":"nord"},"savedAt":"2026-01-01T00:00:00-00:00"}
JSON

# It never reaches the screen, so there is no card to press the cross on.
listed=$("$LOADOUTS" list | jq --arg n "Looks Normal" 'map(select(.name == $n)) | length')
equals "hostile id is not listed" "$listed" "0"

# And the verb refuses it outright, however it is called.
for hostile in '../victim' '../../victim' '/etc/passwd' '.' '..' 'a/b'; do
  if "$LOADOUTS" delete "$hostile" 2>/dev/null; then
    fail "delete accepted an unsafe id: $hostile"
  fi
done
[[ -f $outside ]] || fail "delete escaped the loadouts directory"

# The guard rejects an escape, not an unusual name: a slug made under a UTF-8
# locale keeps its accented letters, and those ids are already on disk.
accented=$("$LOADOUTS" save 'Café' '{}')
[[ -f "$DIR/$accented.json" ]] || fail "a legitimate accented id was written wrong"
"$LOADOUTS" delete "$accented"
[[ ! -f "$DIR/$accented.json" ]] || fail "a legitimate accented id could not be deleted"

printf 'loadouts-test: ok\n'

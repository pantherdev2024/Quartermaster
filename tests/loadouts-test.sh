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

# ---- The store is a boundary ------------------------------------------------
# Everything below treats the store the way the script does: as a directory
# that other machines write into, because that is what "syncable" means.

# The store is created closed to everyone else, and an older store made with
# the default mode is tightened rather than refused.
equals "store is private" "$(stat -c %a "$DIR")" "700"
chmod 755 "$DIR"
"$LOADOUTS" list >/dev/null
equals "a loose store is tightened" "$(stat -c %a "$DIR")" "700"

# A saved loadout is the user's own business and nobody else's.
"$LOADOUTS" save "Mode Check" '{}' >/dev/null
equals "saved file is private" "$(stat -c %a "$DIR/mode-check.json")" "600"
"$LOADOUTS" delete mode-check

# A store that is a link to somewhere else is not a store. Listing says so and
# reports empty rather than reading through it, which is what keeps the screen
# opening; saving and deleting refuse outright.
elsewhere="$TMP/elsewhere"
mkdir -p "$elsewhere"
printf '{"id":"planted","name":"Planted","slots":{},"savedAt":"2026-01-01T00:00:00Z"}\n' \
  > "$elsewhere/planted.json"
linked="$TMP/linkstore"
export XDG_DATA_HOME="$linked"
mkdir -p "$linked/omarchy"
ln -s "$elsewhere" "$linked/omarchy/loadouts"
out=$("$LOADOUTS" list 2>/dev/null) || true
equals "a linked store lists empty" "$out" "[]"
"$LOADOUTS" list >/dev/null 2>&1 && fail "a linked store should exit non-zero"
"$LOADOUTS" save "Nope" '{}' >/dev/null 2>&1 && fail "a linked store should refuse a save"
[[ ! -e "$elsewhere/nope.json" ]] || fail "a save reached through the linked store"
equals "the planted file was not read" \
  "$(XDG_DATA_HOME="$linked" "$LOADOUTS" list 2>/dev/null)" "[]"
export XDG_DATA_HOME="$TMP/data"

# A relative XDG_DATA_HOME is not a path. The spec says to ignore it, so the
# store falls back to the default rather than being built from it.
( cd "$TMP" && XDG_DATA_HOME="relative/path" "$LOADOUTS" list >/dev/null 2>&1 ) || true
[[ ! -d "$TMP/relative" ]] || fail "a relative XDG_DATA_HOME was used as a path"

# ---- Saving cannot be redirected -------------------------------------------
# The reason the write goes through a fresh file and a rename: a link sitting
# at the destination must not become a way to write somewhere else.

victim="$TMP/victim.conf"
printf 'do not touch\n' > "$victim"
ln -s "$victim" "$DIR/trap.json"
"$LOADOUTS" save "Trap" '{}' trap >/dev/null 2>&1 && fail "overwriting a link should fail"
"$LOADOUTS" save "Trap" '{}' >/dev/null 2>&1 && fail "saving onto a link should fail"
equals "the link's target is untouched" "$(cat "$victim")" "do not touch"
[[ -L "$DIR/trap.json" ]] || fail "the link itself should be left alone, not replaced"
rm -f "$DIR/trap.json"

# A directory wearing a loadout's name is refused the same way.
mkdir -p "$DIR/dirnamed.json"
"$LOADOUTS" save "Dirnamed" '{}' >/dev/null 2>&1 && fail "saving onto a directory should fail"
[[ -d "$DIR/dirnamed.json" ]] || fail "the directory should be left alone"
rmdir "$DIR/dirnamed.json"

# A save that fails leaves the loadout it was replacing exactly as it was.
# The old form redirected jq at the file, so the file was already empty by the
# time jq rejected its arguments.
"$LOADOUTS" save "Keeper" '{"theme":"nord"}' >/dev/null
before=$(cat "$DIR/keeper.json")
"$LOADOUTS" save "Keeper" 'not json at all' keeper >/dev/null 2>&1 && fail "bad slots should fail"
equals "a failed save changed nothing" "$(cat "$DIR/keeper.json")" "$before"
equals "and the loadout still lists" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == "keeper")) | length')" "1"

# Nothing half-written is ever listed: the temporary a save publishes through
# is named so that a listing running beside it cannot pick it up.
: > "$DIR/.loadout.halfway"
equals "temporaries are not listed" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == null)) | length')" "0"
rm -f "$DIR/.loadout.halfway"

# ---- Listing is bounded ------------------------------------------------------
# The store is read by the long-lived shell process, so no file in it gets to
# decide how much that read costs.

# A link in the store is not followed, however valid the thing it points at.
ln -s "$victim" "$DIR/link.json"
printf '{"id":"sneak","name":"Sneak","slots":{},"savedAt":"2026-01-01T00:00:00Z"}\n' > "$victim"
equals "a linked entry is not read" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == "sneak")) | length')" "0"
rm -f "$DIR/link.json"

# A file past the per-file limit is skipped rather than read whole. The bulk
# sits in a field the filter does not otherwise police, so that what this
# proves is the read limit and not one of the field limits below it.
{ printf '{"id":"huge","name":"Huge","slots":{},"savedAt":"2026-01-01T00:00:00Z","junk":"'
  head -c 70000 /dev/zero | tr '\0' 'x'
  printf '"}\n'; } > "$DIR/huge.json"
[[ $(stat -c %s "$DIR/huge.json") -gt 65536 ]] || fail "the oversized fixture is not oversized"
equals "an oversized file is skipped" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == "huge")) | length')" "0"
rm -f "$DIR/huge.json"

# Neither is a loadout allowed to carry an unbounded number of slots, or a
# field long enough to be a payload rather than a value.
jq -n '{id:"manyslots", name:"Many", savedAt:"2026-01-01T00:00:00Z",
        slots:([range(200)] | map({key:("s"+tostring), value:"v"}) | from_entries)}' \
  > "$DIR/manyslots.json"
equals "too many slots is skipped" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == "manyslots")) | length')" "0"
rm -f "$DIR/manyslots.json"
jq -n --arg long "$(head -c 3000 /dev/zero | tr '\0' 'y')" \
  '{id:"longfield", name:$long, slots:{}, savedAt:"2026-01-01T00:00:00Z"}' \
  > "$DIR/longfield.json"
equals "an overlong field is skipped" \
  "$("$LOADOUTS" list | jq -r 'map(select(.id == "longfield")) | length')" "0"
rm -f "$DIR/longfield.json"

# Only the four fields the screen reads come back out. A planted file does not
# get to hand anything else to the process that asked for the list.
jq -n '{id:"extra", name:"Extra", slots:{}, savedAt:"2026-01-01T00:00:00Z",
        surprise:"payload", "__proto__":"nope"}' > "$DIR/extra.json"
equals "unknown fields are dropped" \
  "$("$LOADOUTS" list | jq -c 'map(select(.id == "extra")) | .[0] | keys')" \
  '["id","name","savedAt","slots"]'
rm -f "$DIR/extra.json"

# A store whose files are each acceptable but which together are not stops at
# the aggregate limit rather than reading all of it into the shell.
heavy="$TMP/heavy"; mkdir -p "$heavy/omarchy/loadouts"
pad=$(head -c 50000 /dev/zero | tr '\0' 'z')
for i in $(seq 1 120); do
  printf '{"id":"h%s","name":"H%s","slots":{},"savedAt":"2026-01-01T00:00:00Z","junk":"%s"}\n' \
    "$i" "$i" "$pad" > "$heavy/omarchy/loadouts/h$i.json"
done
heavy_count=$(XDG_DATA_HOME="$heavy" "$LOADOUTS" list | jq 'length')
(( heavy_count > 0 )) || fail "the aggregate cap swallowed the whole listing"
(( heavy_count < 120 )) || fail "the listing read $heavy_count heavy files, past the aggregate cap"

# A store belonging to somebody else is refused rather than read or written.
# Nothing here can chown a directory away, so the check is reached by telling
# the script it is running as a different user, which is the same comparison.
mkdir -p "$TMP/bin"
printf '#!/bin/bash\n[[ $1 == -u ]] && { echo 999999; exit 0; }\nexec /usr/bin/id "$@"\n' \
  > "$TMP/bin/id"
chmod +x "$TMP/bin/id"
out=$(PATH="$TMP/bin:$PATH" "$LOADOUTS" list 2>/dev/null) || true
equals "a store owned by another user lists empty" "$out" "[]"
PATH="$TMP/bin:$PATH" "$LOADOUTS" save "Foreign" '{}' >/dev/null 2>&1 &&
  fail "a store owned by another user should refuse a save"
[[ ! -e "$DIR/foreign.json" ]] || fail "a save reached a store owned by another user"

# The number of files read at all is capped, so a store someone filled cannot
# make the listing grow without limit.
bulk="$TMP/bulk"; mkdir -p "$bulk"
export XDG_DATA_HOME="$bulk"
mkdir -p "$bulk/omarchy/loadouts"
for i in $(seq 1 600); do
  printf '{"id":"b%s","name":"B%s","slots":{},"savedAt":"2026-01-01T00:00:00Z"}\n' "$i" "$i" \
    > "$bulk/omarchy/loadouts/b$i.json"
done
counted=$("$LOADOUTS" list | jq 'length')
(( counted <= 512 )) || fail "listing read $counted files, past the cap"
(( counted > 0 )) || fail "the cap swallowed the whole listing"
export XDG_DATA_HOME="$TMP/data"

printf 'loadouts-test: ok\n'

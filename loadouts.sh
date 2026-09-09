#!/bin/bash
# Saved loadouts: one JSON file per loadout under the XDG data directory,
# so they survive plugin updates and can be synced like any other user data.
#
#   loadouts.sh list                      -> JSON array, newest first
#   loadouts.sh save <name> <slots> [id]  -> writes the file, prints its id
#   loadouts.sh delete <id>
#
# save with an id overwrites that loadout in place -- same id, the name
# given, fresh slots and time -- which is how a fitting is saved back over
# the loadout it came from instead of minting a new one beside it.
#
# <slots> is a JSON object of slot id -> item id, exactly what the screen
# stages, so equipping a loadout is staging it and pressing ENTER.

set -uo pipefail

dir="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/loadouts"
mkdir -p "$dir"

slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-\+//; s/-\+$//'
}

# An id becomes a filename, so it has to name a file in this directory and not
# a path out of it. Every id this script mints is a slug and is safe by
# construction, but ids come back in off the disk: the directory is documented
# as syncable, so a file that arrived from somewhere else carries whatever id
# it likes, and delete would have followed "../../x" straight out of here.
# Deliberately narrow -- it rejects an escape, not an unusual name -- because
# a slug made under a UTF-8 locale keeps its accented letters and those ids
# are already saved on people's machines.
is_safe_id() {
  local id="$1"
  [[ -n $id ]] || return 1
  [[ $id != */* ]] || return 1
  [[ $id != "." && $id != ".." ]] || return 1
  return 0
}

case "${1:-}" in
  list)
    # Parsed one file at a time on purpose. This directory is user-visible and
    # meant to be synced, so a conflict copy or a half-written file will turn
    # up in it eventually; catting the lot into one jq made the first bad byte
    # take every saved loadout down with it. The select() below can only skip
    # a file that parsed, so the parsing has to be per file to reach it.
    find "$dir" -maxdepth 1 -name '*.json' -print0 2>/dev/null | sort -z |
      while IFS= read -r -d '' file; do jq -c . "$file" 2>/dev/null || true; done |
      jq -s 'map(select(.id and .name and .slots
                        and ((.id | type) == "string")
                        and ((.id | contains("/")) | not)
                        and .id != "." and .id != ".."))
             | sort_by(.savedAt) | reverse'
    ;;
  save)
    name="${2:?name required}"
    slots="${3:?slots json required}"
    if [[ -n ${4:-} ]]; then
      id="$4"
      is_safe_id "$id" || { echo "refusing unsafe loadout id: $id" >&2; exit 2; }
      [[ -f "$dir/$id.json" ]] || { echo "no such loadout to overwrite: $id" >&2; exit 1; }
    else
      id="$(slug "$name")"
      is_safe_id "$id" || id="loadout-$(date +%s)"
    fi
    jq -n --arg id "$id" --arg name "$name" --argjson slots "$slots" --arg savedAt "$(date -Is)" \
      '{id:$id, name:$name, slots:$slots, savedAt:$savedAt}' > "$dir/$id.json" || exit 1
    echo "$id"
    ;;
  delete)
    id="${2:?id required}"
    is_safe_id "$id" || { echo "refusing unsafe loadout id: $id" >&2; exit 2; }
    rm -f "$dir/$id.json"
    ;;
  *)
    echo "usage: loadouts.sh list | save <name> <slots-json> | delete <id>" >&2
    exit 2
    ;;
esac

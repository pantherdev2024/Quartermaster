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
#
# Saying this directory is syncable is saying that files arrive in it from
# somewhere else, so nothing in it is taken on trust. The directory itself is
# checked once, up front, to be a real directory that belongs to this user and
# to nobody else. A listing reads only regular files it opened itself, and
# only as much of them as the limits below allow. A save is published by
# renaming a freshly created file over its destination rather than by writing
# through the destination's name. Each step says why underneath.

set -uo pipefail

here="$(dirname "$(readlink -f "$0")")"
# shellcheck source=safe-io.sh
source "$here/safe-io.sh" || { echo "cannot load safe-io.sh" >&2; exit 1; }

# Reading limits. A loadout is a few hundred bytes, so these are far above
# anything a real store reaches and far below what would cost the shell that
# reads them anything. Quartermaster runs inside omarchy-shell, so the cost of
# reading a planted store is paid by the bar and the notifications, not by a
# program the user can close.
MAX_FILES=512            # files considered in one listing
MAX_FILE_BYTES=65536     # bytes read from any one file
MAX_TOTAL_BYTES=4194304  # bytes accumulated across the whole listing
MAX_SLOTS=64             # slot entries a loadout may record
MAX_STRING=2048          # characters any one string field may carry

# ---- The store -------------------------------------------------------------

# Where the store lives. XDG_DATA_HOME decides, but only when it is what the
# specification requires it to be: an absolute path. The spec says a relative
# value must be ignored as though it were unset, which is also the safe
# reading, so a value that is not a path is not pasted into one.
store_dir() {
  local base="${XDG_DATA_HOME:-}"
  [[ $base == /* ]] || base="$HOME/.local/share"
  printf '%s/omarchy/loadouts' "$base"
}

# Everything here reads and writes inside one directory, so that directory is
# the boundary worth checking, and checking it once costs nothing. The store
# belongs to this plugin alone, so it is held to the private standard: a real
# directory, this user's, and closed to everybody else. A directory that fails
# is not a store, and is neither written to nor read.
ensure_store() {
  dir="$(store_dir)"
  io_dir "$dir" private
}

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

# ---- Reading ---------------------------------------------------------------

# Parsed one file at a time on purpose. This directory is user-visible and
# meant to be synced, so a conflict copy or a half-written file will turn up
# in it eventually; catting the lot into one jq made the first bad byte take
# every saved loadout down with it. The select() below can only skip a file
# that parsed, so the parsing has to be per file to reach it.
#
# find is given -type f, which on a default walk matches regular files and
# does not match the symlinks, directories and pipes that share the directory
# with them, so the listing never opens anything it was not looking for.
list_store() {
  local count=0 total=0 file doc
  local -a docs=()

  while IFS= read -r -d '' file; do
    (( count >= MAX_FILES )) && break
    count=$((count + 1))
    doc="$(io_read "$file" "$MAX_FILE_BYTES" | jq -c . 2>/dev/null)" || continue
    [[ -n $doc ]] || continue
    (( total + ${#doc} > MAX_TOTAL_BYTES )) && break
    total=$((total + ${#doc}))
    docs+=("$doc")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null | sort -z)

  if (( ${#docs[@]} == 0 )); then
    echo '[]'
    return 0
  fi

  # Shape, then size, then only the four fields the screen reads. Anything a
  # planted file carries beyond those is dropped here rather than handed to
  # the long-lived process that asked for the list.
  printf '%s\n' "${docs[@]}" |
    jq -s --argjson maxSlots "$MAX_SLOTS" --argjson maxString "$MAX_STRING" '
      def short($s): ($s | type) == "string" and ($s | length) <= $maxString;
      map(select(
            short(.id) and (.id | length) > 0
            and ((.id | contains("/")) | not) and .id != "." and .id != ".."
            and short(.name)
            and (.slots | type) == "object"
            and (.slots | length) <= $maxSlots
            and (.slots | to_entries | all(short(.key) and short(.value)))
            and ((.savedAt // "") | type) == "string"
          )
          | {id, name, slots, savedAt: (.savedAt // "")})
      | sort_by(.savedAt) | reverse'
}

# ---- Commands --------------------------------------------------------------

case "${1:-}" in
  list)
    # A store that does not check out is reported empty rather than read. The
    # screen asks for this list every time it opens, and an empty array keeps
    # it opening; the reason goes to stderr, and the exit status says the
    # listing is not to be trusted as complete.
    ensure_store || { echo '[]'; exit 1; }
    list_store
    ;;
  save)
    ensure_store || exit 1
    name="${2:?name required}"
    slots="${3:?slots json required}"
    if [[ -n ${4:-} ]]; then
      id="$4"
      is_safe_id "$id" || { echo "refusing unsafe loadout id: $id" >&2; exit 2; }
      dest="$dir/$id.json"
      # -f follows a link, so a link to any existing file would answer yes
      # here; the destination has to be the plain file it claims to be.
      [[ -f $dest && ! -L $dest ]] ||
        { echo "no such loadout to overwrite: $id" >&2; exit 1; }
    else
      id="$(slug "$name")"
      is_safe_id "$id" || id="loadout-$(date +%s)"
      dest="$dir/$id.json"
    fi
    # Built before the store is touched at all. The old form redirected jq
    # straight at the destination, so the destination was emptied the moment
    # the command started and a jq that then failed on its arguments had
    # already destroyed the loadout it was meant to replace.
    payload="$(jq -n --arg id "$id" --arg name "$name" --argjson slots "$slots" \
      --arg savedAt "$(date -Is)" \
      '{id:$id, name:$name, slots:$slots, savedAt:$savedAt}')" || exit 1
    io_publish "$dest" "$payload" || exit 1
    echo "$id"
    ;;
  delete)
    ensure_store || exit 1
    id="${2:?id required}"
    is_safe_id "$id" || { echo "refusing unsafe loadout id: $id" >&2; exit 2; }
    # rm unlinks the name it is given and never follows it, so a link planted
    # at this name takes the link away rather than what it points at.
    rm -f -- "$dir/$id.json"
    ;;
  *)
    echo "usage: loadouts.sh list | save <name> <slots-json> [id] | delete <id>" >&2
    exit 2
    ;;
esac

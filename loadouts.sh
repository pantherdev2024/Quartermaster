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
# the boundary worth checking, and checking it once costs nothing. It has to
# be a directory rather than a link standing in for one, it has to belong to
# this user, and it has to be closed to everyone else. A directory that fails
# any of those is not a store: it is not written to, and it is reported empty
# rather than read. A directory that is merely too open is tightened, because
# older installs made it with the default mode and there is nothing to gain by
# refusing to work until the user fixes it by hand.
ensure_store() {
  dir="$(store_dir)"

  if [[ ! -e $dir && ! -L $dir ]]; then
    mkdir -p -m 700 -- "$dir" 2>/dev/null ||
      { echo "loadouts: cannot create $dir" >&2; return 1; }
  fi

  # -L first: a link to a directory answers -d, so asking -d alone would let
  # the store be anywhere the link points.
  if [[ -L $dir || ! -d $dir ]]; then
    echo "loadouts: $dir is not a directory" >&2
    return 1
  fi

  local owner mode
  owner="$(stat -c %u -- "$dir" 2>/dev/null)" || return 1
  if [[ $owner != "$(id -u)" ]]; then
    echo "loadouts: $dir does not belong to this user" >&2
    return 1
  fi

  mode="$(stat -c %a -- "$dir" 2>/dev/null)" || return 1
  if (( 8#$mode & 8#077 )); then
    chmod 700 -- "$dir" 2>/dev/null ||
      { echo "loadouts: $dir is open to other users and cannot be tightened" >&2; return 1; }
  fi

  return 0
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

# Read at most MAX_FILE_BYTES from one regular file without following a link
# to it. Bash cannot ask open(2) for O_NOFOLLOW, so the guarantee is made
# after the fact instead of before: take the identity of what the path names
# without following it, open the path, then take the identity of what the
# descriptor actually holds. A symlink resolves to a different inode and is
# dropped, and so is a file swapped for another between those two steps. Every
# byte after that comes from the descriptor rather than from the name, and
# head stops at the limit, so what is on disk cannot decide what this costs.
read_file() {
  local file="$1" want got fd
  [[ -f $file && ! -L $file ]] || return 1
  want="$(stat -c '%d:%i' -- "$file" 2>/dev/null)" || return 1
  exec {fd}<"$file" 2>/dev/null || return 1
  got="$(stat -L -c '%d:%i' -- "/dev/fd/$fd" 2>/dev/null)"
  if [[ -z $got || $got != "$want" ]]; then
    exec {fd}<&-
    return 1
  fi
  head -c "$MAX_FILE_BYTES" <&"$fd"
  exec {fd}<&-
}

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
    doc="$(read_file "$file" | jq -c . 2>/dev/null)" || continue
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

# ---- Writing ---------------------------------------------------------------

# Publish a document at a path in the store. The file is created fresh under a
# name of mktemp's choosing, which is an exclusive create, so it cannot be an
# existing thing in disguise. It is filled, and only then renamed over the
# destination. rename(2) replaces the directory entry itself, so unlike a
# shell redirection it cannot be talked into writing through a link that
# happens to be sitting at the destination, and it either happens whole or not
# at all, so a reader never meets half a loadout. A destination that is
# neither absent nor a plain file is refused rather than replaced: in this
# directory that is evidence of something rather than an accident, and
# quietly overwriting it would destroy whatever it was pointing at.
#
# The temporary name begins with a dot and so does not end in .json, which is
# what keeps a half-written save out of a listing running beside it.
publish() {
  local dest="$1" doc="$2" tmp
  if [[ -L $dest ]]; then
    echo "loadouts: refusing to save over a link: $dest" >&2
    return 1
  fi
  if [[ -e $dest && ! -f $dest ]]; then
    echo "loadouts: refusing to save over a non-file: $dest" >&2
    return 1
  fi
  tmp="$(mktemp -- "$dir/.loadout.XXXXXXXX")" || return 1
  if ! printf '%s\n' "$doc" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! mv -f -- "$tmp" "$dest"; then
    rm -f -- "$tmp"
    return 1
  fi
  return 0
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
    publish "$dest" "$payload" || exit 1
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

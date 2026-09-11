# Sourced, not run. The handful of filesystem moves the plugin's scripts make,
# in one place, because these are the moves that go wrong quietly.
#
#   io_dir <path> [private]     verify, or create, a directory to work inside
#   io_plain <path>             true when a path is free to be written as a file
#   io_publish <dest> <text> [mode]
#                               replace a file atomically, never through a link
#   io_read <file> [max]        read a bounded amount, never through a link
#
# Two habits run through all of it. A name is not a thing: a path that looks
# like a file can be a link to another one, and both the test and the write
# that follow it will happily aim somewhere else, so writes go to a file
# created fresh and are renamed into place, which replaces the name rather
# than following it. And a file this plugin did not write does not get to
# decide what reading it costs, because the process reading it is the
# long-running shell that also draws the bar.
#
# Every function here is safe under `set -e`: each ends on a definite status
# and none leaves an arithmetic test as its last word.

# Verify the directory a script is about to work in, creating it if it is not
# there. It has to be a directory rather than a link standing in for one,
# because a link would move everything that follows somewhere else, and it has
# to belong to this user. No directory anybody else can write into is accepted,
# whoever owns it, because nothing inside such a directory can be trusted to
# still be what was put there. `private` additionally means nobody else may
# look inside, which is worth asking of a directory this plugin owns outright;
# one merely left readable by an older version is tightened rather than
# refused, since a default umask produces exactly that and there is nothing to
# gain by making the user fix it by hand. A directory shared with Omarchy
# keeps whatever mode Omarchy gave it.
io_dir() {
  local path="$1" private="${2:-}" owner mode

  if [[ ! -e $path && ! -L $path ]]; then
    if [[ $private == private ]]; then
      mkdir -p -m 700 -- "$path" 2>/dev/null || { echo "safe-io: cannot create $path" >&2; return 1; }
    else
      mkdir -p -- "$path" 2>/dev/null || { echo "safe-io: cannot create $path" >&2; return 1; }
    fi
  fi

  # -L first: a link to a directory answers -d, so asking -d alone would let
  # the work happen wherever the link points.
  if [[ -L $path || ! -d $path ]]; then
    echo "safe-io: $path is not a directory" >&2
    return 1
  fi

  owner="$(stat -c %u -- "$path" 2>/dev/null)" || return 1
  if [[ $owner != "$(id -u)" ]]; then
    echo "safe-io: $path does not belong to this user" >&2
    return 1
  fi

  mode="$(stat -c %a -- "$path" 2>/dev/null)" || return 1
  if (( 8#$mode & 8#022 )); then
    echo "safe-io: $path is writable by other users" >&2
    return 1
  fi
  if [[ $private == private ]] && (( 8#$mode & 8#077 )); then
    chmod 700 -- "$path" 2>/dev/null ||
      { echo "safe-io: $path is open to other users and cannot be tightened" >&2; return 1; }
  fi

  return 0
}

# True when a path is either not there or is the plain file it appears to be.
# A link is refused rather than followed and a directory or pipe wearing the
# name is refused outright: in a directory this plugin manages, that is
# evidence of something rather than an accident, and quietly writing anyway
# would destroy whatever was at the other end.
io_plain() {
  local path="$1"
  if [[ -L $path ]]; then
    echo "safe-io: refusing to write through a link: $path" >&2
    return 1
  fi
  if [[ -e $path && ! -f $path ]]; then
    echo "safe-io: refusing to write over a non-file: $path" >&2
    return 1
  fi
  return 0
}

# Replace a file with new contents, all at once. The new contents go into a
# file mktemp creates fresh beside the destination, which is an exclusive
# create and so cannot turn out to be something that was already there, and
# that file is then renamed over the destination. rename replaces the
# directory entry itself, so unlike a redirection it cannot be pointed
# somewhere else by a link sitting at the name, and it either happens whole or
# not at all, so nobody reads half a file and nothing is destroyed before its
# replacement exists. The temporary carries a leading dot and a random tail,
# so a half-written file matches neither `*.json` nor `*.lua` and cannot be
# picked up by anything globbing the directory while the write is in flight.
io_publish() {
  local dest="$1" content="$2" mode="${3:-600}" tmp
  io_plain "$dest" || return 1
  tmp="$(mktemp -- "$(dirname -- "$dest")/.$(basename -- "$dest").XXXXXX")" || return 1
  if ! printf '%s\n' "$content" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! chmod "$mode" -- "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! mv -f -- "$tmp" "$dest"; then
    rm -f -- "$tmp"
    return 1
  fi
  return 0
}

# Read at most `max` bytes of one regular file, without following a link to
# it. Bash cannot ask open(2) for O_NOFOLLOW, so the guarantee is made after
# the fact rather than before: take the identity of what the path names
# without following it, open the path, then take the identity of what the
# descriptor actually holds. A link resolves to a different inode and is
# dropped, and so is a file swapped for another between those two steps. Every
# byte after that comes from the descriptor rather than from the name, and
# head stops at the limit, so what is on disk cannot decide what this costs.
io_read() {
  local file="$1" max="${2:-65536}" want got fd
  [[ -f $file && ! -L $file ]] || return 1
  want="$(stat -c '%d:%i' -- "$file" 2>/dev/null)" || return 1
  exec {fd}<"$file" 2>/dev/null || return 1
  got="$(stat -L -c '%d:%i' -- "/dev/fd/$fd" 2>/dev/null)"
  if [[ -z $got || $got != "$want" ]]; then
    exec {fd}<&-
    return 1
  fi
  head -c "$max" <&"$fd"
  exec {fd}<&-
  return 0
}

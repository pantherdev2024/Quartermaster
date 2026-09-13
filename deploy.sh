#!/bin/bash
# Runs a fitting's commands one after another, detached from the shell, and
# reports back three ways: a desktop notification, a result file that scan.sh
# folds into the inventory, and a log.
#
#   deploy.sh '<json array of argv arrays>'
#
# Detached because a font change restarts the shell, and Quartermaster lives inside
# the shell: anything still queued there would die with it.

set -uo pipefail

here="$(dirname "$(readlink -f "$0")")"
# shellcheck source=safe-io.sh
source "$here/safe-io.sh" || { echo "cannot load safe-io.sh" >&2; exit 1; }

# The plan is built by Loadout.qml out of program names that are literals
# there, and this script is the only thing that runs it. That is a promise
# about the caller; this is where it is checked instead of trusted. A command
# runs only if its program is one of Omarchy's own setters, named bare and
# found on PATH, or one of this plugin's two scripts, named by the exact path
# they have beside this one. A plan that names anything else, or that is not
# a list of argv lists, or that is longer than a fitting can be, is refused
# whole before any of it runs.
ALLOWED_PROGRAMS=(
  omarchy-theme-set omarchy-theme-bg-set omarchy-font-set omarchy-display-text-size
  omarchy-bar omarchy-default-terminal omarchy-default-editor omarchy-default-browser
  omarchy-plugin-enable omarchy-plugin-disable
)
ALLOWED_SCRIPTS=("$here/look-set.sh" "$here/agent-set.sh")
MAX_COMMANDS=128   # a full fitting is under twenty; rebuilding the bar adds one per widget

allowed_program() {
  local program="$1" p
  for p in "${ALLOWED_SCRIPTS[@]}"; do [[ $program == "$p" ]] && return 0; done
  [[ $program == */* ]] && return 1
  for p in "${ALLOWED_PROGRAMS[@]}"; do [[ $program == "$p" ]] && return 0; done
  return 1
}

plan="${1:?plan json required}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/loadout"
log="$state/deploy.log"
result="$state/last-deploy.json"

# The log is opened once, here, and everything below appends through that one
# descriptor rather than reopening the name each time. Checking a name and
# then writing to it is two different things happening to two different
# moments; opening it once means every later append lands in the file this
# check passed, whatever happens to the name afterwards.
io_dir "$state" private || exit 1
io_plain "$log" || exit 1
exec {logfd}>>"$log" || exit 1
# The log is created by the append itself, so it arrives with whatever the
# umask says; everything else this writes is shut, and the directory holding
# it is too, so there is no reason for this one to be the exception.
chmod 600 -- "$log" 2>/dev/null || true

jq -e 'type == "array" and all(.[]; type == "array" and length > 0 and all(.[]; type == "string"))' \
  <<<"$plan" >/dev/null 2>&1 || { echo "== $(date -Is) refused: plan is not a list of argv lists" >&$logfd; exit 1; }
count=$(jq 'length' <<<"$plan") || exit 1
echo "== $(date -Is) deploying $count command(s)" >&$logfd

refused=()
(( count <= MAX_COMMANDS )) || refused+=("$count commands, more than the $MAX_COMMANDS a fitting can need")
for ((i = 0; i < count && i < MAX_COMMANDS; i++)); do
  program="$(jq -r ".[$i][0]" <<<"$plan")"
  allowed_program "$program" || refused+=("$program")
done
if (( ${#refused[@]} > 0 )); then
  for r in "${refused[@]}"; do echo "   refused: $r" >&$logfd; done
  echo "== nothing run" >&$logfd
  summary="$(jq -n --arg at "$(date -Is)" --argjson failed "${#refused[@]}" \
    --arg names "${refused[*]}" '{at:$at, ok:0, failed:$failed, names:$names}')" || exit 1
  io_publish "$result" "$summary" || exit 1
  omarchy-notification-send -g 󰆓 "Quartermaster: deploy refused · ${refused[*]}"
  exit 1
fi

now_ms() { date +%s%3N; }

# omarchy-theme-set picks a background of its own: it snapshots the current
# wallpaper, cycles to the next one in the theme's folder, crossfades to it over
# IPC and forks a cleanup. When the fitting carries a background too, all of
# that is thrown away one command later, and the crossfade to the wrong
# wallpaper is the longest stall in the deploy. Tell the theme to leave the
# background alone and let omarchy-theme-bg-set put the right one up directly.
skip_theme_background=0
if jq -e 'any(.[]; (.[0] | split("/") | last) == "omarchy-theme-bg-set")' <<<"$plan" >/dev/null 2>&1; then
  skip_theme_background=1
  echo "   (theme keeps its hands off the background: one is fitted)" >&$logfd
fi

ok=0
failed=()
started=$(now_ms)
for ((i = 0; i < count; i++)); do
  mapfile -t cmd < <(jq -r ".[$i][]" <<<"$plan")
  prefix=()
  if ((skip_theme_background)) && [[ ${cmd[0]##*/} == omarchy-theme-set ]]; then
    prefix=(env OMARCHY_THEME_SKIP_BACKGROUND=1)
  fi
  echo "-- ${cmd[*]}" >&$logfd
  at=$(now_ms)
  if "${prefix[@]}" "${cmd[@]}" >&$logfd 2>&1; then
    ok=$((ok + 1))
    outcome=ok
  else
    failed+=("${cmd[0]##*/}")
    outcome=FAILED
  fi
  echo "   $outcome in $(($(now_ms) - at))ms" >&$logfd
done
echo "== $count command(s) in $(($(now_ms) - started))ms total" >&$logfd

summary="$(jq -n --arg at "$(date -Is)" --argjson ok "$ok" --argjson failed "${#failed[@]}" \
  --arg names "${failed[*]:-}" '{at:$at, ok:$ok, failed:$failed, names:$names}')" || exit 1
io_publish "$result" "$summary" || exit 1

if (( ${#failed[@]} == 0 )); then
  plural="s"; (( ok == 1 )) && plural=""
  omarchy-notification-send -g 󰆓 "Quartermaster deployed · $ok change$plural"
else
  omarchy-notification-send -g 󰆓 "Quartermaster: ${#failed[@]} failed · ${failed[*]}"
fi

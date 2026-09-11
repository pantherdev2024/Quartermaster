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

count=$(jq 'length' <<<"$plan") || exit 1
echo "== $(date -Is) deploying $count command(s)" >&$logfd

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

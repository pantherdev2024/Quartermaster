#!/bin/bash
# Runs a fitting's commands one after another, detached from the shell, and
# reports back three ways: a desktop notification, a result file that scan.sh
# folds into the inventory, and a log.
#
#   deploy.sh '<json array of argv arrays>'
#
# Detached because a font change restarts the shell, and OmaKit lives inside
# the shell: anything still queued there would die with it.

set -uo pipefail

plan="${1:?plan json required}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/loadout"
mkdir -p "$state"
log="$state/deploy.log"
result="$state/last-deploy.json"

count=$(jq 'length' <<<"$plan") || exit 1
echo "== $(date -Is) deploying $count command(s)" >>"$log"

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
  echo "   (theme keeps its hands off the background: one is fitted)" >>"$log"
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
  echo "-- ${cmd[*]}" >>"$log"
  at=$(now_ms)
  if "${prefix[@]}" "${cmd[@]}" >>"$log" 2>&1; then
    ok=$((ok + 1))
    outcome=ok
  else
    failed+=("${cmd[0]##*/}")
    outcome=FAILED
  fi
  echo "   $outcome in $(($(now_ms) - at))ms" >>"$log"
done
echo "== $count command(s) in $(($(now_ms) - started))ms total" >>"$log"

jq -n --arg at "$(date -Is)" --argjson ok "$ok" --argjson failed "${#failed[@]}" \
  --arg names "${failed[*]:-}" '{at:$at, ok:$ok, failed:$failed, names:$names}' >"$result"

if (( ${#failed[@]} == 0 )); then
  plural="s"; (( ok == 1 )) && plural=""
  omarchy-notification-send -g 󰆓 "OmaKit deployed · $ok change$plural"
else
  omarchy-notification-send -g 󰆓 "OmaKit: ${#failed[@]} failed · ${failed[*]}"
fi

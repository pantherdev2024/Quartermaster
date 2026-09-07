#!/bin/bash
# Runs a fitting's commands one after another, detached from the shell, and
# reports back three ways: a desktop notification, a result file that scan.sh
# folds into the inventory, and a log.
#
#   deploy.sh '<json array of argv arrays>'
#
# Detached because a font change restarts the shell, and Loadout lives inside
# the shell: anything still queued there would die with it.

set -uo pipefail

plan="${1:?plan json required}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/loadout"
mkdir -p "$state"
log="$state/deploy.log"
result="$state/last-deploy.json"

count=$(jq 'length' <<<"$plan") || exit 1
echo "== $(date -Is) deploying $count command(s)" >>"$log"

ok=0
failed=()
for ((i = 0; i < count; i++)); do
  mapfile -t cmd < <(jq -r ".[$i][]" <<<"$plan")
  echo "-- ${cmd[*]}" >>"$log"
  if "${cmd[@]}" >>"$log" 2>&1; then
    ok=$((ok + 1))
  else
    failed+=("${cmd[0]##*/}")
  fi
done

jq -n --arg at "$(date -Is)" --argjson ok "$ok" --argjson failed "${#failed[@]}" \
  --arg names "${failed[*]:-}" '{at:$at, ok:$ok, failed:$failed, names:$names}' >"$result"

if (( ${#failed[@]} == 0 )); then
  plural="s"; (( ok == 1 )) && plural=""
  omarchy-notification-send -g 󰆓 "Loadout deployed · $ok change$plural"
else
  omarchy-notification-send -g 󰆓 "Loadout: ${#failed[@]} failed · ${failed[*]}"
fi

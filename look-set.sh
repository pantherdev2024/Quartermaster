#!/bin/bash
# Fits one Hyprland look slot: gaps, border, corners, blur or shadow.
#
#   look-set.sh <slot> <preset>
#
# The presets are the only values that ever reach Hyprland. They live in
# look-presets.json beside this script; both arguments are looked up there
# and rejected if absent, and neither is ever written anywhere as text. The
# choice per slot is recorded in a small JSON file in Quartermaster's state
# directory, and from that record one Lua file is rendered into Omarchy's
# toggles drop-in directory, which Omarchy itself loads after the user's
# ~/.config/hypr/looknfeel.lua (see default/hypr/toggles.lua). Nothing under
# ~/.config is touched. A slot fitted with its stock preset is left out of the
# file altogether, so the user's own looknfeel.lua keeps the last word there,
# and fitting every slot back to stock removes the file.
#
# After writing, Hyprland is reloaded and asked for config errors. Any error
# that was not already there before the write means the render was rejected:
# the previous file and record come back, Hyprland is reloaded again, and the
# script fails. A bad write can never leave the desktop in a broken state.

set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"
presets="$here/look-presets.json"
slot="${1:?usage: look-set.sh <slot> <preset>}"
preset="${2:?usage: look-set.sh <slot> <preset>}"

state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
record="$state/loadout/look.json"
target_dir="$state/toggles/hypr"
target="$target_dir/quartermaster-look.lua"

jq -e --arg s "$slot" --arg p "$preset" \
  '.[$s] | type == "array" and any(.[]; .id == $p)' "$presets" >/dev/null 2>&1 \
  || { echo "unknown look preset: $slot/$preset" >&2; exit 1; }

mkdir -p "$(dirname "$record")" "$target_dir"

current="$(cat "$record" 2>/dev/null || true)"
jq -e 'type == "object"' <<<"$current" >/dev/null 2>&1 || current='{}'
next="$(jq -c --arg s "$slot" --arg p "$preset" '. + {($s): $p}' <<<"$current")"

# Every chosen non-stock preset's `set` table, merged, rendered as one
# hl.config call. Keys come from the preset file, values are numbers and
# booleans; there is no string in the output at all.
body="$(jq -r -n --argjson chosen "$next" --slurpfile table "$presets" '
  def pad(d): ([range(d)] | map("  ") | join(""));
  def lua(d):
    if type == "object" then
      "{\n" + ([to_entries[] | pad(d + 1) + .key + " = " + (.value | lua(d + 1)) + ","] | join("\n"))
      + "\n" + pad(d) + "}"
    elif type == "boolean" or type == "number" then tostring
    else error("look preset holds a value that is not a number or boolean") end;
  [ $chosen | to_entries[] as $e
    | ($table[0][$e.key] // [])[]
    | select(.id == $e.value and ((.stock // false) | not))
    | .set ]
  | reduce .[] as $t ({}; . * $t)
  | if . == {} then "" else "hl.config(" + lua(0) + ")" end
')"

# Remember what was there, so a rejected render can be undone exactly.
had_target=0; prev_target=""
if [[ -f $target ]]; then had_target=1; prev_target="$(cat "$target")"; fi
had_record=0; prev_record=""
if [[ -f $record ]]; then had_record=1; prev_record="$(cat "$record")"; fi

have_hyprctl=0
command -v hyprctl >/dev/null 2>&1 && have_hyprctl=1
errors_before=""
(( have_hyprctl )) && errors_before="$(hyprctl configerrors 2>/dev/null || true)"

write_file() {  # write_file <path> <content>: atomic, same directory
  local tmp
  tmp="$(mktemp "$(dirname "$1")/.$(basename "$1").XXXXXX")"
  printf '%s\n' "$2" >"$tmp"
  mv -f "$tmp" "$1"
}

if [[ -z $body ]]; then
  rm -f "$target"
else
  write_file "$target" "$(printf '%s\n%s\n%s\n\n%s' \
    "-- Written by Quartermaster. The equip screen rewrites this file whenever a" \
    "-- look slot is deployed; fit every look slot back to stock, or delete this" \
    "-- file, and Hyprland is back to ~/.config/hypr/looknfeel.lua alone." \
    "$body")"
fi
write_file "$record" "$next"

(( have_hyprctl )) || exit 0

hyprctl reload >/dev/null 2>&1 || true
errors_after="$(hyprctl configerrors 2>/dev/null || true)"
if [[ $errors_after != "$errors_before" ]]; then
  if (( had_target )); then write_file "$target" "$prev_target"; else rm -f "$target"; fi
  if (( had_record )); then write_file "$record" "$prev_record"; else rm -f "$record"; fi
  hyprctl reload >/dev/null 2>&1 || true
  echo "hyprland rejected the look file; previous look restored: $errors_after" >&2
  exit 1
fi

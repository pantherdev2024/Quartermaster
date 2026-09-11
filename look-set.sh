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
# shellcheck source=safe-io.sh
source "$here/safe-io.sh" || { echo "cannot load safe-io.sh" >&2; exit 1; }

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

# The record is this plugin's own and is held private. The toggles directory
# is Omarchy's, shared with its own flags, so it is checked for being a real
# directory of this user's that nobody else can write to and its mode is left
# exactly as Omarchy set it.
io_dir "$(dirname "$record")" private || exit 1
io_dir "$target_dir" || exit 1

current="$(io_read "$record" 2>/dev/null || true)"
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

# Both destinations are checked before either is written. Writing the Lua and
# only then discovering the record cannot be written leaves Hyprland wearing a
# look that nothing recorded, which is worse than not applying at all.
io_plain "$target" || exit 1
io_plain "$record" || exit 1

# Remember what was there, so a rejected render can be undone exactly. A file
# that is there but cannot be read is not a previous state that can be put
# back, so rather than write over it and find that out later, stop now: the
# alternative is a rollback that deletes what it was meant to restore.
had_target=0; prev_target=""
if [[ -e $target ]]; then
  prev_target="$(io_read "$target")" || { echo "cannot read $target to be able to undo this" >&2; exit 1; }
  had_target=1
fi
had_record=0; prev_record=""
if [[ -e $record ]]; then
  prev_record="$(io_read "$record")" || { echo "cannot read $record to be able to undo this" >&2; exit 1; }
  had_record=1
fi

have_hyprctl=0
command -v hyprctl >/dev/null 2>&1 && have_hyprctl=1
errors_before=""
(( have_hyprctl )) && errors_before="$(hyprctl configerrors 2>/dev/null || true)"

if [[ -z $body ]]; then
  rm -f "$target"
else
  io_publish "$target" "$(printf '%s\n%s\n%s\n\n%s' \
    "-- Written by Quartermaster. The equip screen rewrites this file whenever a" \
    "-- look slot is deployed; fit every look slot back to stock, or delete this" \
    "-- file, and Hyprland is back to ~/.config/hypr/looknfeel.lua alone." \
    "$body")" || exit 1
fi
io_publish "$record" "$next" || exit 1

(( have_hyprctl )) || exit 0

hyprctl reload >/dev/null 2>&1 || true
errors_after="$(hyprctl configerrors 2>/dev/null || true)"
if [[ $errors_after != "$errors_before" ]]; then
  if (( had_target )); then io_publish "$target" "$prev_target"; else rm -f "$target"; fi
  if (( had_record )); then io_publish "$record" "$prev_record"; else rm -f "$record"; fi
  hyprctl reload >/dev/null 2>&1 || true
  echo "hyprland rejected the look file; previous look restored: $errors_after" >&2
  exit 1
fi

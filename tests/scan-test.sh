#!/bin/bash
# scan.sh is read-only, but everything the screen shows comes out of it, so the
# shape of its JSON is a contract with the QML. It runs against a fabricated
# home and a fabricated Omarchy so the assertions do not depend on what this
# machine happens to have installed.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/home/.local/share"
export XDG_STATE_HOME="$TMP/home/.local/state"
export OMARCHY_PATH="$TMP/omarchy"
export PATH="$TMP/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
equals() {
  [[ $2 == "$3" ]] || fail "$1: expected $(printf '%q' "$3"), got $(printf '%q' "$2")"
}

# --- a home and an Omarchy to scan --------------------------------------
theme() {
  mkdir -p "$1"
  printf 'background = "#0d1117"\nforeground = "#e6edf3"\n' > "$1/colors.toml"
}
theme "$HOME/.config/omarchy/themes/mytheme"
theme "$HOME/.config/omarchy/themes/shared"
theme "$OMARCHY_PATH/themes/shared"
theme "$OMARCHY_PATH/themes/stock-only"
# A folder with no palette cannot be previewed or applied, so it is not an item.
mkdir -p "$OMARCHY_PATH/themes/half-removed"
mkdir -p "$HOME/.config/omarchy/themes/mytheme/backgrounds"
: > "$HOME/.config/omarchy/themes/mytheme/backgrounds/dusk.jpg"
: > "$HOME/.config/omarchy/themes/mytheme/backgrounds/notes.txt"

mkdir -p "$HOME/.config/omarchy"
cat > "$HOME/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "position": "left",
    "transparent": true,
    "layout": {
      "left": [{"id": "omarchy.clock", "format": "HH:mm"}],
      "center": [{"id": "omarchy.spacer"}, {"id": "omarchy.benched-service"}],
      "right": []
    }
  }
}
JSON

mkdir -p "$TMP/bin"
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }
stub omarchy-theme-current      'echo "Shared"'
# hyprctl answers a batched getoption with one JSON object per option, blank
# lines between, whatever the batch asked for; the values come from a file so
# a test can move them.
cat > "$TMP/hypr-values" <<'JSON'
{"general:gaps_in": {"option":"general:gaps_in","css":"5 5 5 5","set":true},
 "general:gaps_out": {"option":"general:gaps_out","css":"10 10 10 10","set":true},
 "general:border_size": {"option":"general:border_size","int":2,"set":true},
 "decoration:rounding": {"option":"decoration:rounding","int":12,"set":true},
 "decoration:blur:enabled": {"option":"decoration:blur:enabled","bool":false,"set":true},
 "decoration:blur:size": {"option":"decoration:blur:size","int":8,"set":false},
 "decoration:blur:passes": {"option":"decoration:blur:passes","int":1,"set":false},
 "decoration:shadow:enabled": {"option":"decoration:shadow:enabled","bool":false,"set":true},
 "decoration:shadow:range": {"option":"decoration:shadow:range","int":4,"set":false},
 "decoration:shadow:render_power": {"option":"decoration:shadow:render_power","int":3,"set":false}}
JSON
stub hyprctl "jq -c 'to_entries[] | .value' '$TMP/hypr-values' | sed 's/\$/\n/'"
stub omarchy-font-current       'echo "CaskaydiaMono Nerd Font"'
stub omarchy-font-list          'printf "CaskaydiaMono Nerd Font\nJetBrainsMono Nerd Font\n"'
stub omarchy-display-text-size  'echo "text size: 14 (default) px"'
stub omarchy-default-terminal   'echo foot'
stub omarchy-default-editor     'echo nvim'
stub omarchy-default-browser    'echo chromium'
stub omarchy-default-agent      'echo claude'
# A widget whose service check fails is not offered -- unless the bar already
# carries it, which is the documented exception.
stub omarchy-installed-service-missing-service 'exit 1'
stub omarchy-installed-service-benched-service 'exit 1'
stub omarchy-plugin-catalog 'cat <<CAT
[ {"id":"omarchy.clock","name":"Clock","kinds":["bar-widget"],
   "barWidget":{"category":"Time","description":"The time","defaultSection":"center"}},
  {"id":"omarchy.spacer","name":"Spacer","kinds":["bar-widget"],"barWidget":{}},
  {"id":"omarchy.missing-service","name":"Missing Service","kinds":["bar-widget"],"barWidget":{}},
  {"id":"omarchy.benched-service","name":"Benched Service","kinds":["bar-widget"],"barWidget":{}},
  {"id":"omarchy.notawidget","name":"Not A Widget","kinds":["service"],"barWidget":{}} ]
CAT'

OUT="$TMP/out.json"
"$ROOT/scan.sh" > "$OUT" || fail "scan.sh exited non-zero"
jq -e . "$OUT" >/dev/null || fail "scan.sh did not emit valid JSON"

# --- the shape the QML reads --------------------------------------------
for key in themes loadouts fonts terminals editors browsers agents \
           barPositions barTransparency textSizes barWidgets barLayout \
           lastDeploy currentBackground look lookLive; do
  jq -e --arg k "$key" 'has($k)' "$OUT" >/dev/null || fail "missing top-level key: $key"
done

# --- themes: both halves of the collection ------------------------------
names=$(jq -r '.themes | map(.name) | join(",")' "$OUT")
equals "themes found, sorted" "$names" "Mytheme,Shared,Stock Only"
[[ $names != *"Half Removed"* ]] || fail "a theme with no colors.toml was offered"

# The stock half comes from OMARCHY_PATH, not from a fixed address.
stock=$(jq -r '.themes[] | select(.name == "Stock Only") | .path' "$OUT")
[[ $stock == "$OMARCHY_PATH/themes/stock-only" ]] || fail "stock theme not read from OMARCHY_PATH: $stock"

# A user theme wins a name collision with a stock one.
shared=$(jq -r '.themes[] | select(.name == "Shared") | .path' "$OUT")
[[ $shared == "$HOME/.config/omarchy/themes/shared" ]] || fail "stock theme shadowed the user's: $shared"

equals "current theme is equipped" \
  "$(jq -r '.themes[] | select(.name == "Shared") | .equipped' "$OUT")" "true"
equals "palette parsed" \
  "$(jq -r '.themes[0].colors.background' "$OUT")" "#0d1117"
equals "only images count as backgrounds" \
  "$(jq -r '.themes[] | select(.name == "Mytheme") | .backgrounds | length' "$OUT")" "1"

# --- the rest of the inventory ------------------------------------------
equals "font marked equipped" \
  "$(jq -r '.fonts[] | select(.equipped) | .id' "$OUT")" "CaskaydiaMono Nerd Font"
equals "text size read out of the status line" \
  "$(jq -r '.textSizes[] | select(.equipped) | .id' "$OUT")" "14"
equals "bar position from shell.json" \
  "$(jq -r '.barPositions[] | select(.equipped) | .id' "$OUT")" "left"
equals "bar transparency from shell.json" \
  "$(jq -r '.barTransparency[] | select(.equipped) | .id' "$OUT")" "true"
equals "terminal from omarchy-default-terminal" \
  "$(jq -r '.terminals[] | select(.equipped) | .id' "$OUT")" "foot"

# --- bar widgets ---------------------------------------------------------
widgets=$(jq -r '.barWidgets | map(.id) | join(",")' "$OUT")
[[ $widgets != *"omarchy.spacer"* ]] || fail "the spacer must not be offered as a tile"
[[ $widgets != *"omarchy.notawidget"* ]] || fail "a non-widget plugin was offered as a tile"
[[ $widgets != *"omarchy.missing-service"* ]] \
  || fail "a widget whose service check fails should be left out"
[[ $widgets == *"omarchy.benched-service"* ]] \
  || fail "a widget already on the bar stays listed however its check answers"
equals "placement read off the layout" \
  "$(jq -r '.barWidgets[] | select(.id == "omarchy.clock") | "\(.section):\(.index)"' "$OUT")" "left:0"
equals "a widget carrying settings is flagged" \
  "$(jq -r '.barWidgets[] | select(.id == "omarchy.clock") | .settings' "$OUT")" "true"
equals "an unplaced widget has no section" \
  "$(jq -r '.barWidgets[] | select(.id == "omarchy.benched-service") | .index' "$OUT")" "1"

# barLayout is the raw order, spacer and all, because move indices count it.
equals "raw layout keeps the spacer" \
  "$(jq -rc '.barLayout.center' "$OUT")" '["omarchy.spacer","omarchy.benched-service"]'

# --- look: presets matched against what Hyprland reports -------------------
equals "look slots" "$(jq -r '.look | keys | join(",")' "$OUT")" "blur,border,corners,gaps,shadow"
equals "live gaps read from the css shorthand" "$(jq -c '.lookLive.general' "$OUT")" \
  '{"gaps_in":5,"gaps_out":10,"border_size":2}'
equals "stock gaps equipped" "$(jq -r '.look.gaps[] | select(.equipped) | .id' "$OUT")" "stock"
equals "round corners equipped" "$(jq -r '.look.corners[] | select(.equipped) | .id' "$OUT")" "round"
equals "blur off equipped" "$(jq -r '.look.blur[] | select(.equipped) | .id' "$OUT")" "off"
equals "no custom item when a preset matches" "$(jq '[.look[][] | select(.custom)] | length' "$OUT")" "0"
# Every item carries the values it sets, so the mock desktop can paint them.
jq -e '.look.gaps[] | select(.id == "loose") | .set.general.gaps_out == 32' "$OUT" >/dev/null \
  || fail "preset items should carry their set tables"

# Values no preset produces: the live ones become a Custom item, and only
# for the slot they belong to.
jq '.["general:gaps_in"].css = "7 7 7 7" | .["general:gaps_out"].css = "14 14 14 14"' \
  "$TMP/hypr-values" > "$TMP/hv2" && mv "$TMP/hv2" "$TMP/hypr-values"
"$ROOT/scan.sh" > "$TMP/custom.json" || fail "scan.sh failed with custom gaps"
equals "custom gaps equipped" "$(jq -r '.look.gaps[] | select(.equipped) | .id' "$TMP/custom.json")" "custom"
equals "custom carries the live values" "$(jq -c '.look.gaps[] | select(.custom) | .set' "$TMP/custom.json")" \
  '{"general":{"gaps_in":7,"gaps_out":14}}'
equals "custom says what it is" "$(jq -r '.look.gaps[] | select(.custom) | .meta' "$TMP/custom.json")" \
  "as configured · 7 / 14"
equals "other slots untouched by custom gaps" "$(jq '[.look[][] | select(.custom)] | length' "$TMP/custom.json")" "1"
equals "preset list keeps its order" "$(jq -r '.look.gaps | map(.id) | join(",")' "$TMP/custom.json")" \
  "tight,stock,airy,loose,custom"

# --- an empty machine ----------------------------------------------------
# No themes, no shell.json, no state: the screen must still open, so every
# key has to be present and every list an array rather than null.
rm -rf "$HOME/.config/omarchy" "$OMARCHY_PATH/themes"
"$ROOT/scan.sh" > "$TMP/empty.json" || fail "scan.sh failed on an empty machine"
jq -e . "$TMP/empty.json" >/dev/null || fail "invalid JSON on an empty machine"
for key in themes loadouts fonts barWidgets barPositions; do
  jq -e --arg k "$key" '.[$k] | type == "array"' "$TMP/empty.json" >/dev/null \
    || fail "$key was not an array on an empty machine"
done
equals "no themes to offer" "$(jq '.themes | length' "$TMP/empty.json")" "0"
# hyprctl with no compositor to talk to: the look slots still list their
# presets, nothing is equipped and nothing is invented.
stub hyprctl 'echo "Couldn'"'"'t connect to Hyprland" >&2; exit 1'
"$ROOT/scan.sh" > "$TMP/nohypr.json" || fail "scan.sh failed when hyprctl could not connect"
equals "lookLive is null when hyprctl fails" "$(jq -c '.lookLive' "$TMP/nohypr.json")" "null"
equals "presets still listed when hyprctl fails" "$(jq '.look.gaps | length' "$TMP/nohypr.json")" "4"
equals "nothing equipped when hyprctl fails" "$(jq '[.look[][] | select(.equipped)] | length' "$TMP/nohypr.json")" "0"
equals "bar position falls back to top" \
  "$(jq -r '.barPositions[] | select(.equipped) | .id' "$TMP/empty.json")" "top"

# A state file that is not JSON, or a link wearing its name, must not end the
# scan: everything the screen shows comes through this one document, so one
# unreadable byte in a corner of it would leave the screen with no inventory
# at all rather than with one missing field.
deploy_state="$XDG_STATE_HOME/omarchy/loadout"
mkdir -p "$deploy_state"
printf 'not json at all\n' > "$deploy_state/last-deploy.json"
"$ROOT/scan.sh" > "$TMP/corrupt.json" || fail "scan.sh failed on a corrupt last-deploy"
jq -e . "$TMP/corrupt.json" >/dev/null || fail "invalid JSON with a corrupt last-deploy"
equals "a corrupt last-deploy reads as none" "$(jq -c '.lastDeploy' "$TMP/corrupt.json")" "null"
ln -sf /etc/hostname "$deploy_state/last-deploy.json"
"$ROOT/scan.sh" > "$TMP/linked.json" || fail "scan.sh failed on a linked last-deploy"
equals "a linked last-deploy reads as none" "$(jq -c '.lastDeploy' "$TMP/linked.json")" "null"
rm -f "$deploy_state/last-deploy.json"

# The same for the shell's own configuration, which the bar widgets come from.
# (The empty-machine case above took the whole config directory away.)
mkdir -p "$HOME/.config/omarchy"
printf 'not json at all\n' > "$HOME/.config/omarchy/shell.json"
"$ROOT/scan.sh" > "$TMP/badshell.json" || fail "scan.sh failed on a corrupt shell.json"
jq -e . "$TMP/badshell.json" >/dev/null || fail "invalid JSON with a corrupt shell.json"
jq -e '.barWidgets | type == "array"' "$TMP/badshell.json" >/dev/null \
  || fail "barWidgets was not an array with a corrupt shell.json"

printf 'scan-test: ok\n'

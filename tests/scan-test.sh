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
           lastDeploy currentBackground; do
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
equals "bar position falls back to top" \
  "$(jq -r '.barPositions[] | select(.equipped) | .id' "$TMP/empty.json")" "top"

printf 'scan-test: ok\n'

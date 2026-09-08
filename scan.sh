#!/bin/bash
# Emits the full Quartermaster inventory as a single JSON document on stdout.
# Kept out of QML on purpose: the same pattern the built-in clipboard plugin
# uses, so parsing stays in bash where the omarchy commands already live.
#
# Every slot's items share one shape: {id, name, equipped, icon?, short?}.
# `id` is exactly what the slot's apply command accepts. `icon` is a Nerd
# Font glyph and `short` a 2–5 character tag; the cell shows the glyph if
# there is one, else the tag, else the name's initials.

set -uo pipefail

emit_colors() {
  # colors.toml -> flat JSON object. Only `key = "#hex"` lines; ignores the rest.
  local file="$1"
  [[ -f $file ]] || { echo '{}'; return; }
  sed -n 's/^[[:space:]]*\([a-z_]\+\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1\t\2/p' "$file" |
    jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | map({(.[0]): .[1]}) | add // {}'
}

emit_themes() {
  local current
  current="$(omarchy-theme-current 2>/dev/null || cat ~/.local/state/omarchy/current/theme.name 2>/dev/null)"

  local -a rows=()
  local seen=""
  # Both halves of the collection: what the user installed, then what Omarchy
  # shipped. The stock half is wherever Omarchy says it is rather than where it
  # usually is, because `omarchy dev link` moves it. User themes take precedence
  # over stock ones with the same name.
  for dir in ~/.config/omarchy/themes/*/ "${OMARCHY_PATH:-/usr/share/omarchy}"/themes/*/; do
    dir="${dir%/}"
    [[ -d $dir ]] || continue
    # An entry with no palette can't be previewed or applied — skip stubs and
    # half-removed theme folders rather than showing an unequippable item.
    [[ -f "$dir/colors.toml" ]] || continue
    local id name preview colors
    id="$(basename "$dir")"
    case " $seen " in *" $id "*) continue ;; esac
    seen="$seen $id"

    # Title-case the directory name for display: tokyo-night -> Tokyo Night
    name="$(echo "$id" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')"
    preview=""
    [[ -f "$dir/preview.png" ]] && preview="$dir/preview.png"
    colors="$(emit_colors "$dir/colors.toml")"

    local backgrounds
    backgrounds="$(find "$dir/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null |
      sort | jq -R -s 'split("\n") | map(select(length > 0))')"

    local equipped="false"
    [[ ${current,,} == "${name,,}" ]] && equipped="true"

    rows+=("$(jq -n \
      --arg id "$id" --arg name "$name" --arg path "$dir" --arg preview "$preview" \
      --argjson colors "$colors" --argjson backgrounds "$backgrounds" \
      --argjson equipped "$equipped" \
      '{id:$id, name:$name, path:$path, preview:$preview, colors:$colors, backgrounds:$backgrounds, equipped:$equipped}')")
  done

  printf '%s\n' "${rows[@]}" | jq -s 'sort_by(.name)'
}

# Rows are "id<TAB>name<TAB>icon<TAB>short" lines on stdin; $1 is the current
# id. Missing trailing fields are fine.
emit_rows() {
  local current="$1"
  jq -R -s --arg current "$current" '
    split("\n") | map(select(length > 0) | split("\t")) |
    map({id:.[0], name:(.[1] // .[0]), icon:(.[2] // ""), short:(.[3] // ""),
         equipped:(.[0] == $current)})'
}

present() { command -v "$1" >/dev/null 2>&1; }

# ---- Cyberware: the tools you carry -------------------------------------
# Each table row is "id binary name tag". The id is what omarchy-default-*
# accepts; the binary is what proves the item is actually installed. Cells
# show the tag: app glyphs live in private-use codepoints that vary between
# Nerd Font builds, and nine identical robots tell you nothing.

emit_tagged() {
  # $1 = current id; table rows on stdin.
  local current="$1"
  while read -r id bin name tag; do
    [[ -n ${id:-} ]] || continue
    present "$bin" && printf '%s\t%s\t\t%s\n' "$id" "$name" "$tag"
  done | emit_rows "$current"
}

emit_terminals() {
  emit_tagged "$(omarchy-default-terminal 2>/dev/null)" <<'TBL'
alacritty alacritty Alacritty ALAC
foot foot Foot FOOT
ghostty ghostty Ghostty GHST
kitty kitty Kitty KTTY
TBL
}

emit_editors() {
  emit_tagged "$(omarchy-default-editor 2>/dev/null)" <<'TBL'
nvim nvim Neovim NVIM
code code VSCode CODE
cursor cursor Cursor CURS
zeditor zeditor Zed ZED
sublime_text sublime_text Sublime SUBL
helix helix Helix HX
vim vim Vim VIM
emacs emacs Emacs EMCS
TBL
}

emit_browsers() {
  emit_tagged "$(omarchy-default-browser 2>/dev/null)" <<'TBL'
chromium chromium Chromium CHRM
chrome google-chrome-stable Chrome CHRO
brave brave Brave BRAV
brave-origin brave-origin Brave-Origin BRVO
edge microsoft-edge-stable Edge EDGE
firefox firefox Firefox FFOX
zen zen-browser Zen ZEN
TBL
}

emit_agents() {
  emit_tagged "$(omarchy-default-agent 2>/dev/null)" <<'TBL'
claude claude Claude CLD
codex codex Codex CDX
opencode opencode OpenCode OPC
pi pi Pi PI
omp omp Oh-My-Pi OMP
crush crush Crush CRSH
gemini gemini Gemini GEM
grok grok Grok GROK
copilot copilot Copilot COPI
TBL
}

# ---- Chassis: the frame everything hangs on -----------------------------

shell_json="$HOME/.config/omarchy/shell.json"

emit_bar_positions() {
  local current
  current="$(jq -r '.bar.position // "top"' "$shell_json" 2>/dev/null || echo top)"
  printf '%s\n' \
    $'top\tTop\t\tTOP' $'bottom\tBottom\t\tBTM' $'left\tLeft\t\tLEFT' $'right\tRight\t\tRGHT' |
    emit_rows "$current"
}

emit_bar_transparency() {
  local current
  current="$(jq -r 'if .bar.transparent == true then "true" else "false" end' "$shell_json" 2>/dev/null || echo false)"
  printf '%s\n' $'false\tSolid\t\tSOLID' $'true\tTransparent\t\tCLEAR' |
    emit_rows "$current"
}

# Bar widgets: the catalogue joined with the live layout. The spacer is left
# out: it is a widget you can have several of, which on/off cannot describe,
# so it stays wherever it is. `barLayout` is the raw layout order, spacer and
# all, because move indices count every entry.
emit_bar_layout() {
  jq -c '(.bar.layout // {}) | {
    left:   ((.left   // []) | map(if type == "object" then .id else . end)),
    center: ((.center // []) | map(if type == "object" then .id else . end)),
    right:  ((.right  // []) | map(if type == "object" then .id else . end))
  }' "$shell_json" 2>/dev/null || echo '{"left":[],"center":[],"right":[]}'
}

# Widgets whose service is not there to report on. A bar widget is a plugin
# and its dependencies are generally opaque, but for the few where Omarchy
# ships an omarchy-installed-service-<name> check, the answer is knowable: a
# Dropbox tile on a machine with no Dropbox is a tile that enables cleanly and
# then has nothing to say. Emitted as a JSON array of ids. The check is given
# a short timeout because it can reach for a daemon, and this runs on every
# open of the screen.
unavailable_widgets() {
  local ids=() id name
  while read -r id; do
    [[ $id == omarchy.* ]] || continue
    name=${id#omarchy.}
    command -v "omarchy-installed-service-$name" >/dev/null 2>&1 || continue
    timeout 2 "omarchy-installed-service-$name" >/dev/null 2>&1 || ids+=("$id")
  done < <(jq -r '.[]? | select(.kinds | index("bar-widget")) | .id' <<<"$1" 2>/dev/null)
  printf '%s\n' "${ids[@]:-}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

emit_bar_widgets() {
  local catalog shell unavailable
  catalog="$(omarchy-plugin-catalog 2>/dev/null)" || catalog='[]'
  shell="$(cat "$shell_json" 2>/dev/null)" || shell='{}'
  unavailable="$(unavailable_widgets "$catalog")" || unavailable='[]'
  jq -n --argjson catalog "$catalog" --argjson shell "$shell" \
        --argjson unavailable "$unavailable" '
    { "omarchy.menu": "MENU", "omarchy.workspaces": "WS", "omarchy.clock": "CLK",
      "omarchy.tray": "TRAY", "omarchy.audio": "VOL", "omarchy.network": "NET",
      "omarchy.bluetooth": "BT", "omarchy.power": "PWR", "omarchy.monitor": "DISP",
      "omarchy.agents": "AGNT", "omarchy.indicators": "IND", "omarchy.keyboard-layout": "KBD",
      "omarchy.weather": "WX", "omarchy.system-update": "UPD", "omarchy.active-window": "WIN",
      "omarchy.dropbox": "DBX", "omarchy.media": "MED", "omarchy.microphone": "MIC",
      "omarchy.tailscale": "TS", "37signals.hey": "HEY", "omaplug": "PLUG",
      "crmne.hyprmoncfg": "MON" } as $tags
    | ($shell.bar.layout // {}) as $layout
    | [ ("left", "center", "right") as $s
        | ($layout[$s] // []) | to_entries[]
        | { id: (if (.value | type) == "object" then .value.id else .value end),
            section: $s, index: .key,
            settings: ((.value | type) == "object" and (((.value | keys) - ["id"]) | length) > 0) } ] as $placed
    | $catalog
    | ($placed | map(.id)) as $placedIds
    | map(select((.kinds | index("bar-widget")) and .id != "omarchy.spacer"))
    # A widget with no service behind it is not offered -- unless the bar is
    # already carrying it, where leaving it out would stop the fitting from
    # describing, or undoing, what is actually there.
    | map(select(.id as $id
        | (($unavailable | index($id)) | not) or ($placedIds | index($id))))
    | map(. as $w | ($placed | map(select(.id == $w.id)) | first) as $p
        | { id: $w.id, name: $w.name,
            short: ($tags[$w.id] // ($w.name | ascii_upcase | .[0:4])),
            category: ($w.barWidget.category // ""),
            description: ($w.barWidget.description // $w.description // ""),
            defaultSection: (($w.barWidget.defaultSection // "center")
              | if IN("left", "center", "right") then . else "center" end),
            section: ($p.section // ""), index: ($p.index // -1),
            settings: ($p.settings // false) })
    | sort_by(.name)
  '
}

emit_text_sizes() {
  # First line of the status output reads "text size: 12 (default) px".
  local current
  current="$(omarchy-display-text-size 2>/dev/null | sed -n '1s/.*text size:[[:space:]]*\([0-9]\+\).*/\1/p')"
  [[ -n $current ]] || current=12
  for px in 9 10 11 12 13 14 15 16 17 18 19 20; do
    printf '%s\t%s px\t\t%s\n' "$px" "$px" "$px"
  done | emit_rows "$current"
}

# ---- Outfit -------------------------------------------------------------

emit_fonts() {
  local current
  current="$(omarchy-font-current 2>/dev/null)"
  omarchy-font-list 2>/dev/null | jq -R -s --arg current "$current" \
    'split("\n") | map(select(length > 0)) |
     map({id:., name:., equipped:(. == $current)})'
}

here="$(dirname "$(readlink -f "$0")")"

jq -n \
  --argjson themes "$(emit_themes)" \
  --argjson loadouts "$("$here/loadouts.sh" list)" \
  --argjson fonts "$(emit_fonts)" \
  --argjson terminals "$(emit_terminals)" \
  --argjson editors "$(emit_editors)" \
  --argjson browsers "$(emit_browsers)" \
  --argjson agents "$(emit_agents)" \
  --argjson barPositions "$(emit_bar_positions)" \
  --argjson barTransparency "$(emit_bar_transparency)" \
  --argjson textSizes "$(emit_text_sizes)" \
  --argjson barWidgets "$(emit_bar_widgets)" \
  --argjson barLayout "$(emit_bar_layout)" \
  --argjson lastDeploy "$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/loadout/last-deploy.json" 2>/dev/null || echo null)" \
  --arg currentBackground "$(readlink -f ~/.local/state/omarchy/current/background 2>/dev/null)" \
  '{themes:$themes, loadouts:$loadouts, fonts:$fonts, terminals:$terminals, editors:$editors,
    browsers:$browsers, agents:$agents, barPositions:$barPositions,
    barTransparency:$barTransparency, textSizes:$textSizes,
    barWidgets:$barWidgets, barLayout:$barLayout, lastDeploy:$lastDeploy,
    currentBackground:$currentBackground}'

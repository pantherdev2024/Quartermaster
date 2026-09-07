#!/bin/bash
# Emits the full Loadout inventory as a single JSON document on stdout.
# Kept out of QML on purpose: the same pattern the built-in clipboard plugin
# uses, so parsing stays in bash where the omarchy commands already live.

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
  # User themes take precedence over stock ones with the same name.
  for dir in ~/.config/omarchy/themes/*/ /usr/share/omarchy/themes/*/; do
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

emit_simple_slot() {
  # $1 = current value, rest = candidate values. Marks the matching one equipped.
  local current="$1"; shift
  printf '%s\n' "$@" | jq -R -s --arg current "$current" \
    'split("\n") | map(select(length > 0)) |
     map({id:., name:., equipped:(. == $current)})'
}

present() { command -v "$1" >/dev/null 2>&1; }

emit_terminals() {
  local -a found=()
  for t in alacritty foot ghostty kitty; do present "$t" && found+=("$t"); done
  emit_simple_slot "$(omarchy-default-terminal 2>/dev/null)" "${found[@]}"
}

emit_editors() {
  local -a found=()
  for e in nvim code cursor zeditor sublime_text helix vim emacs; do
    present "$e" && found+=("$e")
  done
  emit_simple_slot "$(omarchy-default-editor 2>/dev/null)" "${found[@]}"
}

emit_browsers() {
  local -a found=()
  for b in chromium google-chrome-stable brave microsoft-edge-stable firefox zen-browser; do
    present "$b" && found+=("$b")
  done
  emit_simple_slot "$(omarchy-default-browser 2>/dev/null)" "${found[@]}"
}

emit_fonts() {
  local current
  current="$(omarchy-font-current 2>/dev/null)"
  omarchy-font-list 2>/dev/null | jq -R -s --arg current "$current" \
    'split("\n") | map(select(length > 0)) |
     map({id:., name:., equipped:(. == $current)})'
}

jq -n \
  --argjson themes "$(emit_themes)" \
  --argjson fonts "$(emit_fonts)" \
  --argjson terminals "$(emit_terminals)" \
  --argjson editors "$(emit_editors)" \
  --argjson browsers "$(emit_browsers)" \
  --arg currentBackground "$(readlink -f ~/.local/state/omarchy/current/background 2>/dev/null)" \
  '{themes:$themes, fonts:$fonts, terminals:$terminals, editors:$editors,
    browsers:$browsers, currentBackground:$currentBackground}'

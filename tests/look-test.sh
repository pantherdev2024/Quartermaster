#!/bin/bash
# look-set.sh is the one script that writes Hyprland configuration, so what
# matters is exactly where it writes, exactly what, and that it backs out when
# Hyprland objects. It runs against a temporary state directory and a stubbed
# hyprctl that records its calls and can be told to report a config error.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/home/.local/state"
export PATH="$TMP/bin:$PATH"
LOOK="$ROOT/look-set.sh"
TARGET="$XDG_STATE_HOME/omarchy/toggles/hypr/quartermaster-look.lua"
RECORD="$XDG_STATE_HOME/omarchy/loadout/look.json"
TRACE="$TMP/trace"
ERRORS="$TMP/errors"      # what the stub answers to `configerrors`

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
equals() {
  [[ $2 == "$3" ]] || fail "$1: expected $(printf '%q' "$3"), got $(printf '%q' "$2")"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/hyprctl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$TRACE"
if [[ \$1 == configerrors ]]; then cat "$ERRORS" 2>/dev/null; fi
STUB
chmod +x "$TMP/bin/hyprctl"
: > "$TRACE"; : > "$ERRORS"
calls() { paste -sd, - < "$TRACE"; }

# --- one slot ------------------------------------------------------------
"$LOOK" gaps airy
[[ -f $TARGET ]] || fail "no look file written"
grep -q 'gaps_in = 10,' "$TARGET" || fail "gaps_in missing from look file"
grep -q 'gaps_out = 20,' "$TARGET" || fail "gaps_out missing from look file"
grep -q '^hl.config({' "$TARGET" || fail "look file is not one hl.config call"
equals "record after one slot" "$(jq -c . "$RECORD")" '{"gaps":"airy"}'
equals "reload then configerrors" "$(calls)" "configerrors,reload,configerrors"

# Nothing but the two files under the state directory, nothing under ~/.config.
equals "files written" "$(cd "$XDG_STATE_HOME" && find . -type f | sort | paste -sd, -)" \
  "./omarchy/loadout/look.json,./omarchy/toggles/hypr/quartermaster-look.lua"
[[ ! -e "$HOME/.config" ]] || fail "look-set.sh touched ~/.config"

# --- a second slot merges into the same file ---------------------------------
: > "$TRACE"
"$LOOK" corners round
grep -q 'gaps_in = 10,' "$TARGET" || fail "first slot lost when second was fitted"
grep -q 'rounding = 12,' "$TARGET" || fail "rounding missing after fitting corners"
equals "record after two slots" "$(jq -c . "$RECORD")" '{"gaps":"airy","corners":"round"}'
equals "one hl.config call" "$(grep -c 'hl.config' "$TARGET")" "1"

# --- the rendered Lua is valid Lua that only calls hl.config -----------------
if command -v lua >/dev/null 2>&1; then
  LOOK_FILE="$TARGET" lua -e 'hl = { config = function(t) assert(type(t) == "table"); _G.got = t end }
          dofile(os.getenv("LOOK_FILE"))
          assert(got.general.gaps_in == 10 and got.general.gaps_out == 20, "gaps")
          assert(got.decoration.rounding == 12, "rounding")' </dev/null \
    || fail "lua could not load the rendered look file"
fi

# --- stock is absence, and all-stock removes the file ------------------------
"$LOOK" gaps stock
grep -q 'gaps_' "$TARGET" && fail "stock gaps should not be written"
grep -q 'rounding = 12,' "$TARGET" || fail "other slot lost when gaps went stock"
equals "record keeps stock choice" "$(jq -r .gaps "$RECORD")" "stock"
"$LOOK" corners square
[[ ! -e $TARGET ]] || fail "look file should be removed when every slot is stock"
equals "record after all stock" "$(jq -c . "$RECORD")" '{"gaps":"stock","corners":"square"}'

# --- every preset in the table renders -------------------------------------
for slot in $(jq -r 'keys[]' "$ROOT/look-presets.json"); do
  for id in $(jq -r --arg s "$slot" '.[$s][].id' "$ROOT/look-presets.json"); do
    "$LOOK" "$slot" "$id" || fail "preset $slot/$id failed to apply"
  done
done
grep -q 'shadow = {' "$TARGET" || fail "nested shadow table missing"
grep -q 'render_power = 3,' "$TARGET" || fail "shadow render_power missing"

# --- bad arguments write nothing -------------------------------------------
before_target="$(cat "$TARGET")"; before_record="$(cat "$RECORD")"; : > "$TRACE"
"$LOOK" gaps enormous 2>/dev/null && fail "unknown preset should fail"
"$LOOK" glow on 2>/dev/null && fail "unknown slot should fail"
"$LOOK" gaps '$(touch /tmp/pwned)' 2>/dev/null && fail "injected preset should fail"
equals "look file untouched by bad arguments" "$(cat "$TARGET")" "$before_target"
equals "record untouched by bad arguments" "$(cat "$RECORD")" "$before_record"
equals "hyprctl not called for bad arguments" "$(calls)" ""

# --- a config error that is new backs the write out ------------------------
"$LOOK" gaps loose
before_target="$(cat "$TARGET")"; before_record="$(cat "$RECORD")"
: > "$TRACE"
# The stub reports an error from the second configerrors call onward.
cat > "$TMP/bin/hyprctl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$TRACE"
if [[ \$1 == configerrors ]]; then
  n=\$(grep -c configerrors "$TRACE")
  (( n >= 2 )) && echo "config error in file quartermaster-look.lua: nope"
fi
STUB
"$LOOK" gaps tight 2>/dev/null && fail "a new config error should fail the apply"
equals "look file restored" "$(cat "$TARGET")" "$before_target"
equals "record restored" "$(cat "$RECORD")" "$before_record"
equals "reloaded again after restoring" "$(calls)" "configerrors,reload,configerrors,reload"

# --- an error that was already there is not ours ------------------------------
cat > "$TMP/bin/hyprctl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$TRACE"
[[ \$1 == configerrors ]] && echo "config error in file looknfeel.lua: the user's own"
exit 0
STUB
"$LOOK" gaps tight || fail "a pre-existing config error must not block the apply"
grep -q 'gaps_in = 0,' "$TARGET" || fail "apply did not land despite pre-existing error"

# --- without hyprctl it still records and renders ---------------------------
rm "$TMP/bin/hyprctl"
"$LOOK" corners pill || fail "should work without hyprctl"
grep -q 'rounding = 20,' "$TARGET" || fail "render without hyprctl"

# ---- Neither file is written through its name ------------------------------
# The rendered look is Lua that Hyprland executes, so where it lands matters
# more than most writes here.

victim="$TMP/victim.conf"
printf 'do not touch\n' > "$victim"
rm -f "$TARGET"
ln -s "$victim" "$TARGET"
"$LOOK" gaps airy 2>/dev/null && fail "a linked look file should stop the apply"
equals "the link's target is untouched" "$(cat "$victim")" "do not touch"
rm -f "$TARGET"

printf 'do not touch\n' > "$victim"
rm -f "$RECORD"
ln -s "$victim" "$RECORD"
"$LOOK" gaps airy 2>/dev/null && fail "a linked record should stop the apply"
equals "the record link's target is untouched" "$(cat "$victim")" "do not touch"
rm -f "$RECORD"

# Back to a working store, and the toggles directory keeps the mode Omarchy
# gave it rather than being taken over.
"$LOOK" gaps airy >/dev/null || fail "a normal apply should still work"
equals "the toggles dir keeps its mode" "$(stat -c %a "$(dirname "$TARGET")")" "755"

printf 'look-test: ok\n'

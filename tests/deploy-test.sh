#!/bin/bash
# deploy.sh is the only part of OmaKit that changes anything. It is handed a
# plan of argv arrays and runs them in the order given, so the things worth
# pinning are that the order survives, that arguments with spaces in them
# survive, and that what it reports back matches what actually happened.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state"
export PATH="$TMP/bin:$PATH"
STATE="$XDG_STATE_HOME/omarchy/loadout"
TRACE="$TMP/trace"
DEPLOY="$ROOT/deploy.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
equals() {
  [[ $2 == "$3" ]] || fail "$1: expected $(printf '%q' "$3"), got $(printf '%q' "$2")"
}

# Stubs stand in for every command a fitting can run. Each one records the
# name it was called by, its arguments, and whether the theme was told to keep
# its hands off the background.
mkdir -p "$TMP/bin"
make_stub() {
  cat > "$TMP/bin/$1" <<STUB
#!/bin/bash
printf '%s|%s|skipbg=%s\n' "\${0##*/}" "\$*" "\${OMARCHY_THEME_SKIP_BACKGROUND:-}" >> "$TRACE"
exit ${2:-0}
STUB
  chmod +x "$TMP/bin/$1"
}
for cmd in omarchy-theme-set omarchy-theme-bg-set omarchy-font-set \
           omarchy-display-text-size omarchy-bar omarchy omarchy-default-browser \
           omarchy-notification-send; do
  make_stub "$cmd"
done

# Guard rail. An absolute path in a plan is run as written, so a plan naming a
# real command would deploy it for real against the machine running the test.
# Every plan must therefore reach only the stubs.
run_plan() {
  if jq -e --arg tmp "$TMP/bin/" 'any(.[]; .[0] | startswith("/") and (startswith($tmp) | not))' \
      <<<"$1" >/dev/null; then
    fail "plan names an absolute path outside the stub directory: $1"
  fi
  : > "$TRACE"; rm -rf "$STATE"; "$DEPLOY" "$1"
}
trace_names() { cut -d'|' -f1 < "$TRACE" | grep -v omarchy-notification-send | paste -sd, -; }

# --- order and quoting -------------------------------------------------
# The plan arrives already sorted by the QML; deploy.sh must not reorder it.
# "Rose Pine" and the font name are the reason arguments are passed as arrays.
run_plan '[["omarchy-theme-set","Rose Pine"],
           ["omarchy-theme-bg-set","/x/2-dusk-guardian.png"],
           ["omarchy-bar","position","bottom"],
           ["omarchy-default-browser","chromium"],
           ["omarchy-font-set","CaskaydiaMono Nerd Font"]]'
equals "plan order preserved" "$(trace_names)" \
  "omarchy-theme-set,omarchy-theme-bg-set,omarchy-bar,omarchy-default-browser,omarchy-font-set"
grep -Fq 'omarchy-theme-set|Rose Pine|' "$TRACE" || fail "a themed name with a space was split"
grep -Fq 'omarchy-font-set|CaskaydiaMono Nerd Font|' "$TRACE" || fail "a font name with spaces was split"
grep -Fq 'omarchy-bar|position bottom|' "$TRACE" || fail "a multi-argument command lost an argument"

# --- the background handoff --------------------------------------------
# omarchy-theme-set picks a background of its own and crossfades to it. When
# the fitting names a background too, that work is thrown away one command
# later, so the theme is told to skip it.
grep -q 'omarchy-theme-set|.*|skipbg=1' "$TRACE" \
  || fail "theme-set should skip its background when the plan carries one"

run_plan '[["omarchy-theme-set","Nord"]]'
grep -q 'omarchy-theme-set|Nord|skipbg=$' "$TRACE" \
  || fail "theme-set should pick its own background when the plan carries none"

# The command is matched on its basename, so an absolute path still counts.
run_plan "$(jq -nc --arg bin "$TMP/bin" \
  '[[($bin + "/omarchy-theme-set"), "Nord"], [($bin + "/omarchy-theme-bg-set"), "/x.png"]]')"
grep -q 'omarchy-theme-set|.*|skipbg=1' "$TRACE" \
  || fail "an absolute path to theme-set should still be recognised"

# --- reporting ----------------------------------------------------------
run_plan '[["omarchy-theme-set","Nord"],["omarchy-bar","transparent","true"]]'
equals "ok count"     "$(jq -r '.ok'     "$STATE/last-deploy.json")" "2"
equals "failed count" "$(jq -r '.failed' "$STATE/last-deploy.json")" "0"
equals "no names"     "$(jq -r '.names'  "$STATE/last-deploy.json")" ""
jq -e '.at | type == "string" and length > 0' "$STATE/last-deploy.json" >/dev/null \
  || fail "result file has no timestamp"
grep -Fq 'omarchy-theme-set Nord' "$STATE/deploy.log" || fail "command missing from the log"
equals "one notification" \
  "$(grep -c '^omarchy-notification-send' "$TRACE")" "1"
grep -Fq 'OmaKit deployed · 2 changes' "$TRACE" || fail "wrong success notification"

# One change is reported in the singular.
run_plan '[["omarchy-theme-set","Nord"]]'
grep -Fq 'OmaKit deployed · 1 change|' "$TRACE" || fail "singular not used for one change"

# --- failure ------------------------------------------------------------
# A command that fails must not stop the ones after it: the fitting is what
# the user asked for, and a font that will not set is no reason to drop a
# browser that would have.
make_stub omarchy-bar 1
run_plan '[["omarchy-theme-set","Nord"],["omarchy-bar","position","left"],["omarchy-default-browser","firefox"]]'
equals "later commands still ran" "$(trace_names)" \
  "omarchy-theme-set,omarchy-bar,omarchy-default-browser"
equals "ok counts only successes" "$(jq -r '.ok'     "$STATE/last-deploy.json")" "2"
equals "failure counted"          "$(jq -r '.failed' "$STATE/last-deploy.json")" "1"
equals "failure named"            "$(jq -r '.names'  "$STATE/last-deploy.json")" "omarchy-bar"
grep -Fq 'OmaKit: 1 failed · omarchy-bar' "$TRACE" || fail "wrong failure notification"
grep -Fq 'FAILED' "$STATE/deploy.log" || fail "failure not recorded in the log"
make_stub omarchy-bar 0

# --- degenerate input ---------------------------------------------------
run_plan '[]'
equals "empty plan runs nothing" "$(trace_names)" ""
equals "empty plan reports zero" "$(jq -r '.ok' "$STATE/last-deploy.json")" "0"

# The log accumulates across deploys rather than being truncated each time.
"$DEPLOY" '[["omarchy-theme-set","Nord"]]'
equals "log appends" "$(grep -c '^== ' "$STATE/deploy.log")" "4"

printf 'deploy-test: ok\n'

#!/bin/bash
# deploy.sh is the only part of Quartermaster that changes anything. It is handed a
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
# The one exception is the plugin's own look-set.sh with a preset that does not
# exist, which exits before it touches anything; it stands in for the two
# scripts the allowlist admits by path.
run_plan() {
  if jq -e --arg tmp "$TMP/bin/" --arg look "$ROOT/look-set.sh" \
      'any(.[]; .[0] | startswith("/") and (startswith($tmp) | not) and . != $look)' \
      <<<"$1" >/dev/null; then
    fail "plan names an absolute path outside the stub directory: $1"
  fi
  if jq -e --arg look "$ROOT/look-set.sh" 'any(.[]; .[0] == $look and .[2] != "no-such-preset")' \
      <<<"$1" >/dev/null; then
    fail "plan would run look-set.sh with a preset that might exist: $1"
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

# --- the allowlist ------------------------------------------------------
# The plan comes from the QML, which only ever writes literal program names
# into it. deploy.sh checks that promise rather than trusting it: a plan that
# names anything but Omarchy's own setters (bare, from PATH) or this plugin's
# two scripts (by their exact path) is refused whole, before anything runs.
: > "$TRACE"; rm -rf "$STATE"
"$DEPLOY" '[["omarchy-theme-set","Nord"],["rm","-rf","/"],["omarchy-bar","position","top"]]' \
  && fail "a plan naming an unknown program should be refused"
equals "nothing in a refused plan runs, not even the known parts" "$(trace_names)" ""
equals "a refused plan reports nothing ok"   "$(jq -r '.ok'     "$STATE/last-deploy.json")" "0"
equals "a refused plan reports the refusal" "$(jq -r '.failed' "$STATE/last-deploy.json")" "1"
equals "and names the program"              "$(jq -r '.names'  "$STATE/last-deploy.json")" "rm"
grep -Fq 'Quartermaster: deploy refused · rm' "$TRACE" || fail "no refusal notification"
grep -Fq 'refused: rm' "$STATE/deploy.log" || fail "refusal not logged"

# An Omarchy command is admitted by bare name only; a path to one, even to the
# real one, is not, because the QML never writes one and nothing else should.
: > "$TRACE"; rm -rf "$STATE"
"$DEPLOY" "$(jq -nc --arg bin "$TMP/bin" '[[($bin + "/omarchy-theme-set"), "Nord"]]')" \
  && fail "a path to an Omarchy command should be refused"
equals "a pathed Omarchy command did not run" "$(trace_names)" ""

# A relative path, a shell, and a name that merely starts like an allowed one.
for bad in '[["./omarchy-theme-set","Nord"]]' '[["bash","-c","true"]]' '[["omarchy-theme-set-evil","x"]]' \
           '[["omarchy","theme","set","Nord"]]' '[["","Nord"]]'; do
  : > "$TRACE"; rm -rf "$STATE"
  "$DEPLOY" "$bad" 2>/dev/null && fail "should have been refused: $bad"
  equals "nothing ran for $bad" "$(trace_names)" ""
done

# The plugin's own scripts are admitted by their exact path. look-set.sh with
# a preset that does not exist exits without touching anything, so it can
# stand in for both.
run_plan "$(jq -nc --arg look "$ROOT/look-set.sh" '[[$look, "gaps", "no-such-preset"]]')"
grep -Fq -- "-- $ROOT/look-set.sh gaps no-such-preset" "$STATE/deploy.log" \
  || fail "the plugin's own script was not admitted by its path"
equals "it ran and reported its own failure" "$(jq -r '.names' "$STATE/last-deploy.json")" "look-set.sh"

# A plan that is not a list of argv lists is refused before the log says
# anything about deploying, and one longer than a fitting can be is refused
# whole rather than truncated.
for shape in '"not a plan"' '[["omarchy-theme-set", 1]]' '[[]]' '[[["omarchy-theme-set"]]]' '{"a":1}'; do
  : > "$TRACE"; rm -rf "$STATE"
  "$DEPLOY" "$shape" 2>/dev/null && fail "malformed plan should be refused: $shape"
  equals "nothing ran for $shape" "$(trace_names)" ""
done
: > "$TRACE"; rm -rf "$STATE"
"$DEPLOY" "$(jq -nc '[range(129) | ["omarchy-bar","position","top"]]')" && fail "an overlong plan should be refused"
equals "nothing of an overlong plan ran" "$(trace_names)" ""
grep -Fq 'refused: 129 commands' "$STATE/deploy.log" || fail "overlong plan not logged as refused"

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
grep -Fq 'Quartermaster deployed · 2 changes' "$TRACE" || fail "wrong success notification"

# One change is reported in the singular.
run_plan '[["omarchy-theme-set","Nord"]]'
grep -Fq 'Quartermaster deployed · 1 change|' "$TRACE" || fail "singular not used for one change"

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
grep -Fq 'Quartermaster: 1 failed · omarchy-bar' "$TRACE" || fail "wrong failure notification"
grep -Fq 'FAILED' "$STATE/deploy.log" || fail "failure not recorded in the log"
make_stub omarchy-bar 0

# --- degenerate input ---------------------------------------------------
run_plan '[]'
equals "empty plan runs nothing" "$(trace_names)" ""
equals "empty plan reports zero" "$(jq -r '.ok' "$STATE/last-deploy.json")" "0"

# The log accumulates across deploys rather than being truncated each time.
"$DEPLOY" '[["omarchy-theme-set","Nord"]]'
equals "log appends" "$(grep -c '^== .* deploying' "$STATE/deploy.log")" "2"

# ---- The state directory is not written to blind ---------------------------
# A deploy reports back through two files. Neither is written through a name
# that something else can have pointed somewhere first.

victim="$TMP/victim.conf"

# The log is opened once, before any command runs, so a link left at its name
# stops the deploy rather than redirecting everything it writes.
printf 'do not touch\n' > "$victim"
: > "$TRACE"; rm -rf "$STATE"; mkdir -p "$STATE"
ln -s "$victim" "$STATE/deploy.log"
"$DEPLOY" '[["omarchy-bar","position","top"]]' >/dev/null 2>&1 && fail "a linked log should stop the deploy"
equals "the link's target is untouched" "$(cat "$victim")" "do not touch"
equals "and nothing was run" "$(wc -l < "$TRACE")" "0"
rm -f "$STATE/deploy.log"

# The result file is replaced rather than written through in the same way.
printf 'do not touch\n' > "$victim"
: > "$TRACE"; rm -rf "$STATE"; mkdir -p "$STATE"
ln -s "$victim" "$STATE/last-deploy.json"
# The commands do run; it is the report at the end that refuses, so this is
# expected to come back non-zero rather than to stop the script.
"$DEPLOY" '[["omarchy-bar","position","top"]]' >/dev/null 2>&1 || true
equals "the result link's target is untouched" "$(cat "$victim")" "do not touch"
rm -rf "$STATE"

# A state directory anyone could write into is not one to report into.
mkdir -p "$STATE"; chmod 777 "$STATE"
: > "$TRACE"
"$DEPLOY" '[["omarchy-bar","position","top"]]' >/dev/null 2>&1 && fail "a world-writable state dir should stop the deploy"
equals "nothing ran there either" "$(wc -l < "$TRACE")" "0"
chmod 700 "$STATE"

printf 'deploy-test: ok\n'

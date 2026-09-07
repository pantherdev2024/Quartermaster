#!/bin/bash
# agent-set.sh exists because omarchy-default-agent also launches the agent in
# a terminal. The whole point is that it records and does nothing else, so the
# test cares as much about what does not happen as about what does.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
AGENT_SET="$ROOT/agent-set.sh"
AGENT_FILE="$HOME/.config/omarchy/defaults/agent"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# It creates the defaults directory rather than assuming Omarchy made it.
"$AGENT_SET" claude
[[ -f $AGENT_FILE ]] || fail "agent file not written"
[[ $(cat "$AGENT_FILE") == "claude" ]] || fail "wrong contents: $(cat "$AGENT_FILE")"

# Same file, same format as omarchy-default-agent: the bare name and a newline.
[[ $(wc -l < "$AGENT_FILE") == 1 ]] || fail "expected exactly one trailing newline"

# Re-recording replaces rather than appends.
"$AGENT_SET" codex
[[ $(cat "$AGENT_FILE") == "codex" ]] || fail "second write did not replace"
[[ $(wc -l < "$AGENT_FILE") == 1 ]] || fail "second write appended"

# Every agent the inventory offers has to be accepted here, or a slot the user
# can pick becomes a slot that fails on deploy. This list is the one in
# scan.sh's emit_agents table.
agents=$(sed -n '/^emit_agents()/,/^TBL$/p' "$ROOT/scan.sh" |
  awk "/<<'TBL'/ {inside=1; next} /^TBL\$/ {inside=0} inside {print \$1}")
[[ -n $agents ]] || fail "could not read the agent table out of scan.sh"
for agent in $agents; do
  "$AGENT_SET" "$agent" >/dev/null 2>&1 \
    || fail "scan.sh offers '$agent' but agent-set.sh rejects it"
done

# An id that is not on that list is refused, loudly, without writing.
before=$(cat "$AGENT_FILE")
if "$AGENT_SET" 'rm -rf /' >/dev/null 2>&1; then fail "unknown agent should exit non-zero"; fi
[[ $(cat "$AGENT_FILE") == "$before" ]] || fail "a rejected agent still changed the file"
if "$AGENT_SET" >/dev/null 2>&1; then fail "no argument should exit non-zero"; fi

printf 'agent-set-test: ok\n'

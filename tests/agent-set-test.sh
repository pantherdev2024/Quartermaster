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

# The file this writes is read by Omarchy, so it keeps the mode
# omarchy-default-agent would have left rather than being locked down.
equals_mode() { [[ $(stat -c %a "$AGENT_FILE") == "$1" ]] || fail "agent file mode is $(stat -c %a "$AGENT_FILE"), expected $1"; }
equals_mode 644

# A link left at that name is replaced rather than written through, so
# whatever it pointed at is not quietly overwritten by an agent name.
victim="$TMP/victim.conf"
printf 'do not touch\n' > "$victim"
rm -f "$AGENT_FILE"
ln -s "$victim" "$AGENT_FILE"
"$AGENT_SET" claude >/dev/null 2>&1 && fail "writing over a link should fail"
[[ $(cat "$victim") == "do not touch" ]] || fail "the link's target was overwritten"
rm -f "$AGENT_FILE"

# A defaults directory anyone could write into is not one to write a default
# into, so it is refused rather than used.
"$AGENT_SET" claude >/dev/null || fail "a normal write should still work"
chmod 777 "$(dirname "$AGENT_FILE")"
"$AGENT_SET" codex >/dev/null 2>&1 && fail "a world-writable defaults dir should be refused"
[[ $(cat "$AGENT_FILE") == "claude" ]] || fail "a refused write still changed the file"
chmod 755 "$(dirname "$AGENT_FILE")"

printf 'agent-set-test: ok\n'

#!/bin/bash
# Records the default coding agent without launching it.
#
# `omarchy-default-agent <name>` both sets the default and execs the agent in
# a terminal, which is the wrong thing to do from an apply queue. The inventory
# only offers agents that are already installed, so recording the choice is
# all that's left to do — same file, same format as the real command.

set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"
# shellcheck source=safe-io.sh
source "$here/safe-io.sh" || { echo "cannot load safe-io.sh" >&2; exit 1; }

agent="${1:?usage: agent-set.sh <agent>}"
case "$agent" in
  pi|omp|opencode|claude|codex|crush|grok|gemini|copilot|hermes|openclaw|cursor-agent|muse) ;;
  *) echo "unknown agent: $agent" >&2; exit 1 ;;
esac

# The defaults directory is Omarchy's rather than this plugin's, so it is
# checked for being a real directory of this user's that nobody else can write
# to, and its mode is left as Omarchy made it. The write is a rename into
# place like every other write here, and keeps the mode omarchy-default-agent
# would have left, because this file is read by Omarchy and not by us.
agent_file="$HOME/.config/omarchy/defaults/agent"
io_dir "$(dirname "$agent_file")" || exit 1
io_publish "$agent_file" "$agent" 644 || exit 1

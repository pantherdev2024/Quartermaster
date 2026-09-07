#!/bin/bash
# Records the default coding agent without launching it.
#
# `omarchy-default-agent <name>` both sets the default and execs the agent in
# a terminal, which is the wrong thing to do from an apply queue. The inventory
# only offers agents that are already installed, so recording the choice is
# all that's left to do — same file, same format as the real command.

set -euo pipefail

agent="${1:?usage: agent-set.sh <agent>}"
case "$agent" in
  pi|omp|opencode|claude|codex|crush|grok|gemini|copilot) ;;
  *) echo "unknown agent: $agent" >&2; exit 1 ;;
esac

agent_file="$HOME/.config/omarchy/defaults/agent"
mkdir -p "$(dirname "$agent_file")"
printf '%s\n' "$agent" >"$agent_file"

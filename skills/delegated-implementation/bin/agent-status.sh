#!/usr/bin/env bash
# agent-status.sh <agent-name> [tail-lines]
#
# One-line status probe: herdr's status column plus the last non-empty
# visible pane line(s). Routine liveness polls go through this instead of a
# full `herdr agent read --source visible`, which pulls an entire rendered
# TUI pane into the orchestrator's context per poll. The status column is
# advisory for some CLIs (quirks in environment.md) — the visible tail is
# the corroborating signal; on any suspect combination, fall back to a full
# pane read to adjudicate.
# Exit: 0 printed a status, 1 agent not found or herdr unavailable.
set -u

name=${1:?usage: agent-status.sh <agent-name> [tail-lines]}
tail_n=${2:-1}

status=$(herdr agent list 2>/dev/null |
  jq -r --arg n "$name" \
    '.result.agents[] | select(.name == $n) | "\(.agent_status) kind=\(.agent) pane=\(.pane_id)"')
[ -n "$status" ] || { echo "ERROR: no agent named $name (herdr agent list)" >&2; exit 1; }

tail_lines=$(herdr agent read "$name" --source visible 2>/dev/null |
  sed -e 's/[[:space:]]*$//' | grep -v '^$' | tail -n "$tail_n")

echo "$name: $status"
[ -z "$tail_lines" ] || printf '%s\n' "$tail_lines" | sed 's/^/  | /'
exit 0

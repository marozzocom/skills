#!/usr/bin/env bash
# agent-status.sh <agent-name> [tail-lines]
#
# One-line status probe: herdr's status column plus the last non-empty
# visible pane line(s). Routine liveness polls go through this instead of a
# full `herdr agent read --source visible`, which pulls an entire rendered
# TUI pane into the orchestrator's context per poll. The pane read itself
# is bounded with `--lines` (the requested count plus a small allowance for
# the blank lines a TUI keeps at its bottom), never the whole pane trimmed
# afterwards. The status column is advisory for some CLIs (quirks in
# environment.md) — the visible tail is the corroborating signal; on any
# suspect combination, fall back to a bounded full pane read to adjudicate.
# Exit: 0 printed a status, 1 agent not found or herdr unavailable, 2 usage.
set -u

name=${1:?usage: agent-status.sh <agent-name> [tail-lines]}
tail_n=${2:-1}

case $tail_n in
  ''|*[!0-9]*) echo "usage: tail-lines must be a positive integer, got '$tail_n'" >&2; exit 2 ;;
esac
[ "$tail_n" -ge 1 ] || { echo "usage: tail-lines must be at least 1" >&2; exit 2; }
[ "$tail_n" -le 200 ] || { echo "usage: tail-lines above 200 is a pane read, not a probe (use herdr agent read --lines)" >&2; exit 2; }

status=$(herdr agent list 2>/dev/null |
  jq -r --arg n "$name" \
    '.result.agents[] | select(.name == $n) | "\(.agent_status) kind=\(.agent) pane=\(.pane_id)"')
[ -n "$status" ] || { echo "ERROR: no agent named $name (herdr agent list)" >&2; exit 1; }

read_n=$((tail_n + 8))
tail_lines=$(herdr agent read "$name" --source visible --lines "$read_n" 2>/dev/null |
  sed -e 's/[[:space:]]*$//' | grep -v '^$' | tail -n "$tail_n")

echo "$name: $status"
[ -z "$tail_lines" ] || printf '%s\n' "$tail_lines" | sed 's/^/  | /'
exit 0

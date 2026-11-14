#!/usr/bin/env bash
# context-guard.sh — Claude Code hook (PostToolUse, UserPromptSubmit).
# Reads the session's current context size from the last usage record in
# its transcript and, on crossing a threshold, injects one reminder as
# additionalContext (SKILL.md §Context discipline):
#   WARN   (default 50%): finish the node in flight, start no new fan-out.
#   ROTATE (default 60%): write the continuation prompt and hand over to a
#          fresh session now; repeated every further 5%.
# Env: CONTEXT_GUARD_WINDOW (tokens, default 1000000),
#      CONTEXT_GUARD_WARN / CONTEXT_GUARD_ROTATE (percent).
# Each level fires once per session (state under XDG_STATE_HOME). Silent
# and exit 0 on anything it cannot read: a guard never blocks a session.
set -uo pipefail
input=$(cat) || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null) || exit 0
session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null) || exit 0
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$session" ] && [ -n "$event" ] || exit 0
window=${CONTEXT_GUARD_WINDOW:-1000000}
warn=${CONTEXT_GUARD_WARN:-50}
rotate=${CONTEXT_GUARD_ROTATE:-60}
used=$(tail -n 200 "$transcript" | jq -s '
  [ .[] | .message? | objects | .usage? | objects
    | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0) ]
  | last // 0' 2>/dev/null) || exit 0
[ "${used:-0}" -gt 0 ] 2>/dev/null || exit 0
pct=$(( used * 100 / window ))
[ "$pct" -ge "$warn" ] || exit 0
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/implementation-orchestration/context-guard
mkdir -p "$state_dir" 2>/dev/null || exit 0
state=$state_dir/$session
last=$(cat "$state" 2>/dev/null || echo 0)
if [ "$pct" -ge "$rotate" ]; then
  level=$(( rotate + (pct - rotate) / 5 * 5 ))
else
  level=$warn
fi
[ "$level" -gt "$last" ] || exit 0
echo "$level" >"$state"
k=$(( used / 1000 ))
if [ "$pct" -ge "$rotate" ]; then
  msg="CONTEXT GUARD: this session holds ~${k}k tokens (${pct}% of the window); every turn re-reads all of it. Rotate now. Orchestration cockpit: finish only the step in hand, write the continuation prompt to the ledger (implementation-orchestration SKILL.md §Context discipline), start a fresh cockpit session on it in a new pane in this tab, and stop. Any other session: write a short handoff file (goal, state, next step, paths) and tell the human to continue in a fresh session from it."
else
  msg="CONTEXT GUARD: this session holds ~${k}k tokens (${pct}% of the window). Finish the node in flight; start no new fan-out or new workstream here. Prepare the continuation prompt so rotation at ${rotate}% is one step."
fi
jq -nc --arg e "$event" --arg m "$msg" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
exit 0

#!/usr/bin/env bash
# context-guard: silent below warn, warn once, rotate once per 5% step, never fails.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
G="$BIN_DIR/context-guard.sh"
export XDG_STATE_HOME="$SCRATCH/state" CONTEXT_GUARD_WINDOW=1000
t="$SCRATCH/transcript.jsonl"
usage() { echo "{\"type\":\"assistant\",\"message\":{\"usage\":{\"input_tokens\":1,\"cache_read_input_tokens\":$1,\"cache_creation_input_tokens\":0}}}" >>"$t"; }
hook() { echo "{\"transcript_path\":\"$t\",\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\"}" | "$G"; }
usage 300; assert_eq below-warn-silent "" "$(hook)"
usage 519; out=$(hook); assert_contains warn "Finish the node in flight" "$out"
assert_eq warn-event PostToolUse "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
assert_eq warn-once "" "$(hook)"
usage 610; assert_contains rotate "Rotate now" "$(hook)"
usage 640; assert_eq same-step-silent "" "$(hook)"
usage 660; assert_contains next-step "Rotate now" "$(hook)"
echo '{"transcript_path":"/nope","session_id":"s1","hook_event_name":"PostToolUse"}' | "$G"; assert_eq missing-transcript-ok 0 $?
echo 'not json' | "$G"; assert_eq bad-input-ok 0 $?
finish

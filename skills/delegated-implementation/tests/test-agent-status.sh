#!/usr/bin/env bash
# agent-status.sh against the mock herdr: the pane read is bounded with
# --lines, the tail is the last N non-empty lines, and tail-lines is
# validated.
. "$(dirname "$0")/lib.sh"
A="$BIN_DIR/agent-status.sh"

cat >"$HERDR_SCENARIO/agents.json" <<'EOF'
{"result":{"agents":[{"name":"impl","agent_status":"working","agent":"somecli","pane_id":"w1:p2"}]}}
EOF
{ for i in $(seq 1 200); do echo "line $i"; done; echo "last real line"; echo; echo "   "; } >"$HERDR_SCENARIO/pane.txt"

out=$("$A" impl 2>&1); rc=$?
assert_eq default-exit 0 "$rc"
assert_eq default-status "impl: working kind=somecli pane=w1:p2" "$(printf '%s\n' "$out" | head -n1)"
assert_eq default-tail "  | last real line" "$(printf '%s\n' "$out" | tail -n1)"
assert_eq bounded-read 1 "$(grep -c -- '--lines 9' "$MOCK_LOG")"
assert_eq no-unbounded-read 0 "$(grep -c 'UNBOUNDED' "$MOCK_LOG")"

: >"$MOCK_LOG"
out=$("$A" impl 3 2>&1)
assert_eq three-lines 4 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_contains three-first "  | line 199" "$out"
assert_eq three-bounded 1 "$(grep -c -- '--lines 11' "$MOCK_LOG")"

"$A" impl 0 >/dev/null 2>&1; assert_eq zero-rejected 2 "$?"
"$A" impl abc >/dev/null 2>&1; assert_eq alpha-rejected 2 "$?"
"$A" impl -1 >/dev/null 2>&1; assert_eq negative-rejected 2 "$?"
"$A" impl 500 >/dev/null 2>&1; assert_eq huge-rejected 2 "$?"
"$A" nobody >/dev/null 2>&1; assert_eq unknown-agent 1 "$?"

finish

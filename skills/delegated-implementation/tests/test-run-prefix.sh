#!/usr/bin/env bash
# run-prefix.sh against the mock herdr: slug sanitizing, the 12-char cut,
# and suffixing when a live agent already carries the prefix.
. "$(dirname "$0")/lib.sh"
P="$BIN_DIR/run-prefix.sh"

cat >"$HERDR_SCENARIO/agents.json" <<'EOF'
{"result":{"agents":[{"name":"overseer"},{"name":"sdlgen-overseer"},{"name":"sdlgen-2-impl"},{"name":"auth"},{}]}}
EOF

assert_eq free-slug "billing" "$("$P" billing)"
assert_eq sanitized "candidate-co" "$("$P" "Candidate  Composition!")"
assert_eq no-trailing-dash "abcdefghijk" "$("$P" "abcdefghijk-lmn")"
assert_eq taken-by-role "sdlgen-3" "$("$P" sdlgen)"
assert_eq taken-exact "auth-2" "$("$P" auth)"
assert_eq prefix-not-substring "over" "$("$P" over)"

"$P" >/dev/null 2>&1; assert_eq empty-usage 2 "$?"
"$P" "---" >/dev/null 2>&1; assert_eq no-alnum-usage 2 "$?"

rm -f "$HERDR_SCENARIO/agents.json"
out=$("$P" billing 2>&1); rc=$?
assert_eq herdr-down-exit 1 "$rc"
assert_contains herdr-down-msg "herdr agent list failed" "$out"

finish

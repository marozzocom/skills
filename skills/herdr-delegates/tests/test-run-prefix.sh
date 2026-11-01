#!/usr/bin/env bash
# run-prefix.sh against the mock herdr: slug sanitizing, the 12-char cut,
# and suffixing when a live agent already carries the prefix.
# shellcheck source=lib.sh
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

cat >"$HERDR_SCENARIO/tabs.json" <<'EOF'
{"result":{"tabs":[{"label":"billing·cockpit"},{"label":"billing-2"},{"label":"billboard·N1"},{}]}}
EOF
cat >"$HERDR_SCENARIO/workspaces.json" <<'EOF'
{"result":{"workspaces":[{"label":"billing-3"},{"label":"billing-4-other"},{}]}}
EOF
assert_eq tab-and-workspace-collisions billing-4 "$("$P" billing)"
assert_eq tab-prefix-not-substring bill "$("$P" bill)"
assert_eq workspace-prefix-not-substring billing-4 "$("$P" billing)"
rm "$HERDR_SCENARIO/tabs.json"
"$P" fresh >/dev/null 2>&1; assert_eq tab-list-failure 1 "$?"
echo '{"result":{"tabs":[]}}' >"$HERDR_SCENARIO/tabs.json"
rm "$HERDR_SCENARIO/workspaces.json"
"$P" fresh >/dev/null 2>&1; assert_eq workspace-list-failure 1 "$?"
echo '{"result":{"workspaces":[]}}' >"$HERDR_SCENARIO/workspaces.json"

"$P" >/dev/null 2>&1; assert_eq empty-usage 2 "$?"
"$P" "---" >/dev/null 2>&1; assert_eq no-alnum-usage 2 "$?"

rm -f "$HERDR_SCENARIO/agents.json"
out=$("$P" billing 2>&1); rc=$?
assert_eq herdr-down-exit 1 "$rc"
assert_contains herdr-down-msg "herdr agent list failed" "$out"

finish

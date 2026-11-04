#!/usr/bin/env bash
# rotate-implementer.sh: the agent kind is required and never defaulted.
# (The live rotation itself needs a Herdr session and is not exercised.)
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
R="$BIN_DIR/rotate-implementer.sh"

out=$(HERDR_ENV=1 "$R" impl w1:p1 "$SCRATCH" 2>&1); rc=$?
assert_eq missing-kind-exit 1 "$rc"
assert_contains missing-kind-msg "kind" "$out"

out=$(HERDR_ENV=1 "$R" impl w1:p1 "$SCRATCH" -- -m some-model 2>&1); rc=$?
assert_eq separator-as-kind-exit 2 "$rc"
assert_contains separator-as-kind-msg "kind must be an agent kind" "$out"

out=$(HERDR_ENV='' "$R" impl w1:p1 "$SCRATCH" anykind 2>&1); rc=$?
assert_eq kind-ok-then-env-check 1 "$rc"
assert_contains kind-ok-then-env-msg "not inside a Herdr session" "$out"

# shellcheck disable=SC2016 # Match the literal parameter expansion in the script.
assert_eq no-default-kind 0 "$(grep -c 'kind=\${4:-' "$R")"

app_fixture
jq '.[0].name="fixture-impl"' "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"
mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"
mkdir "$SCRATCH/new worktree"
out=$("$R" fixture-impl pa1 "$SCRATCH/new worktree" tool -- --model pinned --effort high)
assert_eq app-rotate-id tnew1 "$out"
assert_contains app-kill-old 'hc kill t1' "$(cat "$MOCK_LOG")"
assert_contains app-remove-old 'hc rm t1' "$(cat "$MOCK_LOG")"
assert_contains app-repin '--label herdr.space=sp1 --label herdr.tab=tb1 -- tool --model pinned --effort high' "$(cat "$MOCK_LOG")"
assert_eq app-new-cwd "$(cd "$SCRATCH/new worktree" && pwd -P)" "$(jq -r '.[]|select(.address=="tnew1")|.cwd' "$HC_SCENARIO/terminals.json")"
: >"$MOCK_LOG"
out=$("$R" fixture-impl ignored-pane "$SCRATCH" tool -- --model pinned)
assert_eq app-ignored-pane 0 "$?"
assert_eq app-ignored-pane-new-address tnew2 "$out"
finish

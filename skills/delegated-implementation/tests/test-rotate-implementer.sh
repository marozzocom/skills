#!/usr/bin/env bash
# rotate-implementer.sh: the agent kind is required and never defaulted.
# (The live rotation itself needs a Herdr session and is not exercised.)
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

assert_eq no-default-kind 0 "$(grep -c 'kind=\${4:-' "$R")"

finish

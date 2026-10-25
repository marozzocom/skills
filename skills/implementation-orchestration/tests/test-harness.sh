#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal command strings must expand in the child shell.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
mkdir "$SCRATCH/decoy"
printf '#!/bin/sh\nexit 9\n' >"$SCRATCH/decoy/gh"
chmod +x "$SCRATCH/decoy/gh"
printf 'export PATH="%s:$PATH"\n' "$SCRATCH/decoy" >"$SCRATCH/startup"
export BASH_ENV="$SCRATCH/startup" ENV="$SCRATCH/startup"
assert_eq hostile-child-resolves-decoy "$SCRATCH/decoy/gh" "$("$BASH" -c 'command -v gh')"
# Run the assertion in a subshell so this expected failure does not count
# against the suite, while proving the guard detects the poisoned lookup.
negative=$(assert_child_resolves gh "$MOCK_BIN/gh" 2>&1); rc=$?
assert_eq resolution-guard-catches-hostile 1 "$rc"
assert_contains resolution-guard-reason 'ASSERT child-resolves-gh' "$negative"
# Re-source in a child to exercise lib.sh neutralization after its startup.
out=$("$BASH" -c 'source "$1"; assert_child_resolves gh "$MOCK_BIN/gh"; assert_child_resolves herdr "$MOCK_BIN/herdr"; test -z "${BASH_ENV+x}${ENV+x}"; finish' _ "$TESTS_DIR/lib.sh" 2>&1); rc=$?
unset BASH_ENV ENV
assert_eq library-neutralizes-startup 0 "$rc"
assert_contains library-checks-passed 'checks ok' "$out"
finish

#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal command strings must expand in the child shell.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
G=${RUN_GATES:-$BIN_DIR/run-gates.sh}
mkdir "$SCRATCH/worktree"
export GATE_MARKER="$SCRATCH/ran" GATE_WORKTREE="$SCRATCH/worktree"
run() { out=$("$BASH" "$G" "$GATE_WORKTREE" "$@" 2>&1); rc=$?; }
run 'ok:true'
assert_eq pass-exit 0 "$rc"
assert_contains pass-verdict 'PASS ok' "$out"
assert_contains default-env-line 'bash_env: none' "$out"
assert_eq logs-last logs: "$(printf '%s\n' "$out" | tail -n1 | cut -d' ' -f1)"
run 'a:false; true'
assert_eq false-then-true 1 "$rc"
assert_contains false-then-true-verdict 'FAIL a (exit 1)' "$out"
run 'a:false | true'
assert_eq false-pipeline 1 "$rc"
unset RUN_GATES_UNSET_TEST_VALUE
run 'a:echo "$RUN_GATES_UNSET_TEST_VALUE"'
assert_eq unset-variable 1 "$rc"
run 'a:exit 3'
assert_eq exit-three 1 "$rc"
assert_contains exit-three-code 'FAIL a (exit 3)' "$out"
run 'a:false' 'b:true'
assert_eq continue-exit 1 "$rc"
assert_contains continue-fail 'FAIL a' "$out"
assert_contains continue-pass 'PASS b' "$out"
run 'tail:for ((i=1; i<=25; i++)); do echo "line-$i"; done; exit 4'
assert_eq tail-failure-exit 1 "$rc"
assert_contains tail-start '  line-6' "$out"
assert_contains tail-end '  line-25' "$out"
assert_not_contains tail-truncated '  line-5' "$out"
logdir=$(printf '%s\n' "$out" | sed -n 's/^logs: //p')
assert_eq full-log-retained 25 "$(wc -l <"$logdir/01-tail.log" 2>/dev/null | tr -d ' ')"
assert_eq private-log-directory "$logdir" "$(find "$logdir" -prune -perm 700)"
run 'tolerated:false || true'
assert_eq explicit-tolerance 0 "$rc"
run 'a:touch "$GATE_MARKER"' 'a:true'
assert_eq duplicate-exit 2 "$rc"
assert_eq duplicate-no-gate no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
rm -f "$GATE_MARKER"
for bad in ':true' 'missing-colon' 'empty:'; do
  run 'a:touch "$GATE_MARKER"' "$bad"
  assert_eq "bad-spec-$bad" 2 "$rc"
  assert_eq "bad-spec-no-gate-$bad" no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
  rm -f "$GATE_MARKER"
done
run 'a/b:echo first' 'a b:echo second'
logdir=$(printf '%s\n' "$out" | sed -n 's/^logs: //p')
assert_eq collision-exit 0 "$rc"
assert_eq collision-log-count 2 "$(find "$logdir" -name '*.log' | wc -l | tr -d ' ')"
assert_eq collision-first first "$(cat "$logdir/01-a_b.log" 2>/dev/null)"
assert_eq collision-second second "$(cat "$logdir/02-a_b.log" 2>/dev/null)"
run 'cwd:test "$PWD" = "$GATE_WORKTREE"'
assert_eq worktree-cwd 0 "$rc"
# Feed a line that would make read succeed if stdin were inherited.
out=$(printf 'unexpected\n' | "$BASH" "$G" "$GATE_WORKTREE" 'stdin:read -r value' 2>&1); rc=$?
assert_eq stdin-dev-null 1 "$rc"
mkdir "$SCRATCH/real" "$SCRATCH/decoy"
printf '#!/bin/sh\nexit 0\n' >"$SCRATCH/real/tool"
printf '#!/bin/sh\nexit 9\n' >"$SCRATCH/decoy/tool"
chmod +x "$SCRATCH/real/tool" "$SCRATCH/decoy/tool"
export GATE_DECOY="$SCRATCH/decoy" GATE_ENV_MARKER="$SCRATCH/env-ran" GATE_EXPORTED=preserved
export PATH="$SCRATCH/real:$PATH"
cat >"$SCRATCH/hostile" <<'STARTUP'
export PATH="$GATE_DECOY:$PATH"
echo ran >>"$GATE_ENV_MARKER"
STARTUP
# Source after startup: the boundary under test is the gate child, not the
# already-started caller (whose own BASH_ENV bash necessarily reads first).
out=$("$BASH" --noprofile --norc -c 'export BASH_ENV=$1 ENV=$1; shift; source "$@"' _ "$SCRATCH/hostile" "$G" "$GATE_WORKTREE" 'env:tool; test "$GATE_EXPORTED" = preserved; test -z "${BASH_ENV+x}${ENV+x}"' 2>&1); rc=$?
assert_eq default-startup-ignored 0 "$rc"
assert_eq default-startup-no-marker no "$([ -e "$GATE_ENV_MARKER" ] && echo yes || echo no)"
assert_contains default-startup-announced 'bash_env: none' "$out"
out=$(RUN_GATES_BASH_ENV="$SCRATCH/hostile" "$BASH" "$G" "$GATE_WORKTREE" 'env:tool' 2>&1); rc=$?
assert_eq opted-startup-fails 1 "$rc"
assert_eq opted-startup-marker ran "$(cat "$GATE_ENV_MARKER" 2>/dev/null)"
assert_contains opted-startup-code 'FAIL env (exit 9)' "$out"
assert_contains opted-startup-announced "bash_env: $SCRATCH/hostile" "$out"
for invalid in "$SCRATCH/absent" "$SCRATCH" ''; do
  out=$(RUN_GATES_BASH_ENV="$invalid" "$BASH" "$G" "$GATE_WORKTREE" 'a:touch "$GATE_MARKER"' 2>&1); rc=$?
  assert_eq invalid-startup-exit 2 "$rc"
  assert_eq invalid-startup-no-gate no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
  rm -f "$GATE_MARKER"
done
out=$("$BASH" "$G" 2>&1); rc=$?
assert_eq usage-exit 2 "$rc"
finish

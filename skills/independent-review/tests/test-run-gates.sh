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
# Durations: whole seconds on every verdict line, summed on the time: line.
run 'slow:sleep 1' 'quick:true' 'bad:sleep 1; exit 5'
# Whole seconds straddle a clock tick, so each value has one second of slack.
secs() { printf '%s\n' "$out" | sed -n "s/^$1 in \([0-9]*\)s.*/\1/p"; }
slow=$(secs 'PASS slow'); quick=$(secs 'PASS quick'); bad=$(secs 'FAIL bad (exit 5)')
assert_eq duration-pass yes "$([ "${slow:-0}" -ge 1 ] && [ "$slow" -le 2 ] && echo yes || echo "no: $slow")"
assert_eq duration-quick yes "$([ -n "$quick" ] && [ "$quick" -le 1 ] && echo yes || echo "no: $quick")"
assert_eq duration-fail yes "$([ "${bad:-0}" -ge 1 ] && [ "$bad" -le 2 ] && echo yes || echo "no: $bad")"
assert_contains duration-fail-tail "FAIL bad (exit 5) in ${bad}s — last 20 lines:" "$out"
assert_contains duration-total "time: $((slow + quick + bad))s" "$out"
assert_eq time-before-env 'time: bash_env: logs:' "$(printf '%s\n' "$out" | tail -n3 | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
# Record file: one line per gate, appended across runs, names flattened.
rec="$SCRATCH/gates.tsv"
out=$(RUN_GATES_RECORD="$rec" "$BASH" "$G" "$GATE_WORKTREE" 'ok:true' "tab	name:exit 4" 2>&1); rc=$?
assert_eq record-exit 1 "$rc"
assert_eq record-lines 2 "$(wc -l <"$rec" | tr -d ' ')"
assert_eq record-fields 6 "$(awk -F'\t' 'NR==2{print NF}' "$rec")"
assert_eq record-pass "$GATE_WORKTREE	gate	ok	0" "$(sed -n 1p "$rec" | cut -f2-5)"
assert_eq record-fail "$GATE_WORKTREE	gate	tab name	4" "$(sed -n 2p "$rec" | cut -f2-5)"
assert_eq record-seconds-numeric 2 "$(cut -f6 "$rec" | grep -c -E '^[0-9]+$')"
assert_contains record-time-utc 'T' "$(sed -n 1p "$rec" | cut -f1 | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$')"
out=$(RUN_GATES_RECORD="$rec" "$BASH" "$G" "$GATE_WORKTREE" 'again:true' 2>&1)
assert_eq record-appends 3 "$(wc -l <"$rec" | tr -d ' ')"
# A record that cannot be written is reported and changes nothing else.
out=$(RUN_GATES_RECORD="$SCRATCH/absent/gates.tsv" "$BASH" "$G" "$GATE_WORKTREE" 'ok:true' 2>&1); rc=$?
assert_eq record-failure-exit 0 "$rc"
assert_contains record-failure-line "record: failed $SCRATCH/absent/gates.tsv" "$out"
assert_eq record-failure-logs-last logs: "$(printf '%s\n' "$out" | tail -n1 | cut -d' ' -f1)"
out=$(RUN_GATES_RECORD='' "$BASH" "$G" "$GATE_WORKTREE" 'a:touch "$GATE_MARKER"' 2>&1); rc=$?
assert_eq record-empty-usage 2 "$rc"
# Gates do not inherit the lock or the record: a nested run stands alone.
export ORCHESTRATION_LOCK_DIR="$SCRATCH/locks"
: >"$rec"
out=$(RUN_GATES_RECORD="$rec" RUN_GATES_LOCK=heavy "$BASH" "$G" "$GATE_WORKTREE" \
  'env:test -z "${RUN_GATES_LOCK+x}${RUN_GATES_RECORD+x}${RUN_GATES_LOCKED+x}"; test "$ORCHESTRATION_LOCKS_HELD" = heavy' \
  "nested:\"$BASH\" \"$G\" . inner:true" 2>&1); rc=$?
assert_eq lock-exit 0 "$rc"
assert_eq lock-first-line 'lock: heavy waited Ns' "$(printf '%s\n' "$out" | sed -n 1p | sed 's/[0-9][0-9]*s$/Ns/')"
assert_contains lock-env-clean 'PASS env in' "$out"
assert_contains lock-nested 'PASS nested in' "$out"
assert_eq lock-record-rows 'lock gate gate' "$(cut -f3 "$rec" | tr '\n' ' ' | sed 's/ $//')"
assert_eq lock-record-wait 'heavy	0' "$(sed -n 1p "$rec" | cut -f4-5)"
# Several locks are taken in the order given and all held by the gates.
out=$(RUN_GATES_LOCK=heavy,desktop "$BASH" "$G" "$GATE_WORKTREE" 'held:test "$ORCHESTRATION_LOCKS_HELD" = heavy:desktop' 2>&1); rc=$?
assert_eq lock-list-exit 0 "$rc"
assert_contains lock-list-line 'lock: heavy,desktop waited' "$out"
# A second run queues behind the holder, and its wait is not gate time.
"$BIN_DIR/with-lock.sh" heavy -- sleep 3 &
holder=$!; sleep 0.5
out=$(RUN_GATES_LOCK=heavy "$BASH" "$G" "$GATE_WORKTREE" 'after:true' 2>&1); rc=$?
wait "$holder"
assert_eq queued-exit 0 "$rc"
waited=$(printf '%s\n' "$out" | sed -n 's/^lock: heavy waited \([0-9]*\)s$/\1/p')
assert_eq queued-waited yes "$([ "${waited:-0}" -ge 2 ] && echo yes || echo no)"
after=$(secs 'PASS after')
assert_eq queued-gate-time yes "$([ -n "$after" ] && [ "$after" -lt "$waited" ] && echo yes || echo "no: $after vs $waited")"
# A lock that is not acquired runs no gate and keeps the last two lines.
: >"$rec"
"$BIN_DIR/with-lock.sh" heavy -- sleep 3 &
holder=$!; sleep 0.5
out=$(WITH_LOCK_WAIT=1 RUN_GATES_RECORD="$rec" RUN_GATES_LOCK=heavy "$BASH" "$G" "$GATE_WORKTREE" 'a:touch "$GATE_MARKER"' 2>/dev/null); rc=$?
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
assert_eq lock-timeout-exit 3 "$rc"
assert_eq lock-timeout-no-gate no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
assert_eq lock-timeout-lines 'FAIL lock heavy (not acquired)|bash_env: none|logs: none' "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')"
assert_eq lock-timeout-record 'lock	heavy	75' "$(cut -f3-5 "$rec")"
# with-lock.sh failing for any other reason is also "no gate ran", exit 3.
ln -s "$SCRATCH" "$SCRATCH/lock-link"
out=$(ORCHESTRATION_LOCK_DIR="$SCRATCH/lock-link" RUN_GATES_RECORD="$rec" RUN_GATES_LOCK=heavy "$BASH" "$G" "$GATE_WORKTREE" 'a:touch "$GATE_MARKER"' 2>/dev/null); rc=$?
assert_eq lock-broken-exit 3 "$rc"
assert_eq lock-broken-no-gate no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
assert_eq lock-broken-lines 'FAIL lock heavy (with-lock.sh exit 1)|bash_env: none|logs: none' "$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')"
# A gate run that did start keeps its own exit code, whatever it is.
out=$(RUN_GATES_LOCK=heavy "$BASH" "$G" "$GATE_WORKTREE" 'a:false' 2>&1); rc=$?
assert_eq lock-started-exit 1 "$rc"
assert_eq lock-started-logs-last logs: "$(printf '%s\n' "$out" | tail -n1 | cut -d' ' -f1)"
assert_eq no-pending-left 0 "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'run-gates-lock.*' -newer "$SCRATCH/mock.log" 2>/dev/null | wc -l | tr -d ' ')"
for bad in 'a b' ',heavy' 'heavy,' 'a/b'; do
  out=$(RUN_GATES_LOCK="$bad" "$BASH" "$G" "$GATE_WORKTREE" 'a:touch "$GATE_MARKER"' 2>&1); rc=$?
  assert_eq "bad-lock-$bad" 2 "$rc"
done
assert_eq bad-lock-no-gate no "$([ -e "$GATE_MARKER" ] && echo yes || echo no)"
out=$("$BASH" "$G" 2>&1); rc=$?
assert_eq usage-exit 2 "$rc"
finish

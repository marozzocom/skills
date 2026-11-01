#!/usr/bin/env bash
# Append and matrix refresh share one lock: waiting, recovery and no lost lines.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
L="$BIN_DIR/ledger-append.sh"
S="$BIN_DIR/status-set.sh"
run="$SCRATCH/run with spaces"; mkdir "$run"
ledger=$run/ledger.md
"$S" "$run" init concurrency concurrent 'Preserve every ledger entry' >/dev/null
cp "$ledger" "$SCRATCH/initial"
# A background writer holds the lock, snapshots before releasing, then exits.
(
  mkdir "$run/.status.lock" || exit 1
  : >"$SCRATCH/holder-ready"
  sleep 0.5
  cp "$ledger" "$SCRATCH/while-held"
  rmdir "$run/.status.lock"
) & holder=$!
while [ ! -f "$SCRATCH/holder-ready" ]; do sleep 0.01; done
out=$("$L" "$ledger" 'after release'); rc=$?
wait "$holder"; assert_eq holder-exit 0 "$?"
assert_eq waits-then-succeeds 0 "$rc"
cmp -s "$SCRATCH/initial" "$SCRATCH/while-held"; assert_eq no-write-while-held 0 "$?"
assert_eq confirmation-is-entry "$(tail -n1 "$ledger")" "$out"
assert_contains entry-format ' — after release' "$out"
assert_eq one-confirmation-line 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
released=no; if [ ! -d "$run/.status.lock" ]; then released=yes; fi
assert_eq own-lock-released yes "$released"

(
  mkdir "$run/.status.lock" || exit 1
  : >"$SCRATCH/timeout-holder-ready"
  sleep 7
  rmdir "$run/.status.lock"
) & holder=$!
while [ ! -f "$SCRATCH/timeout-holder-ready" ]; do sleep 0.01; done
cp "$ledger" "$SCRATCH/before-timeout"
SECONDS=0
out=$("$L" "$ledger" 'must not append' 2>&1); rc=$?; elapsed=$SECONDS
assert_eq lock-timeout 1 "$rc"
assert_contains recovery-hint "if no writer is running, remove $run/.status.lock" "$out"
bounded=no; if [ "$elapsed" -ge 4 ] && [ "$elapsed" -le 8 ]; then bounded=yes; fi
assert_eq timeout-bounded yes "$bounded"
held=no; if [ -d "$run/.status.lock" ]; then held=yes; fi
assert_eq foreign-lock-preserved yes "$held"
cmp -s "$SCRATCH/before-timeout" "$ledger"; assert_eq timeout-no-write 0 "$?"
wait "$holder"; assert_eq timeout-holder-exit 0 "$?"

# Start 20 pairs together; every append must survive every atomic matrix mv.
pids=()
for i in $(seq 1 20); do
  "$L" "$ledger" "parallel-entry-$i" >"$SCRATCH/append-$i.log" 2>&1 &
  pids[${#pids[@]}]=$!
  "$S" "$run" node "N$i" "title=Concurrent node $i" state=review >"$SCRATCH/status-$i.log" 2>&1 &
  pids[${#pids[@]}]=$!
done
for pid in "${pids[@]}"; do
  wait "$pid"; assert_eq "parallel-writer-$pid" 0 "$?"
done
assert_eq all-appended-lines 20 "$(grep -c ' — parallel-entry-' "$ledger")"
for i in $(seq 1 20); do
  assert_eq "unique-entry-$i" 1 "$(grep -c " — parallel-entry-$i\$" "$ledger")"
done
assert_eq all-node-updates 20 "$(jq '.nodes|length' "$run/status.json")"
assert_eq matrix-begin-once 1 "$(grep -c '^<!-- status-matrix:begin -->$' "$ledger")"
assert_eq matrix-end-once 1 "$(grep -c '^<!-- status-matrix:end -->$' "$ledger")"
assert_eq matrix-node-rows 20 "$(grep -c '^| N[0-9]' "$ledger")"
assert_contains matrix-header '| node | title | state | PR | CI |' "$(cat "$ledger")"
# All 20 rows must be inside the markers, all appended entries after them.
awk '
  /^<!-- status-matrix:begin -->$/ { inside=1; next }
  /^<!-- status-matrix:end -->$/ { inside=0; ended=1; next }
  /^\| N[0-9]/ { if (!inside) bad=1; nodes++ }
  / — parallel-entry-/ { if (inside || !ended) bad=1; entries++ }
  END { exit (bad || inside || nodes != 20 || entries != 20) }
' "$ledger"
assert_eq well-formed-matrix 0 "$?"
"$L" "$ledger" >/dev/null 2>&1; assert_eq missing-entry-usage 2 "$?"
"$L" >/dev/null 2>&1; assert_eq missing-file-exit-preserved 1 "$?"
finish

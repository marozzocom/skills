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
assert_contains recovery-hint "status lock held for 5 s — another writer may be running; if none is, remove $run/.status.lock" "$out"
bounded=no; if [ "$elapsed" -ge 4 ] && [ "$elapsed" -le 8 ]; then bounded=yes; fi
assert_eq timeout-bounded yes "$bounded"
held=no; if [ -d "$run/.status.lock" ]; then held=yes; fi
assert_eq foreign-lock-preserved yes "$held"
cmp -s "$SCRATCH/before-timeout" "$ledger"; assert_eq timeout-no-write 0 "$?"
wait "$holder"; assert_eq timeout-holder-exit 0 "$?"

# Start 20 pairs together; give this burst headroom over the default bound
# tested above. Every successful append must survive every matrix mv.
pids=(); logs=()
for i in $(seq 1 20); do
  STATUS_LOCK_WAIT=20 "$L" "$ledger" "parallel-entry-$i" >"$SCRATCH/append-$i.log" 2>&1 &
  pids[${#pids[@]}]=$!
  logs[${#logs[@]}]=$SCRATCH/append-$i.log
  STATUS_LOCK_WAIT=20 "$S" "$run" node "N$i" "title=Concurrent node $i" state=review >"$SCRATCH/status-$i.log" 2>&1 &
  pids[${#pids[@]}]=$!
  logs[${#logs[@]}]=$SCRATCH/status-$i.log
done
idx=0
for pid in "${pids[@]}"; do
  wait "$pid"; rc=$?
  assert_eq "parallel-writer-$pid" 0 "$rc"
  if [ "$rc" != 0 ]; then cat "${logs[$idx]}" >&2; fi
  idx=$((idx + 1))
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
SECONDS=0
out=$(STATUS_LOCK_WAIT=20 "$L" "$SCRATCH/missing/ledger.md" nope 2>&1); rc=$?; elapsed=$SECONDS
assert_eq missing-directory-exit 1 "$rc"
assert_contains missing-directory-message "no such directory: $SCRATCH/missing" "$out"
immediate=no; if [ "$elapsed" -le 1 ]; then immediate=yes; fi
assert_eq missing-directory-immediate yes "$immediate"
# Nonregular files must fail before opening, especially a FIFO with no reader.
for kind in fifo directory symlink dangling; do
  nonfile=$SCRATCH/nonfile-$kind; mkdir "$nonfile"
  cp "$ledger" "$nonfile/target"
  case $kind in
    fifo) mkfifo "$nonfile/ledger.md" ;;
    directory) mkdir "$nonfile/ledger.md" ;;
    symlink) ln -s target "$nonfile/ledger.md" ;;
    dangling) ln -s missing "$nonfile/ledger.md" ;;
  esac
  SECONDS=0
  if [ "$kind" = fifo ]; then
    "$L" "$nonfile/ledger.md" rejected >"$SCRATCH/fifo.log" 2>&1 & writer=$!
    # Bound a regression that would otherwise block the entire suite forever.
    (sleep 2; : >"$SCRATCH/fifo-timeout"; kill "$writer" 2>/dev/null) & watchdog=$!
    wait "$writer"; rc=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    out=$(cat "$SCRATCH/fifo.log")
    timed_out=no; if [ -f "$SCRATCH/fifo-timeout" ]; then timed_out=yes; fi
    assert_eq fifo-no-timeout no "$timed_out"
  else
    out=$("$L" "$nonfile/ledger.md" rejected 2>&1); rc=$?
  fi
  elapsed=$SECONDS
  assert_eq "$kind-exit" 1 "$rc"
  assert_contains "$kind-message" 'ledger is not a regular file' "$out"
  immediate=no; if [ "$elapsed" -le 1 ]; then immediate=yes; fi
  assert_eq "$kind-immediate" yes "$immediate"
  released=no; if [ ! -d "$nonfile/.status.lock" ]; then released=yes; fi
  assert_eq "$kind-lock-released" yes "$released"
  cmp -s "$ledger" "$nonfile/target"; assert_eq "$kind-target-unchanged" 0 "$?"
  case $kind in
    fifo) kept=no; if [ -p "$nonfile/ledger.md" ]; then kept=yes; fi ;;
    directory) kept=no; if [ -d "$nonfile/ledger.md" ]; then kept=yes; fi ;;
    symlink) kept=no; if [ "$(readlink "$nonfile/ledger.md")" = target ]; then kept=yes; fi ;;
    dangling) kept=no; if [ "$(readlink "$nonfile/ledger.md")" = missing ]; then kept=yes; fi ;;
  esac
  assert_eq "$kind-file-kept" yes "$kept"
done
# A short override leaves foreign locks and temporary files alone.
mkdir "$run/.status.lock"
for stem in .status-set.tmp .ledger.tmp .ledger-seed.tmp; do : >"$run/$stem.abcdef"; done
for name in .status.backup .ledger.mirror .status-set.tmp.short .ledger.tmp.toolong; do : >"$run/$name"; done
out=$(STATUS_LOCK_WAIT=0.2 "$L" "$ledger" blocked 2>&1); assert_eq wait-override-exit 1 "$?"
assert_contains wait-override-message 'status lock held for 0.2 s' "$out"
assert_eq foreign-temp-kept 3 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
rmdir "$run/.status.lock"
"$L" "$ledger" cleanup >/dev/null
assert_eq leftover-temps-removed 0 "$(find "$run" -name '*.abcdef' | wc -l | tr -d ' ')"
for name in .status.backup .ledger.mirror .status-set.tmp.short .ledger.tmp.toolong; do
  kept=no; if [ -f "$run/$name" ]; then kept=yes; fi
  assert_eq "unrelated-$name-kept" yes "$kept"
done
mkdir "$run/.ledger.tmp.dirdir"
out=$("$L" "$ledger" 'directory temp cleanup' 2>&1); assert_eq temp-directory-write-exit 0 "$?"
assert_contains temp-directory-write-confirmed ' — directory temp cleanup' "$out"
assert_not_contains temp-directory-no-cleanup-noise 'rm:' "$out"
kept=no; if [ -d "$run/.ledger.tmp.dirdir" ]; then kept=yes; fi
assert_eq temp-directory-kept yes "$kept"
STATUS_LOCK_WAIT=bad "$L" "$ledger" nope >/dev/null 2>&1; assert_eq invalid-wait-usage 2 "$?"
mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
(umask 077; "$L" "$run/new.md" new >/dev/null)
assert_eq new-ledger-mode-077 600 "$(mode_of "$run/new.md")"
(umask 022; "$L" "$run/public.md" new >/dev/null)
assert_eq new-ledger-mode-022 644 "$(mode_of "$run/public.md")"
chmod 640 "$run/new.md"
"$L" "$run/new.md" again >/dev/null
assert_eq existing-ledger-mode 640 "$(mode_of "$run/new.md")"
finish

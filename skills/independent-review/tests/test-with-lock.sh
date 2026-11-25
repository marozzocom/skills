#!/usr/bin/env bash
# with-lock.sh: exclusive, queued, bounded, re-entrant, and never free while
# its command still runs.
# shellcheck disable=SC2016 # Literal command strings must expand in the child shell.
# shellcheck source=tests/lib.sh disable=SC1091 # Followed only with -x.
. "$(dirname "$0")/lib.sh"
W=$BIN_DIR/with-lock.sh
export ORCHESTRATION_LOCK_DIR="$SCRATCH/locks"
out=$("$W" a -- sh -c 'echo "held=$ORCHESTRATION_LOCKS_HELD"; exit 7' 2>&1); rc=$?
assert_eq command-exit 7 "$rc"
assert_eq command-sees-lock held=a "$out"
assert_eq directory-private "$ORCHESTRATION_LOCK_DIR" "$(find "$ORCHESTRATION_LOCK_DIR" -prune -perm 700)"
# Exclusive: two holders never overlap.
for _ in 1 2 3; do
  "$W" a -- sh -c 'echo start >>"$1"; sleep 1; echo end >>"$1"' _ "$SCRATCH/order" &
done
wait
assert_eq serialized 'start end start end start end' "$(tr '\n' ' ' <"$SCRATCH/order" | sed 's/ $//')"
# Different names do not block each other.
"$W" a -- sleep 2 &
holder=$!; sleep 0.5
out=$(WITH_LOCK_WAIT=0 "$W" b -- echo free 2>&1); rc=$?
assert_eq other-name-free "0 free" "$rc $out"
# Bounded wait: 75, the command never ran, and the holder is named.
began=$SECONDS
out=$(WITH_LOCK_WAIT=0 "$W" a -- touch "$SCRATCH/ran" 2>&1); rc=$?
# Nothing the wrapper starts keeps the caller's pipe open.
assert_eq timeout-prompt yes "$([ $((SECONDS - began)) -le 1 ] && echo yes || echo no)"
assert_eq timeout-exit 75 "$rc"
assert_eq timeout-no-command no "$([ -e "$SCRATCH/ran" ] && echo yes || echo no)"
assert_contains timeout-waiting 'waiting for a — held by: pid ' "$out"
assert_contains timeout-holder 'a not acquired within 0s — held by: pid ' "$out"
assert_contains timeout-holder-command 'command sleep 2' "$out"
wait "$holder"
# Re-entrant: a name already held runs the command directly.
out=$(WITH_LOCK_WAIT=0 "$W" a -- "$W" a -- echo nested 2>&1); rc=$?
assert_eq reentrant "0 nested" "$rc $out"
out=$(WITH_LOCK_WAIT=0 "$W" a -- "$W" b -- sh -c 'echo "$ORCHESTRATION_LOCKS_HELD"' 2>&1)
assert_eq nested-names a:b "$out"
# TERM to the wrapper ends the command before the lock can be taken again.
"$W" a -- sh -c 'echo $$ >"$1"; exec sleep 30' _ "$SCRATCH/cpid" &
wrapper=$!; sleep 0.7
kill -TERM "$wrapper"; wait "$wrapper"; rc=$?
assert_eq term-exit 143 "$rc"
assert_eq term-command-gone gone "$(kill -0 "$(cat "$SCRATCH/cpid")" 2>/dev/null && echo alive || echo gone)"
out=$(WITH_LOCK_WAIT=0 "$W" a -- echo free 2>&1); rc=$?
assert_eq term-lock-free "0 free" "$rc $out"
# The command keeps default INT handling: it can trap INT, which a process
# started with INT ignored cannot. Skipped when this test itself was started
# with INT ignored (a backgrounded run without job control).
trap : INT
if [ -n "$(trap -p INT)" ]; then
  trap - INT
  out=$("$W" a -- "$BASH" -c 'trap "echo trapped" INT; kill -INT $$; :' 2>&1)
  assert_eq command-int-default trapped "$out"
else echo "skipped: INT ignored on entry" >&2; fi
# INT to the wrapper reaches the command as TERM.
# Job control gives the wrapper default INT handling, as a foreground run has.
set -m
"$W" a -- sh -c 'echo $$ >"$1"; exec sleep 30' _ "$SCRATCH/ipid" &
wrapper=$!; set +m; sleep 0.7
began=$SECONDS
kill -INT "$wrapper"; wait "$wrapper"; rc=$?
assert_eq int-exit 130 "$rc"
assert_eq int-prompt yes "$([ $((SECONDS - began)) -le 5 ] && echo yes || echo no)"
assert_eq int-command-gone gone "$(kill -0 "$(cat "$SCRATCH/ipid")" 2>/dev/null && echo alive || echo gone)"
# HUP is forwarded as HUP.
"$W" a -- sh -c 'echo $$ >"$1"; exec sleep 30' _ "$SCRATCH/hpid" &
wrapper=$!; sleep 0.7
kill -HUP "$wrapper"; wait "$wrapper"; rc=$?
assert_eq hup-exit 129 "$rc"
assert_eq hup-command-gone gone "$(kill -0 "$(cat "$SCRATCH/hpid")" 2>/dev/null && echo alive || echo gone)"
# TERM while still waiting gives up without running the command.
"$W" a -- sleep 3 &
holder=$!; sleep 0.5
"$W" a -- touch "$SCRATCH/ran-late" 2>/dev/null &
waiter=$!; sleep 0.5
kill -TERM "$waiter"; wait "$waiter"; rc=$?
wait "$holder"; sleep 0.3
assert_eq term-waiting-exit 143 "$rc"
assert_eq term-waiting-no-command no "$([ -e "$SCRATCH/ran-late" ] && echo yes || echo no)"
# Usage and an unusable directory.
for args in '' 'a' 'a --' 'a b c' 'bad/name -- true' '-x -- true' '--status -- true' \
  '--status' '--status -x' '--max-hold' '--max-hold soon a -- true' '--max-hold -1 a -- true' '--max-hold 5 -x -- true'; do
  # shellcheck disable=SC2086 # Word splitting builds the argument list.
  out=$("$W" $args 2>&1); rc=$?
  assert_eq "usage-$args" 2 "$rc"
done
out=$(WITH_LOCK_WAIT=soon "$W" a -- true 2>&1); rc=$?
assert_eq usage-wait 2 "$rc"
for setting in WITH_LOCK_MAX_HOLD=soon WITH_LOCK_KILL_GRACE=-1 WITH_LOCK_SAMPLE_INTERVAL=1.5 \
  WITH_LOCK_STALE_IDLE=x WITH_LOCK_DEPTH_STEP=x WITH_LOCK_DEADLINE=soon; do
  out=$(env "$setting" "$W" a -- touch "$SCRATCH/ran-setting" 2>&1); rc=$?
  assert_eq "usage-$setting" 2 "$rc"
done
# Staggered kills need a free depth below the cap.
out=$(ORCHESTRATION_LOCKS_HELD=1:2:3:4:5:6:7:8 "$W" --max-hold 5 a -- touch "$SCRATCH/ran-setting" 2>&1); rc=$?
assert_eq usage-too-deep 2 "$rc"
# A zero depth step would let nested holders KILL at the same moment.
out=$(WITH_LOCK_DEPTH_STEP=0 "$W" --max-hold 5 a -- touch "$SCRATCH/ran-setting" 2>&1); rc=$?
assert_eq usage-zero-step 2 "$rc"
for setting in WITH_LOCK_OUTER_KILL_AT=soon WITH_LOCK_OUTER_KILL_WAIT=-1; do
  out=$(env "$setting" "$W" a -- touch "$SCRATCH/ran-setting" 2>&1); rc=$?
  assert_eq "usage-$setting" 2 "$rc"
done
assert_eq usage-setting-no-command no "$([ -e "$SCRATCH/ran-setting" ] && echo yes || echo no)"
ln -s "$SCRATCH" "$SCRATCH/link"
out=$(ORCHESTRATION_LOCK_DIR="$SCRATCH/link" "$W" a -- touch "$SCRATCH/ran-link" 2>&1); rc=$?
assert_eq symlink-dir-refused 1 "$rc"
assert_eq symlink-dir-no-command no "$([ -e "$SCRATCH/ran-link" ] && echo yes || echo no)"
# Neither flock nor lockf: refuse rather than run unlocked.
mkdir "$SCRATCH/bare"
for tool in id mkdir mktemp; do ln -s "$(command -v $tool)" "$SCRATCH/bare/$tool"; done
out=$(PATH="$SCRATCH/bare" "$BASH" "$W" a -- "$BASH" -c ': >"$1"' _ "$SCRATCH/ran-bare" 2>&1); rc=$?
assert_eq no-tool-exit 2 "$rc"
assert_eq no-tool-no-command no "$([ -e "$SCRATCH/ran-bare" ] && echo yes || echo no)"
# flock is preferred when present; a stub pins the argument shape.
cat >"$SCRATCH/bare/flock" <<'STUB'
#!/bin/sh
echo "flock $*" >>"$FLOCK_LOG"
[ "$1" = -n ] && exit 0
[ "$1" = -o ] && shift
[ "$1" = -w ] && shift 2
shift; exec "$@"
STUB
chmod +x "$SCRATCH/bare/flock"
for tool in rm head date tr cat; do ln -s "$(command -v $tool)" "$SCRATCH/bare/$tool"; done
out=$(FLOCK_LOG="$SCRATCH/flock.log" WITH_LOCK_WAIT=5 PATH="$SCRATCH/bare" "$BASH" "$W" a -- "$BASH" -c 'echo via-flock' 2>&1); rc=$?
assert_eq flock-run "0 via-flock" "$rc $out"
assert_contains flock-probe "flock -n $ORCHESTRATION_LOCK_DIR/a.lock true" "$(cat "$SCRATCH/flock.log")"
assert_contains flock-wait "flock -o -w 5 $ORCHESTRATION_LOCK_DIR/a.lock " "$(cat "$SCRATCH/flock.log")"
# Sampling without ps is quiet: liveness is "uncheckable", never idle.
mkdir "$SCRATCH/bare-sleep"
for tool in id mkdir mktemp rm head date tr cat sleep mv; do ln -s "$(command -v $tool)" "$SCRATCH/bare-sleep/$tool"; done
cp "$SCRATCH/bare/flock" "$SCRATCH/bare-sleep/flock"
out=$(FLOCK_LOG="$SCRATCH/flock.log" WITH_LOCK_SAMPLE_INTERVAL=1 PATH="$SCRATCH/bare-sleep" "$BASH" "$W" nops -- sleep 2 2>&1); rc=$?
assert_eq no-ps-quiet "0 " "$rc $out"
assert_contains no-ps-uncheckable liveness=uncheckable "$(cat "$ORCHESTRATION_LOCK_DIR/nops.meta" 2>/dev/null)"

gone() { kill -0 "$1" 2>/dev/null && echo alive || echo gone; }
group_gone() { kill -0 -- -"$1" 2>/dev/null && echo alive || echo gone; }
meta_value() { sed -n "s/^$2=//p" "$ORCHESTRATION_LOCK_DIR/$1.meta"; }
# TERM to the wrapper reaches the whole group, not one pid: a child the
# command started is gone before the lock can be taken again.
"$W" a -- "$BASH" -c 'sleep 30 & echo $! >"$1"; wait' _ "$SCRATCH/gpid" &
wrapper=$!; sleep 0.7
began=$SECONDS
kill -TERM "$wrapper"; wait "$wrapper"; rc=$?
# Prompt: the TERM itself reached the child, not the later KILL escalation.
assert_eq group-term-prompt yes "$([ $((SECONDS - began)) -le 3 ] && echo yes || echo "no: $((SECONDS - began))s")"
assert_eq group-term-exit 143 "$rc"
assert_eq group-term-child-gone gone "$(gone "$(cat "$SCRATCH/gpid")")"
out=$(WITH_LOCK_WAIT=0 "$W" a -- echo free 2>&1); rc=$?
assert_eq group-term-lock-free "0 free" "$rc $out"
# Max hold: a hung command (not exec'd) is terminated with its group, exit
# 124, the lock is free at once, and the caller's pipe is not held open.
began=$SECONDS
out=$(WITH_LOCK_KILL_GRACE=1 WITH_LOCK_DEPTH_STEP=1 "$W" --max-hold 1 a -- "$BASH" -c 'sleep 30; :' 2>&1); rc=$?
assert_eq max-hold-exit 124 "$rc"
assert_eq max-hold-prompt yes "$([ $((SECONDS - began)) -le 4 ] && echo yes || echo "no: $((SECONDS - began))s")"
assert_contains max-hold-message "with-lock.sh: a exceeded max-hold (1s) — terminated pid $(meta_value a pid)" "$out"
assert_eq max-hold-group-gone gone "$(group_gone "$(meta_value a pgid)")"
out=$(WITH_LOCK_WAIT=0 "$W" a -- echo free 2>&1); rc=$?
assert_eq max-hold-lock-free "0 free" "$rc $out"
# The environment sets it too, and a TERM-ignoring child is killed (the fake
# held list puts the lock at the deepest stagger: KILL after one second).
out=$(ORCHESTRATION_LOCKS_HELD=x1:x2:x3:x4:x5:x6:x7 WITH_LOCK_MAX_HOLD=1 WITH_LOCK_KILL_GRACE=0 WITH_LOCK_DEPTH_STEP=1 "$W" a -- \
  "$BASH" -c 'trap "" TERM; sleep 30 & echo $! >"$1"; wait; :' _ "$SCRATCH/kpid" 2>&1); rc=$?
assert_eq max-hold-env-exit 124 "$rc"
assert_eq max-hold-kill-child-gone gone "$(gone "$(cat "$SCRATCH/kpid")")"
# Nested: the inner lock inherits the absolute deadline (a longer max hold
# of its own does not extend it), its TERM-ignoring command dies before the
# outer lock is released, and no holder of either lock overlaps it. The fake
# held list puts both at the deepest stagger, so kills come within seconds.
cat >"$SCRATCH/nested.sh" <<'NESTED'
echo "outer=$WITH_LOCK_DEADLINE"
exec "$1" --max-hold 100 b -- "$BASH" -c 'echo "inner=$WITH_LOCK_DEADLINE"; trap "" TERM; sleep 30 & echo $! >"$1"; wait; :' _ "$2"
NESTED
ORCHESTRATION_LOCKS_HELD=x1:x2:x3:x4:x5:x6 WITH_LOCK_KILL_GRACE=0 WITH_LOCK_DEPTH_STEP=1 \
  "$W" --max-hold 2 a -- "$BASH" "$SCRATCH/nested.sh" "$W" "$SCRATCH/npid" >"$SCRATCH/nested.out" 2>&1 &
nested=$!; sleep 0.7
overlap='if kill -0 "$(cat "$1")" 2>/dev/null; then echo overlap; else echo clean; fi'
WITH_LOCK_WAIT=20 "$W" a -- sh -c "$overlap" _ "$SCRATCH/npid" >"$SCRATCH/contend-a" 2>/dev/null &
contend_a=$!
WITH_LOCK_WAIT=20 "$W" b -- sh -c "$overlap" _ "$SCRATCH/npid" >"$SCRATCH/contend-b" 2>/dev/null &
contend_b=$!
wait "$nested"; rc=$?
wait "$contend_a" "$contend_b"
assert_eq nested-exit 124 "$rc"
assert_contains nested-outer-message 'a exceeded max-hold (2s)' "$(cat "$SCRATCH/nested.out")"
outer=$(sed -n 's/^outer=//p' "$SCRATCH/nested.out"); inner=$(sed -n 's/^inner=//p' "$SCRATCH/nested.out")
assert_eq nested-deadline-inherited "$outer" "$inner"
assert_eq nested-inner-gone gone "$(gone "$(cat "$SCRATCH/npid")")"
assert_eq nested-no-overlap-a clean "$(cat "$SCRATCH/contend-a")"
assert_eq nested-no-overlap-b clean "$(cat "$SCRATCH/contend-b")"
# An inner lock given a longer KILL grace than its outer one (as a desktop
# lock may be) still kills its TERM-ignoring command before the outer lock
# is released: it clamps its KILL below the outer holder's.
rm -f "$SCRATCH/npid"
ORCHESTRATION_LOCKS_HELD=x1:x2:x3:x4:x5:x6 WITH_LOCK_KILL_GRACE=0 WITH_LOCK_DEPTH_STEP=1 \
  "$W" --max-hold 2 a -- env WITH_LOCK_KILL_GRACE=5 "$W" b -- \
  "$BASH" -c 'trap "" TERM; sleep 30 & echo $! >"$1"; wait; :' _ "$SCRATCH/npid" >"$SCRATCH/clamp.out" 2>&1 &
nested=$!; sleep 0.7
WITH_LOCK_WAIT=20 "$W" a -- sh -c "$overlap" _ "$SCRATCH/npid" >"$SCRATCH/contend-a" 2>/dev/null &
contend_a=$!
wait "$nested"; rc=$?
wait "$contend_a"
assert_eq clamp-exit 124 "$rc"
assert_eq clamp-no-overlap clean "$(cat "$SCRATCH/contend-a")"
assert_eq clamp-inner-gone gone "$(gone "$(cat "$SCRATCH/npid")")"
# The caller's errexit (SHELLOPTS or a BASH_ENV with set -e) never ends the
# supervisor on its 1-second tick: the lock stays held for the whole command,
# whose status is kept, and the command still gets errexit and BASH_ENV.
printf 'set -e\n' >"$SCRATCH/errexit-env"
for how in "SHELLOPTS=errexit" "BASH_ENV=$SCRATCH/errexit-env"; do
  env "$how" WITH_LOCK_SAMPLE_INTERVAL=1 "$W" a -- \
    "$BASH" -c 'case $- in *e*) echo errexit ;; esac; echo "env=${BASH_ENV-}"; sleep 3; exit 7' >"$SCRATCH/errexit.out" 2>&1 &
  holder=$!; sleep 1.8
  out=$(WITH_LOCK_WAIT=0 "$W" a -- echo overlap 2>/dev/null); rc=$?
  assert_eq "errexit-no-overlap-${how%%=*}" "75 " "$rc $out"
  wait "$holder"; rc=$?
  assert_eq "errexit-status-${how%%=*}" 7 "$rc"
  assert_contains "errexit-kept-${how%%=*}" errexit "$(cat "$SCRATCH/errexit.out")"
done
assert_contains errexit-bash-env-kept "env=$SCRATCH/errexit-env" "$(cat "$SCRATCH/errexit.out")"
# An exported CDPATH does not change where a relative invocation finds itself.
mkdir -p "$SCRATCH/cdpath/bin"
for cdpath in . "$SCRATCH/cdpath"; do
  out=$(cd "$BIN_DIR/.." && CDPATH=$cdpath "$BASH" bin/with-lock.sh a -- echo ok 2>&1); rc=$?
  assert_eq "cdpath-$cdpath" "0 ok" "$rc $out"
done
# The liveness sample from a fixed ps listing: BSD M:SS.cc and procps
# [DD-]HH:MM:SS times, descendants in other groups, a lock tool waiting (no
# child) or holding (a child), and a parse independent of a comma-decimal
# locale where one is installed.
mkdir "$SCRATCH/stub-ps"
printf '#!/bin/sh\ncat "$PS_FIXTURE"\n' >"$SCRATCH/stub-ps/ps"
chmod +x "$SCRATCH/stub-ps/ps"
cat >"$SCRATCH/ps-bsd" <<'PS'
    1     0     1 309:42.23 /sbin/launchd
  100     1   100   0:00.75 /bin/sh
  101   100   100   0:00.25 /bin/sleep
  102   100   102   0:00.00 /usr/bin/lockf
  555     1   555   1:00.00 /Applications/Some App.app/Contents/MacOS/Some App
PS
grep -v ' 101 ' "$SCRATCH/ps-bsd" >"$SCRATCH/ps-bsd-exited"
cat >"$SCRATCH/ps-procps" <<'PS'
  100     1   100 01:02:03 sh
  101   100   100 2-03:04:05 sleep
  102   100   102 00:00:00 flock
  103   102   103 00:00:01 bash
  556     1   556 00:10:00 other
PS
locale=C
if locale -a 2>/dev/null | grep -qx fi_FI.UTF-8; then locale=fi_FI.UTF-8
else echo "skipped: fi_FI.UTF-8 not installed, sampling checked in C only" >&2; fi
sample() { PS_FIXTURE=$1 PATH="$SCRATCH/stub-ps:$PATH" LC_ALL=$locale "$W" --members 100; }
assert_eq members-bsd '1 100,100,101,102' "$(sample "$SCRATCH/ps-bsd")"
assert_eq members-bsd-exited '1 75,100,102' "$(sample "$SCRATCH/ps-bsd-exited")"
assert_eq members-procps '0 18756900,100,101,102,103' "$(sample "$SCRATCH/ps-procps")"
# Live ps checks run only where ps can list processes (not in a sandbox).
if ps -A -o pid=,ppid=,pgid=,time=,comm= >/dev/null 2>&1; then
# Liveness, sampled every second; idle from 4 seconds is stale. Holders: idle,
# busy, a child replaced at 2.5s (a pid change is activity, whatever the CPU
# sum does), and one waiting on another lock. Read at about 5.2s, the margins
# cover whole-second clocks and up to two seconds of sampling lag.
export WITH_LOCK_SAMPLE_INTERVAL=1 WITH_LOCK_STALE_IDLE=4
"$W" idle -- sleep 10 &
p1=$!
"$W" busy -- "$BASH" -c 'end=$((SECONDS + 9)); while [ $SECONDS -lt $end ]; do :; done' &
p2=$!
"$W" swap -- sh -c 'sleep 2.5; sleep 7' &
p3=$!
"$W" inner -- sleep 10 &
p4=$!; sleep 0.3
"$W" outer -- "$W" inner -- true 2>/dev/null &
p5=$!; sleep 4.9
# Most time-sensitive first: swap's idle time grows from about 2.5s on.
out=$(WITH_LOCK_WAIT=0 "$W" swap -- true 2>&1)
assert_not_contains swap-not-stale STALE "$out"
assert_contains swap-sampled ', idle ' "$out"
out=$(WITH_LOCK_WAIT=0 "$W" busy -- true 2>&1)
assert_not_contains busy-active STALE "$out"
assert_contains busy-sampled ', idle ' "$out"
out=$("$W" --status busy)
assert_not_contains busy-status-not-stale stale "$out"
out=$(WITH_LOCK_WAIT=0 "$W" outer -- true 2>&1)
assert_contains outer-waiting ', waiting on another lock]' "$out"
out=$("$W" --status outer)
assert_contains outer-status-waiting '[waiting on another lock]' "$out"
out=$(WITH_LOCK_WAIT=0 "$W" idle -- true 2>&1)
assert_contains idle-waiter 'waiting for idle — held by: pid ' "$out"
assert_contains idle-stale ' — STALE]' "$out"
assert_contains idle-timeout-stale 'idle not acquired within 0s — held by: pid ' "$out"
out=$("$W" --status idle); rc=$?
assert_eq status-held-exit 1 "$rc"
assert_contains status-held 'held: pid ' "$out"
assert_contains status-stale '[stale]' "$out"
# Waiting for the holders is not part of the test.
kill "$p1" "$p2" "$p3" "$p4"
wait "$p1" "$p2" "$p3" "$p4" "$p5"
unset WITH_LOCK_SAMPLE_INTERVAL WITH_LOCK_STALE_IDLE
else echo "skipped: ps cannot list processes" >&2; fi
# --status: a free lock; a missing directory; a free lock whose last holder
# never finished (its supervisor was killed) and whose group still runs.
out=$("$W" --status fresh); rc=$?
assert_eq status-free "0 free" "$rc $out"
out=$(ORCHESTRATION_LOCK_DIR="$SCRATCH/no-such-dir" "$W" --status fresh); rc=$?
assert_eq status-no-dir "0 free" "$rc $out"
set -m
sleep 30 &
orphan=$!
set +m
printf 'pid %s, since 2026-01-01T00:00:00Z, cwd /, command sleep 30 ' "$orphan" >"$ORCHESTRATION_LOCK_DIR/orphan.holder"
printf 'pid=%s\npgid=%s\nsince_epoch=1\ndeadline=0\nlast_activity_epoch=1\nwaiting_on_lock=0\nliveness=ok\n' \
  "$orphan" "$orphan" >"$ORCHESTRATION_LOCK_DIR/orphan.meta"
out=$("$W" --status orphan); rc=$?
assert_eq status-orphan "0 free (WARNING: last holder group $orphan still alive — pid $orphan, since 2026-01-01T00:00:00Z, cwd /, command sleep 30)" "$rc $out"
kill "$orphan"; wait "$orphan" 2>/dev/null
out=$("$W" --status orphan); rc=$?
assert_eq status-orphan-gone "0 free" "$rc $out"
finish

#!/usr/bin/env bash
# with-lock.sh: exclusive, queued, bounded, re-entrant, and never free while
# its command still runs.
# shellcheck disable=SC2016 # Literal command strings must expand in the child shell.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
W=$BIN_DIR/with-lock.sh
export ORCHESTRATION_LOCK_DIR="$SCRATCH/locks"
out=$("$W" a -- sh -c 'echo "held=$ORCHESTRATION_LOCKS_HELD"; exit 7' 2>&1); rc=$?
assert_eq command-exit 7 "$rc"
assert_eq command-sees-lock held=a "$out"
assert_eq directory-private "$ORCHESTRATION_LOCK_DIR" "$(find "$ORCHESTRATION_LOCK_DIR" -prune -perm 700)"
# Exclusive: two holders never overlap.
for i in 1 2 3; do
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
out=$(WITH_LOCK_WAIT=0 "$W" a -- touch "$SCRATCH/ran" 2>&1); rc=$?
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
for args in '' 'a' 'a --' 'a b c' 'bad/name -- true'; do
  # shellcheck disable=SC2086 # Word splitting builds the argument list.
  out=$("$W" $args 2>&1); rc=$?
  assert_eq "usage-$args" 2 "$rc"
done
out=$(WITH_LOCK_WAIT=soon "$W" a -- true 2>&1); rc=$?
assert_eq usage-wait 2 "$rc"
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
finish

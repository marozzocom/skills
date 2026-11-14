#!/usr/bin/env bash
# with-lock.sh NAME -- COMMAND [ARG...]
# Runs COMMAND while holding the machine-wide exclusive lock NAME, so heavy
# local work (full gate runs, native GUI suites) queues across sessions and
# agents instead of running at once. NAME is [A-Za-z0-9._-]+.
# The lock is a kernel lock (flock when present, else lockf) on
# ${ORCHESTRATION_LOCK_DIR:-/tmp/orchestration-locks-<uid>}/NAME.lock: it is
# released when the holder exits, so nothing goes stale. The directory is
# created mode 700 and refused when it is a symlink or owned by someone else.
# Waiting: without limit by default; WITH_LOCK_WAIT=<whole seconds> bounds it.
# A busy lock prints "with-lock.sh: waiting for NAME — held by: <holder>" to
# stderr, the holder line coming from NAME.holder (pid, start, cwd, command),
# which the holder writes after acquiring and nobody deletes: read it only
# together with "waiting" or "not acquired".
# Re-entrant: COMMAND sees NAME in ORCHESTRATION_LOCKS_HELD (colon list), and
# a nested with-lock.sh for a name already held runs its command directly.
# Take several locks by nesting, always in one fixed order.
# COMMAND runs in its own process group with default signal handling, as a
# foreground command would. TERM and HUP sent to the wrapper are forwarded to
# COMMAND, INT reaches it as TERM, and the wrapper waits for it, so a signal
# to the wrapper never frees the lock while COMMAND still runs. kill -9 of
# the wrapper leaves COMMAND running with the lock held until it ends; a
# wrapper started with INT already ignored cannot see INT. The lock belongs to
# the flock/lockf process: killing that process directly, or signalling the
# whole process group (a closed terminal), frees the lock while COMMAND may
# still be shutting down. With flock the lock is not passed on to COMMAND
# (-o), so a daemon COMMAND leaves behind does not keep it, as with lockf.
# Exit: COMMAND's status; 75 the lock was not acquired within WITH_LOCK_WAIT
# (COMMAND never ran); 128+N ended by signal N; 1 lock directory unusable;
# 2 usage, or neither flock nor lockf is installed.
set -u

usage() { printf 'with-lock.sh: %s\n' "$*" >&2; exit 2; }
[ $# -ge 3 ] && [ "$2" = -- ] || usage 'usage: with-lock.sh NAME -- COMMAND [ARG...]'
name=$1; shift 2
[[ $name =~ ^[A-Za-z0-9._-]+$ ]] || usage "bad lock name: $name"
wait_s=${WITH_LOCK_WAIT-}
[[ -z $wait_s || $wait_s =~ ^[0-9]+$ ]] || usage "WITH_LOCK_WAIT must be whole seconds: $wait_s"

case ":${ORCHESTRATION_LOCKS_HELD-}:" in *":$name:"*) exec "$@" ;; esac

if command -v flock >/dev/null 2>&1; then tool=flock
elif command -v lockf >/dev/null 2>&1; then tool=lockf
else usage 'needs flock or lockf on PATH'; fi

dir=${ORCHESTRATION_LOCK_DIR:-/tmp/orchestration-locks-$(id -u)}
[ -d "$dir" ] || mkdir -m 700 "$dir" 2>/dev/null
[ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] ||
  { printf 'with-lock.sh: lock directory unusable: %s\n' "$dir" >&2; exit 1; }
lock=$dir/$name.lock; holder=$dir/$name.holder
state=$(mktemp -d "${TMPDIR:-/tmp}/with-lock.XXXXXX") || exit 1
trap 'rm -rf "$state"' EXIT

held_by() { if [ -s "$holder" ]; then head -n 1 "$holder"; else echo unknown; fi; }
# Informational probe: taking and dropping a free lock changes nothing.
if [ "$tool" = flock ]; then flock -n "$lock" true 2>/dev/null; else lockf -k -s -t 0 "$lock" true 2>/dev/null; fi ||
  printf 'with-lock.sh: waiting for %s — held by: %s\n' "$name" "$(held_by)" >&2

# Runs under the lock. Writing the pid file is the proof of acquisition; the
# cancel check closes the gap between acquiring and a signal already handled.
# shellcheck disable=SC2016 # Expanded by the locked child shell.
inner='state=$1 holder=$2 name=$3; shift 3
printf "%s\n" "$$" >"$state/pid"
[ ! -e "$state/cancel" ] || exit 143
printf "pid %s, since %s, cwd %s, command %s\n" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PWD" "$*" |
  tr "\n" " " >"$holder" 2>/dev/null || true
export ORCHESTRATION_LOCKS_HELD="${ORCHESTRATION_LOCKS_HELD:+$ORCHESTRATION_LOCKS_HELD:}$name"
exec "$@"'
if [ "$tool" = flock ]; then locker=(flock -o ${wait_s:+-w "$wait_s"} "$lock")
else locker=(lockf -k -s ${wait_s:+-t "$wait_s"} "$lock"); fi

signal=0
# shellcheck disable=SC2329 # Invoked by the traps below.
forward() { # <signal to send> <number received>
  signal=$2; : >"$state/cancel"
  if [ -s "$state/pid" ]; then kill -"$1" "$(cat "$state/pid")" 2>/dev/null
  else kill -"$1" "$child" 2>/dev/null; fi
}
# Job control for the spawn only: without it a background child starts with
# INT ignored, and so would everything COMMAND runs.
set -m
"${locker[@]}" "$BASH" --noprofile --norc -c "$inner" _ "$state" "$holder" "$name" "$@" &
child=$!
set +m
trap 'forward TERM 15' TERM; trap 'forward TERM 2' INT; trap 'forward HUP 1' HUP
# A trapped signal interrupts wait; keep waiting until the locker is gone.
while :; do
  wait "$child"; rc=$?
  kill -0 "$child" 2>/dev/null || break
done
[ "$signal" = 0 ] || exit $((128 + signal))
if [ ! -e "$state/pid" ]; then
  printf 'with-lock.sh: %s not acquired within %ss — held by: %s\n' "$name" "${wait_s:-?}" "$(held_by)" >&2
  exit 75
fi
exit "$rc"

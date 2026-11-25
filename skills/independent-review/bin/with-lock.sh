#!/usr/bin/env bash
# with-lock.sh [--max-hold SECONDS] NAME -- COMMAND [ARG...]
# with-lock.sh --status NAME
# Runs COMMAND while holding the machine-wide exclusive lock NAME, so heavy
# local work (full gate runs, native GUI suites) queues across sessions and
# agents instead of running at once. NAME is [A-Za-z0-9._][A-Za-z0-9._-]*
# (it never starts with a dash).
# The lock is a kernel lock (flock when present, else lockf) on
# ${ORCHESTRATION_LOCK_DIR:-/tmp/orchestration-locks-<uid>}/NAME.lock: it is
# released when the holder exits, so nothing goes stale. The directory is
# created mode 700 and refused when it is a symlink or owned by someone else.
# Waiting: without limit by default; WITH_LOCK_WAIT=<whole seconds> bounds it.
# A busy lock prints "with-lock.sh: waiting for NAME — held by: <holder>" to
# stderr, the holder line coming from NAME.holder (pid, start, cwd, command),
# which the holder writes after acquiring and nobody deletes: read it only
# together with "waiting" or "not acquired". When the holder's NAME.meta
# matches, the line ends with its age and liveness: [held 12m, idle 6m],
# "— STALE" once idle reaches WITH_LOCK_STALE_IDLE (default 300 seconds), or
# [held 12m, waiting on another lock].
# Re-entrant: COMMAND sees NAME in ORCHESTRATION_LOCKS_HELD (colon list), and
# a nested with-lock.sh for a name already held runs its command directly
# (its --max-hold is then ignored; the outer holder's deadline applies).
# Take several locks by nesting, always in one fixed order.
#
# Supervision. Under the lock a supervisor shell starts COMMAND in its own
# process group with default signal handling, as a foreground command would,
# and stays alive until COMMAND ends. TERM and HUP sent to the wrapper are
# forwarded to the supervisor, INT as TERM; the supervisor sends the signal
# to COMMAND's whole process group and waits until COMMAND and every process
# left in that group have exited (TERM first, then KILL after the grace below)
# before it exits and the kernel lock is released. A COMMAND that exits on
# its own releases the lock at once: with flock the lock is not passed on
# (-o), so a daemon COMMAND leaves behind does not keep it, as with lockf.
# Trade-off: the lock belongs to the flock/lockf process and its supervisor
# child. kill -9 (or an out-of-memory kill) of the supervisor or of that
# locker process frees the lock while COMMAND's group may still run; nothing
# can clean up after KILL. --status then reports "free (WARNING: last holder
# group <pgid> still alive — <holder>)". kill -9 of the wrapper alone leaves
# the supervisor holding the lock until COMMAND ends. A wrapper started with
# INT already ignored cannot see INT.
#
# Max hold. --max-hold SECONDS, else WITH_LOCK_MAX_HOLD (0 or unset: no
# limit), bounds how long COMMAND may hold the lock. The deadline is absolute
# (epoch seconds) and exported to COMMAND as WITH_LOCK_DEADLINE; a nested
# with-lock.sh takes the earlier of that and its own max hold, so nesting
# never resets the budget. At the deadline the supervisor sends TERM to the
# group, waits WITH_LOCK_KILL_GRACE (default 5) plus (8 - depth) *
# WITH_LOCK_DEPTH_STEP (default 2) seconds, depth being the number of locks
# already held, so the innermost holder kills first; then KILL. It prints
# "with-lock.sh: NAME exceeded max-hold (Ns) — terminated pid P" and exits
# 124. A deadline with 8 or more locks already held, or with
# WITH_LOCK_DEPTH_STEP below 1, is refused (exit 2).
# Kill order across nesting: each supervisor exports when it will send KILL,
# absolute as WITH_LOCK_OUTER_KILL_AT (with a deadline) and relative to a
# TERM as WITH_LOCK_OUTER_KILL_WAIT. A nested holder clamps its own KILL to
# at least max(step, 2) seconds before that, whatever grace it was given, so
# an inner command is always killed before its outer lock can be released.
# Set WITH_LOCK_KILL_GRACE on the outermost call.
# Liveness. Every WITH_LOCK_SAMPLE_INTERVAL seconds (default 30, 0 off) the
# supervisor samples COMMAND's group and descendants with ps: any change in
# their summed CPU time or member pids is activity, and a flock/lockf with no
# child among them means COMMAND waits on another lock. NAME.meta (pid, pgid,
# since_epoch, deadline, last_activity_epoch, waiting_on_lock, liveness
# ok|uncheckable, ended_epoch once done) is replaced atomically; without ps
# liveness is "uncheckable" and nothing is reported as idle.
# --status NAME prints one line: "free" (exit 0), or "held: <holder> [age=Ns
# idle=Ms]" plus " [waiting on another lock]" or " [stale]" (exit 1). It takes
# and drops the lock for an instant when free: advisory, do not tight-poll.
# Exit: COMMAND's status; 124 max hold reached; 75 the lock was not acquired
# within WITH_LOCK_WAIT (COMMAND never ran); 128+N ended by signal N; 1 lock
# directory unusable; 2 usage, a bad setting, or neither flock nor lockf is
# installed. --supervise is internal: the wrapper's locked child.
# --members PGID prints the liveness sample for a group (diagnostics, tests).
# The caller's errexit (SHELLOPTS, BASH_ENV) never applies here: a failing
# wait must not end the supervisor while COMMAND runs. COMMAND gets the
# caller's errexit, BASH_ENV and ENV back.
set -u
case $- in *e*) had_errexit=1 ;; *) had_errexit=0 ;; esac
set +e
MAXDEPTH=8

usage() { printf 'with-lock.sh: %s\n' "$*" >&2; exit 2; }
# Whole seconds without leading zeros (so arithmetic never reads octal).
whole() { # <label> <value>
  [[ $2 =~ ^[0-9]{1,12}$ ]] || { printf 'with-lock.sh: %s must be whole seconds: %s\n' "$1" "$2" >&2; return 2; }
  printf '%s' "$((10#$2))"
}

# --- supervisor: runs under the kernel lock ----------------------------------
# awk over `ps -A -o pid=,ppid=,pgid=,time=,comm=`: COMMAND's group and all
# descendants. Prints "<waiting 0|1> <centiseconds>,<sorted pids>". time is
# [D-]H:MM:SS (procps) or M:SS.cc (BSD); comm may be a path with spaces.
# shellcheck disable=SC2016 # awk program text.
members_awk='
function cs(t,   d, a, n, i, m) {
  d = 0
  if (index(t, "-")) { d = substr(t, 1, index(t, "-") - 1) + 0; t = substr(t, index(t, "-") + 1) }
  n = split(t, a, ":"); m = 0
  for (i = 1; i < n; i++) m = m * 60 + a[i]
  return int((d * 86400 + m * 60 + a[n]) * 100 + 0.5)
}
{ id[NR] = $1; up[$1] = $2; grp[$1] = $3; tm[$1] = $4; c = $5
  for (i = 6; i <= NF; i++) c = c " " $i
  sub(/.*\//, "", c); cm[$1] = c }
END {
  if (NR == 0) exit
  for (i = 1; i <= NR; i++) if (grp[id[i]] == root) mem[id[i]] = 1
  do { more = 0
    for (i = 1; i <= NR; i++) { p = id[i]; if (!(p in mem) && (up[p] in mem)) { mem[p] = 1; more = 1 } }
  } while (more)
  for (i = 1; i <= NR; i++) { p = id[i]; if (p in mem) kids[up[p]] = 1 }
  n = 0; total = 0; waiting = 0
  for (i = 1; i <= NR; i++) { p = id[i]; if (!(p in mem)) continue
    v[++n] = p + 0; total += cs(tm[p])
    if ((cm[p] == "lockf" || cm[p] == "flock") && !(p in kids)) waiting = 1 }
  for (i = 2; i <= n; i++) { x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x }
  out = total; for (i = 1; i <= n; i++) out = out "," v[i]
  print waiting, out
}'

# One sample of group <pgid>; the C locale keeps "0:00.75" a decimal number.
members() { # <pgid>
  LC_ALL=C ps -A -o pid=,ppid=,pgid=,time=,comm= 2>/dev/null 3>&- |
    LC_ALL=C awk -v root="$1" "$members_awk" 2>/dev/null 3>&-
}

# Restores the caller's BASH_ENV/ENV ("" unset, "=value" set).
restore_env() { # <BASH_ENV spec> <ENV spec>
  case $1 in =*) export BASH_ENV="${1#=}" ;; *) unset BASH_ENV ;; esac
  case $2 in =*) export ENV="${2#=}" ;; *) unset ENV ;; esac
}

supervise() { # STATE NAME DIR DEPTH MAX_HOLD DEADLINE GRACE SAMPLE STEP OUTER_AT OUTER_WAIT ERREXIT BASH_ENV ENV -- COMMAND...
  local state=$1 name=$2 dir=$3 depth=$4 max_hold=$5 deadline=$6 grace=$7 sample=$8 step=$9
  local outer_at=${10} outer_wait=${11} errexit=${12} bash_env_spec=${13} env_spec=${14}
  shift 15
  local kill_wait kill_at=0 margin usr1_rc
  local holder=$dir/$name.holder meta=$dir/$name.meta
  local pending='' cmd='' timer='' ended='' since base now rc
  local last_activity waiting=0 liveness=uncheckable signature='' sampled ticking=0 can_tick=0
  # Recorded only: acted on once COMMAND's pid is known (closes the spawn gap).
  trap 'pending=${pending:-TERM}' TERM; trap 'pending=${pending:-INT}' INT
  trap 'pending=${pending:-HUP}' HUP; trap ':' USR1
  # Writing the pid file is the proof of acquisition; the cancel check closes
  # the gap between acquiring and a signal the wrapper already handled.
  printf '%s\n' "$$" >"$state/pid"
  [ ! -e "$state/cancel" ] || exit 143
  [ -z "$pending" ] || exit "$(signal_status "$pending")"
  since=$(date +%s 2>/dev/null); [[ $since =~ ^[0-9]+$ ]] || since=0
  base=$SECONDS
  if [ "$max_hold" -gt 0 ] && { [ "$deadline" = 0 ] || [ $((since + max_hold)) -lt "$deadline" ]; }; then
    deadline=$((since + max_hold))
  fi
  export ORCHESTRATION_LOCKS_HELD="${ORCHESTRATION_LOCKS_HELD:+$ORCHESTRATION_LOCKS_HELD:}$name"
  if [ "$deadline" -gt 0 ]; then export WITH_LOCK_DEADLINE=$deadline; fi
  # KILL comes strictly before the enclosing holder's (it may release only
  # after its group, which holds this whole lock chain, has exited).
  kill_wait=$((grace + (MAXDEPTH - depth) * step))
  margin=$step; [ "$margin" -ge 2 ] || margin=2
  if [ -n "$outer_wait" ] && [ "$kill_wait" -gt $((outer_wait - margin)) ]; then
    kill_wait=$((outer_wait - margin)); [ "$kill_wait" -ge 0 ] || kill_wait=0
  fi
  export WITH_LOCK_OUTER_KILL_WAIT=$kill_wait
  if [ "$deadline" -gt 0 ]; then
    kill_at=$((deadline + kill_wait))
    if [ "$outer_at" -gt 0 ] && [ "$kill_at" -gt $((outer_at - margin)) ]; then
      kill_at=$((outer_at - margin)); [ "$kill_at" -ge "$deadline" ] || kill_at=$deadline
    fi
    export WITH_LOCK_OUTER_KILL_AT=$kill_at
  fi
  usr1_rc=$((128 + $(kill -l USR1)))
  restore_env "$bash_env_spec" "$env_spec"
  # Job control for the spawn only: COMMAND gets its own process group and
  # default INT handling (a background child without it starts INT-ignored).
  # errexit is on just for the spawn, so an exported SHELLOPTS carries it.
  set -m
  [ "$errexit" = 0 ] || set -e
  "$@" &
  cmd=$!
  set +e +m
  # From here the shell's own stderr (job notices, failed probes) is silent;
  # messages go to fd 3. COMMAND already has the real stderr.
  exec 3>&2 2>/dev/null
  printf "pid %s, since %s, cwd %s, command %s\n" "$cmd" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PWD" "$*" |
    tr "\n" " " >"$holder" || true
  last_activity=$since
  [ "$sample" = 0 ] || sample_group
  write_meta
  # Ticks only when there is something to check; the kill path always may.
  command -v sleep >/dev/null && can_tick=1
  if [ "$can_tick" = 1 ] && { [ "$deadline" -gt 0 ] || [ "$sample" -gt 0 ]; }; then ticking=1; fi
  sampled=$SECONDS
  while :; do
    [ -z "$pending" ] || end_by_signal
    now=$((since + SECONDS - base))
    if [ "$deadline" -gt 0 ] && [ "$now" -ge "$deadline" ]; then end_by_deadline; fi
    if [ "$sample" -gt 0 ] && [ $((SECONDS - sampled)) -ge "$sample" ]; then
      sampled=$SECONDS; sample_group; write_meta
    fi
    [ "$ticking" = 0 ] || timer_start
    rc=0; wait "$cmd" || rc=$?
    timer_stop
    # Only a trapped signal interrupts wait; any other status is COMMAND's.
    case $rc in
      129 | 130 | 143 | "$usr1_rc")
        ! kill -0 "$cmd" || continue
        rc=0; wait "$cmd" || rc=$?; break ;;
      *) break ;;
    esac
  done
  # A signal that arrived as COMMAND ended still empties its group first.
  [ -z "$pending" ] || end_by_signal
  # A normal exit: the group is not polled, so a daemon COMMAND left behind
  # does not keep the lock.
  ended=$((since + SECONDS - base)); write_meta
  exit "$rc"
}

signal_status() { case $1 in INT) echo 130 ;; HUP) echo 129 ;; *) echo 143 ;; esac; }

# A 1-second tick: USR1 interrupts `wait`. The timer runs in its own process
# group with no caller descriptors, and timer_stop kills and reaps it.
timer_start() {
  set -m
  (sleep 1; kill -USR1 "$$") </dev/null >/dev/null 2>&1 3>&- &
  timer=$!
  set +m
}
timer_stop() {
  [ -n "$timer" ] || return 0
  kill -- -"$timer"; wait "$timer" || :; timer=''
}

sample_group() {
  local out
  local shape='^[01] [0-9]'
  out=$(members "$cmd")
  if [[ ! $out =~ $shape ]]; then liveness=uncheckable; return 0; fi
  liveness=ok; waiting=${out%% *}
  if [ "${out#* }" != "$signature" ]; then
    signature=${out#* }; last_activity=$((since + SECONDS - base))
  fi
}

# Replaced atomically; silently absent where mv is not available.
write_meta() {
  local tmp=$meta.$$
  if {
    printf 'pid=%s\npgid=%s\nsince_epoch=%s\ndeadline=%s\nlast_activity_epoch=%s\nwaiting_on_lock=%s\nliveness=%s\n' \
      "$cmd" "$cmd" "$since" "$deadline" "$last_activity" "$waiting" "$liveness"
    [ -z "$ended" ] || printf 'ended_epoch=%s\n' "$ended"
  } >"$tmp"; then
    mv -f "$tmp" "$meta" || rm -f "$tmp"
  fi
}

# 0 once COMMAND and every process in its group are gone; 1 after <seconds>.
wait_gone() { # <seconds>
  local start=$SECONDS
  while :; do
    if kill -0 "$cmd"; then
      [ "$can_tick" = 0 ] || timer_start
      wait "$cmd" || :
      timer_stop
    else
      wait "$cmd" || :
      kill -0 -- -"$cmd" || return 0
      if [ "$can_tick" = 1 ]; then sleep 0.2 >/dev/null 3>&-; fi
    fi
    [ $((SECONDS - start)) -lt "$1" ] || return 1
  done
}

# TERM (or the received signal) to the whole group, KILL after <seconds>,
# and never return while any process of the group is alive.
stop_group() { # <signal> <seconds before KILL>
  local warned=0
  kill -"$1" -- -"$cmd"
  wait_gone "$2" && return 0
  kill -KILL -- -"$cmd"
  until wait_gone 10; do
    [ "$warned" = 1 ] ||
      printf 'with-lock.sh: %s: process group %s survives KILL; the lock stays held until it exits\n' "$name" "$cmd" >&3
    warned=1
    kill -KILL -- -"$cmd"
  done
}

end_by_signal() {
  stop_group "$pending" "$kill_wait"
  ended=$((since + SECONDS - base)); write_meta
  exit "$(signal_status "$pending")"
}

end_by_deadline() {
  local budget=$((deadline - since))
  [ "$budget" -ge 0 ] || budget=0
  local left=$((kill_at - since - SECONDS + base))
  [ "$left" -ge 0 ] || left=0
  stop_group TERM "$left"
  printf 'with-lock.sh: %s exceeded max-hold (%ss) — terminated pid %s\n' "$name" "$budget" "$cmd" >&3
  ended=$((since + SECONDS - base)); write_meta
  exit 124
}

if [ "${1-}" = --supervise ]; then
  shift
  supervise "$@"
fi
if [ "${1-}" = --members ]; then
  [ $# -eq 2 ] && [[ $2 =~ ^[1-9][0-9]*$ ]] || { printf 'with-lock.sh: usage: with-lock.sh --members PGID\n' >&2; exit 2; }
  members "$2"; exit 0
fi

# --- wrapper -------------------------------------------------------------------
status_mode=0
max_hold=${WITH_LOCK_MAX_HOLD-}
case ${1-} in
  --status)
    [ $# -eq 2 ] || usage 'usage: with-lock.sh --status NAME'
    status_mode=1; name=$2 ;;
  --max-hold)
    [ $# -ge 2 ] || usage 'usage: with-lock.sh [--max-hold SECONDS] NAME -- COMMAND [ARG...]'
    max_hold=$2; shift 2 ;;
esac
if [ "$status_mode" = 0 ]; then
  [ $# -ge 3 ] && [ "$2" = -- ] || usage 'usage: with-lock.sh [--max-hold SECONDS] NAME -- COMMAND [ARG...]'
  name=$1; shift 2
fi
[[ $name =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || usage "bad lock name: $name"
wait_s=${WITH_LOCK_WAIT-}
[[ -z $wait_s || $wait_s =~ ^[0-9]+$ ]] || usage "WITH_LOCK_WAIT must be whole seconds: $wait_s"
max_hold=$(whole 'max-hold' "${max_hold:-0}") || exit 2
grace=$(whole WITH_LOCK_KILL_GRACE "${WITH_LOCK_KILL_GRACE:-5}") || exit 2
sample=$(whole WITH_LOCK_SAMPLE_INTERVAL "${WITH_LOCK_SAMPLE_INTERVAL:-30}") || exit 2
stale=$(whole WITH_LOCK_STALE_IDLE "${WITH_LOCK_STALE_IDLE:-300}") || exit 2
step=$(whole WITH_LOCK_DEPTH_STEP "${WITH_LOCK_DEPTH_STEP:-2}") || exit 2
inherited=$(whole WITH_LOCK_DEADLINE "${WITH_LOCK_DEADLINE:-0}") || exit 2
outer_at=$(whole WITH_LOCK_OUTER_KILL_AT "${WITH_LOCK_OUTER_KILL_AT:-0}") || exit 2
outer_wait=''
if [ -n "${WITH_LOCK_OUTER_KILL_WAIT-}" ]; then
  outer_wait=$(whole WITH_LOCK_OUTER_KILL_WAIT "$WITH_LOCK_OUTER_KILL_WAIT") || exit 2
fi

if [ "$status_mode" = 0 ]; then
  case ":${ORCHESTRATION_LOCKS_HELD-}:" in *":$name:"*) exec "$@" ;; esac
fi

if command -v flock >/dev/null 2>&1; then tool=flock
elif command -v lockf >/dev/null 2>&1; then tool=lockf
else usage 'needs flock or lockf on PATH'; fi

dir=${ORCHESTRATION_LOCK_DIR:-/tmp/orchestration-locks-$(id -u)}
if [ "$status_mode" = 1 ] && [ ! -e "$dir" ] && [ ! -L "$dir" ]; then echo free; exit 0; fi
[ -d "$dir" ] || mkdir -m 700 "$dir" 2>/dev/null
[ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] ||
  { printf 'with-lock.sh: lock directory unusable: %s\n' "$dir" >&2; exit 1; }
lock=$dir/$name.lock; holder=$dir/$name.holder; meta=$dir/$name.meta

held_by() {
  local line=unknown
  if [ -s "$holder" ]; then line=$(head -n 1 "$holder"); line=${line% }; fi
  printf '%s' "$line"
}
# Reads NAME.meta into m_*; 1 when absent, malformed, or not the holder's.
read_meta() {
  local k v hp
  m_pid='' m_pgid='' m_since='' m_last='' m_wait=0 m_live='' m_ended=''
  [ -r "$meta" ] || return 1
  while IFS='=' read -r k v; do
    case $k in
      pid) m_pid=$v ;; pgid) m_pgid=$v ;; since_epoch) m_since=$v ;;
      last_activity_epoch) m_last=$v ;; waiting_on_lock) m_wait=$v ;;
      liveness) m_live=$v ;; ended_epoch) m_ended=$v ;;
    esac
  done <"$meta"
  [[ $m_pid =~ ^[0-9]+$ && $m_pgid =~ ^[0-9]+$ && $m_since =~ ^[0-9]+$ && $m_last =~ ^[0-9]+$ ]] || return 1
  hp=$(held_by); hp=${hp#pid }; hp=${hp%%,*}
  [ "$hp" = "$m_pid" ]
}
span() { # <seconds> as 42s, 12m, 2h05m
  if [ "$1" -lt 60 ]; then printf '%ss' "$1"
  elif [ "$1" -lt 3600 ]; then printf '%sm' $(($1 / 60))
  else printf '%sh%02dm' $(($1 / 3600)) $(($1 % 3600 / 60)); fi
}
# The holder's age and liveness from NAME.meta, or nothing.
meta_note() { # waiter|status
  local now age idle
  read_meta && [ -z "$m_ended" ] || return 0
  now=$(date +%s 2>/dev/null); [[ $now =~ ^[0-9]+$ ]] || return 0
  age=$((now - m_since)); idle=$((now - m_last))
  [ "$age" -ge 0 ] || age=0; [ "$idle" -ge 0 ] || idle=0
  if [ "$1" = status ]; then
    if [ "$m_live" != ok ]; then printf ' [age=%ss liveness=uncheckable]' "$age"; return 0; fi
    printf ' [age=%ss idle=%ss]' "$age" "$idle"
    if [ "$m_wait" = 1 ]; then printf ' [waiting on another lock]'
    elif [ "$idle" -ge "$stale" ]; then printf ' [stale]'; fi
    return 0
  fi
  if [ "$m_wait" = 1 ] && [ "$m_live" = ok ]; then printf ' [held %s, waiting on another lock]' "$(span "$age")"
  elif [ "$m_live" != ok ]; then printf ' [held %s, liveness unchecked]' "$(span "$age")"
  elif [ "$idle" -ge "$stale" ]; then printf ' [held %s, idle %s — STALE]' "$(span "$age")" "$(span "$idle")"
  else printf ' [held %s, idle %s]' "$(span "$age")" "$(span "$idle")"; fi
}
# Informational probe: taking and dropping a free lock changes nothing.
probe() {
  if [ "$tool" = flock ]; then flock -n "$lock" true 2>/dev/null; else lockf -k -s -t 0 "$lock" true 2>/dev/null; fi
}

if [ "$status_mode" = 1 ]; then
  if probe; then
    if read_meta && [ -z "$m_ended" ] && [ "$m_pgid" -gt 1 ] && kill -0 -- -"$m_pgid" 2>/dev/null; then
      printf 'free (WARNING: last holder group %s still alive — %s)\n' "$m_pgid" "$(held_by)"
    else echo free; fi
    exit 0
  fi
  printf 'held: %s%s\n' "$(held_by)" "$(meta_note status)"
  exit 1
fi

held=${ORCHESTRATION_LOCKS_HELD-}
depth=0
while [ -n "$held" ]; do depth=$((depth + 1)); case $held in *:*) held=${held#*:} ;; *) held='' ;; esac; done
if [ "$max_hold" -gt 0 ] || [ "$inherited" -gt 0 ]; then
  [ "$depth" -lt "$MAXDEPTH" ] || usage "max-hold needs fewer than $MAXDEPTH locks already held"
  [ "$step" -ge 1 ] || usage 'max-hold needs WITH_LOCK_DEPTH_STEP of at least 1'
  command -v sleep >/dev/null 2>&1 && [[ $(date +%s 2>/dev/null) =~ ^[0-9]+$ ]] ||
    usage 'max-hold needs sleep and date +%s on PATH'
fi

state=$(mktemp -d "${TMPDIR:-/tmp}/with-lock.XXXXXX") || exit 1
trap 'rm -rf "$state"' EXIT

probe || printf 'with-lock.sh: waiting for %s — held by: %s%s\n' "$name" "$(held_by)" "$(meta_note waiter)" >&2

case $0 in */*) self_dir=${0%/*} ;; *) self_dir=. ;; esac
self=$(CDPATH='' cd -P -- "$self_dir" >/dev/null && pwd -P)/${0##*/}
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
# The supervisor starts without the caller's startup files (bash reads no
# empty BASH_ENV); COMMAND gets them back.
bash_env_spec=${BASH_ENV+=$BASH_ENV}; env_spec=${ENV+=$ENV}
BASH_ENV='' ENV='' "${locker[@]}" "$BASH" --noprofile --norc "$self" --supervise "$state" "$name" "$dir" "$depth" \
  "$max_hold" "$inherited" "$grace" "$sample" "$step" "$outer_at" "$outer_wait" "$had_errexit" \
  "$bash_env_spec" "$env_spec" -- "$@" &
child=$!
set +m
trap 'forward TERM 15' TERM; trap 'forward TERM 2' INT; trap 'forward HUP 1' HUP
# A trapped signal interrupts wait; keep waiting until the locker is gone.
while :; do
  rc=0; wait "$child" || rc=$?
  kill -0 "$child" 2>/dev/null || break
done
[ "$signal" = 0 ] || exit $((128 + signal))
if [ ! -e "$state/pid" ]; then
  printf 'with-lock.sh: %s not acquired within %ss — held by: %s%s\n' "$name" "${wait_s:-?}" "$(held_by)" "$(meta_note waiter)" >&2
  exit 75
fi
exit "$rc"

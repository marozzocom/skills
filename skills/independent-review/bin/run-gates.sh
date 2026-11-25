#!/usr/bin/env bash
# run-gates.sh <worktree> "<name>:<command>" [...]
# Each gate runs in a fresh strict bash (-e -u -o pipefail). A command that
# tolerates a failure must say so explicitly, e.g. cmd || true.
# The caller's exported environment (PATH, tool homes, version managers) is
# inherited unchanged: its shell has already run startup. BASH_ENV and ENV
# are unset for gates by default, preventing startup from silently changing
# PATH. RUN_GATES_BASH_ENV=<readable regular file> opts into BASH_ENV.
# Validate every spec before running any gate: missing colon, empty name or
# command, duplicate names, or RUN_GATES_BASH_ENV set but empty are usage errors.
# Output: one PASS <name> in <N>s or FAIL <name> (exit N) in <N>s — last 20
# lines: per gate (whole seconds), followed by the failed gate's indented
# tail. Every valid gate runs. Then time: <N>s, the sum over the gates.
# Full logs are NN-<sanitized>.log (a zero-padded index prevents collisions)
# in a private mktemp directory, never auto-deleted. The final two lines are
# bash_env: <none|file> and logs: <dir>, with logs always last.
# RUN_GATES_LOCK=<name>[,<name>...] holds those with-lock.sh locks, taken in
# the order given, for the whole run, so heavy runs queue across sessions.
# The first output line is then lock: <names> waited <N>s; the wait is never
# counted in a gate's time. WITH_LOCK_WAIT=<seconds> bounds each wait; when a
# lock is not acquired, or with-lock.sh cannot lock at all, no gate runs:
# FAIL lock <names> (not acquired) or (with-lock.sh exit N), bash_env:,
# logs: none, exit 3.
# RUN_GATES_RECORD=<file> appends one tab-separated line per gate and per
# lock wait: UTC time, worktree, gate|lock, name, exit code, seconds (tabs
# and newlines in names become spaces). A failed append prints record:
# failed <file> before time: and changes nothing else.
# Gates never inherit RUN_GATES_LOCK or RUN_GATES_RECORD: a gate that runs
# this script again takes no lock and writes no record of its own.
# Max hold: with RUN_GATES_LOCK the locks are held at most WITH_LOCK_MAX_HOLD
# seconds (default 3600 here; 0 means no limit), an absolute deadline that
# with-lock.sh exports as WITH_LOCK_DEADLINE, which gates keep, so a lock a
# gate takes inherits it. At the deadline with-lock.sh terminates the whole
# gate run, running gates included, before the lock is released; this script
# then prints FAIL lock <names> (max-hold), records a lock row with exit 124,
# and still ends with bash_env: and logs: <dir>. A gate run ended by a signal
# prints FAIL lock <names> (terminated, exit N) the same way.
# Exit: 0 all gates pass, 1 any gate failed, 2 usage error, 3 lock not
# acquired, 124 the lock's max hold was reached (stderr then carries
# with-lock.sh's "exceeded max-hold" line; a gate that itself exits 124 is
# only FAIL <gate> (exit 124) and exit 1), 128+N the locked run was ended by
# signal N.
# Signals: with RUN_GATES_LOCK, TERM and HUP to this script (alone or with
# its process group) are forwarded to with-lock.sh, INT as TERM; it ends the
# gate run and frees the locks, and this script then still prints FAIL lock
# <names> (terminated, exit N), or (not acquired) while it waited, records
# the lock row, ends with bash_env: and logs:, and exits 128+N.
# The caller's errexit (SHELLOPTS, BASH_ENV) never applies to this script;
# gates run under their own -e regardless.
set -u
set +e

usage() { printf 'run-gates.sh: %s\n' "$*" >&2; exit 2; }
[ $# -ge 2 ] || usage 'usage: run-gates.sh <worktree> "<name>:<command>" [...]'
worktree=$1; shift
[ -d "$worktree" ] || usage "worktree not found: $worktree"
names=()
for spec in "$@"; do
  name=${spec%%:*}
  cmd=${spec#*:}
  [[ $spec == *:* && -n $name && -n $cmd ]] || usage "bad gate spec: $spec"
  for seen in ${names[@]+"${names[@]}"}; do
    [[ $name != "$seen" ]] || usage "duplicate gate name: $name"
  done
  names+=("$name")
done
bash_env=${RUN_GATES_BASH_ENV-}
if [[ ${RUN_GATES_BASH_ENV+x} ]]; then
  [[ -f $bash_env && -r $bash_env ]] || usage "RUN_GATES_BASH_ENV is not a readable regular file: $bash_env"
  # Resolve before changing to the worktree, including relative opt-in paths.
  # Logical paths (no -P) here and in the record: output names what was given.
  bash_env=$(CDPATH='' cd -- "$(dirname "$bash_env")" >/dev/null && pwd)/$(basename "$bash_env")
fi
record=${RUN_GATES_RECORD-}
[[ -z ${RUN_GATES_RECORD+x} || -n $record ]] || usage 'RUN_GATES_RECORD is set but empty'
record_failed=0
flat() { printf '%s' "$1" | tr '\t\n' '  '; }
note() { # <gate|lock> <name> <exit code> <seconds>
  [[ -n $record ]] || return 0
  { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(flat "$(CDPATH='' cd -- "$worktree" >/dev/null && pwd)")" \
    "$1" "$(flat "$2")" "$3" "$4" >>"$record"; } 2>/dev/null || record_failed=1
}
locks=${RUN_GATES_LOCK-}
if [[ -n $locks ]]; then
  [[ $locks =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*(,[A-Za-z0-9._][A-Za-z0-9._-]*)*$ ]] || usage "bad RUN_GATES_LOCK: $locks"
  export WITH_LOCK_MAX_HOLD=${WITH_LOCK_MAX_HOLD:-3600}
  [[ $WITH_LOCK_MAX_HOLD =~ ^[0-9]{1,12}$ ]] || usage "WITH_LOCK_MAX_HOLD must be whole seconds: $WITH_LOCK_MAX_HOLD"
  # Run this script again as a child under the locks: the parent keeps the
  # output contract when a lock is never acquired.
  here=$(CDPATH='' cd -P -- "$(dirname "$0")" >/dev/null && pwd -P)
  relaunch=("$BASH" "$here/$(basename "$0")" "$worktree" "$@")
  IFS=, read -r -a lock_names <<<"$locks"
  for ((i = ${#lock_names[@]} - 1; i >= 0; i--)); do
    relaunch=("$here/with-lock.sh" "${lock_names[i]}" -- "${relaunch[@]}")
  done
  # The child removes this file once it runs under the locks: whether a gate
  # run started is read from it, never from an exit code.
  pending=$(mktemp "${TMPDIR:-/tmp}/run-gates-lock.XXXXXX") || exit 1
  # The log directory is made here, so a run that with-lock.sh ends (max hold,
  # signal) still names it on the logs: line.
  logdir=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || { rm -f "$pending"; exit 1; }
  waiting=$SECONDS
  # A signal to this script (or its group) is forwarded to with-lock.sh, which
  # ends the gate run and frees the locks; the last lines are printed after.
  signal=0 relaunched=''
  # shellcheck disable=SC2329 # Invoked by the traps below.
  forward() { # <signal to send> <number received>
    signal=$2
    [ -z "$relaunched" ] || kill -"$1" "$relaunched" 2>/dev/null
  }
  trap 'forward TERM 15' TERM; trap 'forward TERM 2' INT; trap 'forward HUP 1' HUP
  # Job control for the spawn only: its own process group, default INT.
  set -m
  RUN_GATES_LOCK='' RUN_GATES_PENDING=$pending RUN_GATES_LOGDIR=$logdir RUN_GATES_LOCKED="$(date +%s) $locks" "${relaunch[@]}" &
  relaunched=$!
  set +m
  # A signal received before the pid was known.
  case $signal in 0) ;; 1) kill -HUP "$relaunched" 2>/dev/null ;; *) kill -TERM "$relaunched" 2>/dev/null ;; esac
  while :; do
    rc=0; wait "$relaunched" || rc=$?
    kill -0 "$relaunched" 2>/dev/null || break
  done
  status=$rc; [ "$signal" = 0 ] || status=$((128 + signal))
  if [ ! -e "$pending" ]; then
    # The gate run started; the child exits 0 or 1 after its own last lines.
    case $rc in 0 | 1) exit "$rc" ;; esac
    note lock "$locks" "$rc" $((SECONDS - waiting))
    if [ "$rc" -eq 124 ] && [ "$signal" = 0 ]; then printf 'FAIL lock %s (max-hold)\n' "$locks"
    else printf 'FAIL lock %s (terminated, exit %s)\n' "$locks" "$rc"; fi
    [ "$record_failed" = 0 ] || printf 'record: failed %s\n' "$record"
    printf 'bash_env: %s\n' "${bash_env:-none}"
    printf 'logs: %s\n' "$logdir"
    exit "$status"
  fi
  rm -f "$pending"
  rmdir "$logdir" 2>/dev/null
  note lock "$locks" "$rc" $((SECONDS - waiting))
  if [ "$rc" -eq 75 ] || [ "$signal" != 0 ]; then printf 'FAIL lock %s (not acquired)\n' "$locks"
  else printf 'FAIL lock %s (with-lock.sh exit %s)\n' "$locks" "$rc"; fi
  [ "$record_failed" = 0 ] || printf 'record: failed %s\n' "$record"
  printf 'bash_env: %s\n' "${bash_env:-none}"
  printf 'logs: none\n'
  [ "$signal" = 0 ] || exit "$status"
  exit 3
fi
if [[ -n ${RUN_GATES_LOCKED-} ]]; then
  [[ -z ${RUN_GATES_PENDING-} ]] || rm -f "$RUN_GATES_PENDING"
  waited=$(($(date +%s) - ${RUN_GATES_LOCKED%% *}))
  printf 'lock: %s waited %ss\n' "${RUN_GATES_LOCKED#* }" "$waited"
  note lock "${RUN_GATES_LOCKED#* }" 0 "$waited"
fi
if [[ -n ${RUN_GATES_LOCKED-} && -n ${RUN_GATES_LOGDIR-} && -d ${RUN_GATES_LOGDIR-} ]]; then logdir=$RUN_GATES_LOGDIR
else logdir=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || exit 1; fi
fail=0; index=0; total=0
for spec in "$@"; do
  name=${spec%%:*}; cmd=${spec#*:}
  index=$((index + 1))
  printf -v log '%s/%02d-%s.log' "$logdir" "$index" "$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
  # The child interpreter implements errexit; the parent's conditional does
  # not put the command text into an errexit-suppressed eval context.
  started=$SECONDS
  if (
    # WITH_LOCK_DEADLINE stays: a lock taken inside a gate keeps the deadline.
    unset BASH_ENV ENV RUN_GATES_LOCK RUN_GATES_LOCKED RUN_GATES_PENDING RUN_GATES_RECORD RUN_GATES_LOGDIR
    if [[ -n $bash_env ]]; then export BASH_ENV=$bash_env; fi
    cd "$worktree" || exit 1
    exec "$BASH" --noprofile --norc -e -u -o pipefail -c "$cmd" </dev/null
  ) >"$log" 2>&1; then
    took=$((SECONDS - started))
    printf 'PASS %s in %ss\n' "$name" "$took"
    note gate "$name" 0 "$took"
  else
    rc=$?; fail=1; took=$((SECONDS - started))
    printf 'FAIL %s (exit %s) in %ss — last 20 lines:\n' "$name" "$rc" "$took"
    tail -n 20 "$log" | sed 's/^/  /'
    note gate "$name" "$rc" "$took"
  fi
  total=$((total + took))
done
[ "$record_failed" = 0 ] || printf 'record: failed %s\n' "$record"
printf 'time: %ss\n' "$total"
printf 'bash_env: %s\n' "${bash_env:-none}"
printf 'logs: %s\n' "$logdir"
exit "$fail"

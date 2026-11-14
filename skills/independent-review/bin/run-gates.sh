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
# Exit: 0 all gates pass, 1 any gate failed, 2 usage error, 3 lock not
# acquired.
set -u

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
  bash_env=$(cd "$(dirname "$bash_env")" && pwd)/$(basename "$bash_env")
fi
record=${RUN_GATES_RECORD-}
[[ -z ${RUN_GATES_RECORD+x} || -n $record ]] || usage 'RUN_GATES_RECORD is set but empty'
record_failed=0
flat() { printf '%s' "$1" | tr '\t\n' '  '; }
note() { # <gate|lock> <name> <exit code> <seconds>
  [[ -n $record ]] || return 0
  { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(flat "$(cd "$worktree" && pwd)")" \
    "$1" "$(flat "$2")" "$3" "$4" >>"$record"; } 2>/dev/null || record_failed=1
}
locks=${RUN_GATES_LOCK-}
if [[ -n $locks ]]; then
  [[ $locks =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || usage "bad RUN_GATES_LOCK: $locks"
  # Run this script again as a child under the locks: the parent keeps the
  # output contract when a lock is never acquired.
  here=$(cd "$(dirname "$0")" && pwd)
  relaunch=("$BASH" "$here/$(basename "$0")" "$worktree" "$@")
  IFS=, read -r -a lock_names <<<"$locks"
  for ((i = ${#lock_names[@]} - 1; i >= 0; i--)); do
    relaunch=("$here/with-lock.sh" "${lock_names[i]}" -- "${relaunch[@]}")
  done
  # The child removes this file once it runs under the locks: whether a gate
  # run started is read from it, never from an exit code.
  pending=$(mktemp "${TMPDIR:-/tmp}/run-gates-lock.XXXXXX") || exit 1
  waiting=$SECONDS
  RUN_GATES_LOCK='' RUN_GATES_PENDING=$pending RUN_GATES_LOCKED="$(date +%s) $locks" "${relaunch[@]}"; rc=$?
  [ -e "$pending" ] || exit "$rc"
  rm -f "$pending"
  note lock "$locks" "$rc" $((SECONDS - waiting))
  if [ "$rc" -eq 75 ]; then printf 'FAIL lock %s (not acquired)\n' "$locks"
  else printf 'FAIL lock %s (with-lock.sh exit %s)\n' "$locks" "$rc"; fi
  [ "$record_failed" = 0 ] || printf 'record: failed %s\n' "$record"
  printf 'bash_env: %s\n' "${bash_env:-none}"
  printf 'logs: none\n'
  exit 3
fi
if [[ -n ${RUN_GATES_LOCKED-} ]]; then
  [[ -z ${RUN_GATES_PENDING-} ]] || rm -f "$RUN_GATES_PENDING"
  waited=$(($(date +%s) - ${RUN_GATES_LOCKED%% *}))
  printf 'lock: %s waited %ss\n' "${RUN_GATES_LOCKED#* }" "$waited"
  note lock "${RUN_GATES_LOCKED#* }" 0 "$waited"
fi
logdir=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || exit 1
fail=0; index=0; total=0
for spec in "$@"; do
  name=${spec%%:*}; cmd=${spec#*:}
  index=$((index + 1))
  printf -v log '%s/%02d-%s.log' "$logdir" "$index" "$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
  # The child interpreter implements errexit; the parent's conditional does
  # not put the command text into an errexit-suppressed eval context.
  started=$SECONDS
  if (
    unset BASH_ENV ENV RUN_GATES_LOCK RUN_GATES_LOCKED RUN_GATES_PENDING RUN_GATES_RECORD
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

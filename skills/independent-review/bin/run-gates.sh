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
# Output: one PASS <name> or FAIL <name> (exit N) — last 20 lines: per gate,
# followed by the failed gate's indented tail. Every valid gate runs.
# Full logs are NN-<sanitized>.log (a zero-padded index prevents collisions)
# in a private mktemp directory, never auto-deleted. The final two lines are
# bash_env: <none|file> and logs: <dir>, with logs always last.
# Exit: 0 all gates pass, 1 any gate failed, 2 usage error.
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
logdir=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || exit 1
fail=0; index=0
for spec in "$@"; do
  name=${spec%%:*}; cmd=${spec#*:}
  index=$((index + 1))
  printf -v log '%s/%02d-%s.log' "$logdir" "$index" "$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
  # The child interpreter implements errexit; the parent's conditional does
  # not put the command text into an errexit-suppressed eval context.
  if (
    unset BASH_ENV ENV
    if [[ -n $bash_env ]]; then export BASH_ENV=$bash_env; fi
    cd "$worktree" || exit 1
    exec "$BASH" --noprofile --norc -e -u -o pipefail -c "$cmd" </dev/null
  ) >"$log" 2>&1; then
    printf 'PASS %s\n' "$name"
  else
    rc=$?; fail=1
    printf 'FAIL %s (exit %s) — last 20 lines:\n' "$name" "$rc"
    tail -n 20 "$log" | sed 's/^/  /'
  fi
done
printf 'bash_env: %s\n' "${bash_env:-none}"
printf 'logs: %s\n' "$logdir"
exit "$fail"

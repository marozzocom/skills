#!/usr/bin/env bash
# run-gates.sh <worktree> "<name>:<command>" [...]
#
# Acceptance gate runner: executes each gate command inside <worktree> and
# prints one line per gate — `PASS <name>`, or `FAIL <name> (exit N)` plus
# the last 20 lines of that gate's output. Full logs stay on disk (path
# printed last, never auto-deleted) so a failure can be diagnosed without a
# re-run. The verdict is the exit code; the orchestrator needs verdict
# lines, not scrollback — the verbatim output already lives in the
# implementer's report file.
# Exit: 0 all gates pass, 1 any gate failed, 2 usage error.
set -u

worktree=${1:?usage: run-gates.sh <worktree> "<name>:<command>" [...]}
shift
[ $# -ge 1 ] || { echo 'usage: run-gates.sh <worktree> "<name>:<command>" [...]' >&2; exit 2; }
[ -d "$worktree" ] || { echo "ERROR: worktree not found: $worktree" >&2; exit 2; }

logdir=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX")
fail=0

for spec in "$@"; do
  name=${spec%%:*}
  cmd=${spec#*:}
  if [ -z "$name" ] || [ "$name" = "$spec" ] || [ -z "$cmd" ]; then
    echo "ERROR: bad gate spec (want \"<name>:<command>\"): $spec" >&2
    fail=1
    continue
  fi
  log="$logdir/$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_').log"
  if (cd "$worktree" && eval "$cmd") >"$log" 2>&1; then
    echo "PASS $name"
  else
    rc=$?
    fail=1
    echo "FAIL $name (exit $rc) — last 20 lines:"
    tail -n 20 "$log" | sed 's/^/  /'
  fi
done

echo "logs: $logdir"
exit "$fail"

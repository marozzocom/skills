#!/usr/bin/env bash
# Rotate a Herdr agent onto a new worktree in one step: quit whatever agent
# occupies the pane, cd the pane's shell, start a fresh session.
#
# Usage: rotate-implementer.sh <agent-name> <pane-id> <worktree-dir> <kind> \
#          [-- <native agent args>...]
# App: resolves <agent-name>, accepts and ignores <pane-id>, prints the new address.
#   rotate-implementer.sh impl w1:p3 ~/worktrees/task-x <implementer-kind> \
#     -- <that CLI's model pin and effort args, from environment.md>
#   rotate-implementer.sh rev w1:p4 ~/worktrees/task-x <reviewer-kind> \
#     -- <that CLI's model pin, from environment.md>
#
# Args after `--` are forwarded verbatim to `herdr agent start`. Pass the model
# pin here: references/environment.md requires an explicit pin because ids
# drift, and a rotation that omits it silently downgrades the agent to whatever
# its config file defaults to. Omitting them warns on stderr rather than
# failing. ROTATE_AGENT_ARGS supplies a default when none are given.
#
# <kind> is required and is any kind `herdr agent start --kind` accepts
# (`herdr agent start --help` lists them). There is no default: a rotation
# that silently picked a vendor would start the wrong agent in the pane.
#
# The pane must exist (create it first: herdr pane split --current
# --direction right --cwd <dir> --no-focus). Prints the started agent JSON.
#
# Every step is state-verified: a failed or slow quit aborts instead of
# typing shell commands into a live agent composer, and the cd is confirmed
# against the pane's foreground_cwd before a new session starts. Safe to run
# concurrently for different (name, pane) pairs — no shared state.
set -euo pipefail

usage='usage: rotate-implementer.sh <agent-name> <pane-id> <worktree-dir> <kind> [-- <native agent args>...] (app ignores pane-id)'
name=${1:?$usage}
pane=${2:?$usage}
dir=${3:?$usage}
kind=${4:?$usage — <kind> is required (any herdr agent kind; no default)}
case $kind in
  --|-*) echo "$usage" >&2; echo "kind must be an agent kind, got '$kind'" >&2; exit 2 ;;
esac
shift 4
# Tolerate the `--` separator being present or absent.
[ "${1:-}" = "--" ] && shift
agent_args=("$@")
if [ ${#agent_args[@]} -eq 0 ] && [ -n "${ROTATE_AGENT_ARGS:-}" ]; then
  # shellcheck disable=SC2206  # deliberate word-splitting of a config string
  agent_args=(${ROTATE_AGENT_ARGS})
fi

here=$(cd "$(dirname "$0")" && pwd)
"$here/herdr-backend.sh" flavor >/dev/null || exit 1
[ -d "$dir" ] || { echo "worktree dir does not exist: $dir" >&2; exit 1; }

if [ ${#agent_args[@]} -eq 0 ]; then
  "$here/herdr-backend.sh" rotate "$name" "$pane" "$dir" "$kind" --
else
  "$here/herdr-backend.sh" rotate "$name" "$pane" "$dir" "$kind" -- "${agent_args[@]}"
fi

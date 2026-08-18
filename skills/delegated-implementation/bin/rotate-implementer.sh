#!/usr/bin/env bash
# Rotate a Herdr agent onto a new worktree in one step: quit whatever agent
# occupies the pane, cd the pane's shell, start a fresh session.
#
# Usage: rotate-implementer.sh <agent-name> <pane-id> <worktree-dir> [kind] \
#          [-- <native agent args>...]
#   rotate-implementer.sh sol w1:p3 ~/worktrees/task-x codex \
#     -- -m gpt-5.6-sol -c model_reasoning_effort=high
#   rotate-implementer.sh rev w1:p4 ~/worktrees/task-x cursor \
#     -- --model cursor-grok-4.6-high-fast
#
# Args after `--` are forwarded verbatim to `herdr agent start`. Pass the model
# pin here: references/environment.md requires an explicit pin because ids
# drift, and a rotation that omits it silently downgrades the agent to whatever
# its config file defaults to. Omitting them warns on stderr rather than
# failing. ROTATE_AGENT_ARGS supplies a default when none are given.
#
# <kind> is any kind `herdr agent start --kind` accepts (pi, claude, codex,
# gemini, cursor, devin, agy, cline, omp, mastracode, opencode, copilot, kimi,
# kiro, droid, amp, grok, hermes, kilo, qodercli, maki). Defaults to codex.
#
# The pane must exist (create it first: herdr pane split --current
# --direction right --cwd <dir> --no-focus). Prints the started agent JSON.
#
# Every step is state-verified: a failed or slow quit aborts instead of
# typing shell commands into a live agent composer, and the cd is confirmed
# against the pane's foreground_cwd before a new session starts. Safe to run
# concurrently for different (name, pane) pairs — no shared state.
set -euo pipefail

name=${1:?agent name}
pane=${2:?pane id}
dir=${3:?worktree dir}
kind=${4:-codex}
shift $(( $# < 4 ? $# : 4 ))
# Tolerate the `--` separator being present or absent.
[ "${1:-}" = "--" ] && shift
agent_args=("$@")
if [ ${#agent_args[@]} -eq 0 ] && [ -n "${ROTATE_AGENT_ARGS:-}" ]; then
  # shellcheck disable=SC2206  # deliberate word-splitting of a config string
  agent_args=(${ROTATE_AGENT_ARGS})
fi

[ "${HERDR_ENV:-}" = 1 ] || { echo "not inside a Herdr session" >&2; exit 1; }
[ -d "$dir" ] || { echo "worktree dir does not exist: $dir" >&2; exit 1; }
# Physical path, for comparison against the pane's reported foreground_cwd.
target=$(cd "$dir" && pwd -P)

pane_has_agent() { herdr agent get "$pane" >/dev/null 2>&1; }

# Poll for the pane's agent to disappear. Returns 0 if it went away within
# $1 seconds, 1 otherwise.
await_agent_gone() {
  local deadline=$((SECONDS + $1))
  while pane_has_agent; do
    [ "$SECONDS" -ge "$deadline" ] && return 1
    sleep 1
  done
  return 0
}

# Target the PANE, not the name: we care about whatever agent currently
# occupies it. Checking by name would skip the quit when a differently-named
# agent holds the pane, and the cd would then land in that agent's composer
# as a prompt — the exact failure this script exists to prevent.
if pane_has_agent; then
  # Quit commands. Verified on this machine 2026-08-18 by probe: codex,
  # cursor, and claude all exit on `/quit`; claude also exits on `/exit`.
  # Every other kind is ASSUMED to take `/quit` — the escalation ladder below
  # covers a wrong guess by aborting rather than proceeding, so an unverified
  # kind costs time, never correctness. If a kind ever needs different
  # commands, grow this into a case on "$kind". Override for a one-off with
  # ROTATE_QUIT_CMD.
  primary='/quit'
  secondary='/exit'
  if [ -n "${ROTATE_QUIT_CMD:-}" ]; then
    secondary=$primary
    primary=$ROTATE_QUIT_CMD
  fi
  wait_each=${ROTATE_QUIT_WAIT:-8}

  # Escalation ladder. A quit submitted while the TUI is still settling can be
  # swallowed with no error and no exit (observed on claude: the first `/quit`
  # left an empty composer and a live agent; an identical retry exited in 2s).
  # So round 2 is a plain retry, and later rounds clear whatever is
  # intercepting input before retrying.
  ladder=(
    "prompt:$primary"
    "prompt:$primary"
    "keys:esc|prompt:$primary"
    "prompt:$secondary"
    "keys:ctrl-c|prompt:$secondary"
  )

  quit_ok=0
  for round in "${ladder[@]}"; do
    IFS='|' read -r -a steps <<<"$round"
    for step in "${steps[@]}"; do
      case "$step" in
        keys:*)
          herdr agent send-keys "$pane" "${step#keys:}" >/dev/null 2>&1 || true
          sleep 1
          ;;
        prompt:*)
          herdr agent prompt "$pane" "${step#prompt:}" >/dev/null 2>&1 || true
          ;;
      esac
    done
    if await_agent_gone "$wait_each"; then quit_ok=1; break; fi
    echo "quit attempt did not take ($round) — escalating" >&2
  done

  if [ "$quit_ok" != 1 ]; then
    echo "agent in pane $pane survived every quit attempt — not proceeding" >&2
    echo "(inspect with: herdr agent read $pane --source visible)" >&2
    exit 1
  fi

  # Name is released the moment the process exits; give the shell a beat to
  # repaint its prompt after the TUI tears down.
  sleep 1
fi

pane_foreground_cwd() {
  herdr pane get "$pane" | python3 -c '
import json, sys
d = json.load(sys.stdin)["result"]
p = d.get("pane") or d
print(p.get("foreground_cwd") or p.get("cwd") or "")'
}

herdr pane run "$pane" "cd '$dir'" >/dev/null
deadline=$((SECONDS + 10))
while [ "$(pane_foreground_cwd)" != "$target" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "pane $pane did not reach cwd $target within 10s — not proceeding" >&2
    exit 1
  fi
  sleep 1
done

if [ ${#agent_args[@]} -eq 0 ]; then
  echo "warning: no native agent args — '$kind' will start on its config" \
       "default, not an explicit model pin (see environment.md)" >&2
fi

# `agent start` is itself the final verification: it fails unless the pane is
# an available shell at its prompt. A freshly settled pane can transiently
# report agent_pane_busy — retry once before giving up.
start_agent() {
  if [ ${#agent_args[@]} -eq 0 ]; then
    herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000
  else
    herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 \
      -- "${agent_args[@]}"
  fi
}

if ! start_agent; then
  sleep 3
  start_agent
fi

# Phase: execution — load the herdr-delegates skill

Read at first fan-out. The pane transport lives in the
**`herdr-delegates`** skill, installed alongside this one: invoke it (the
Skill tool, or read `${CLAUDE_SKILL_DIR}/../herdr-delegates/SKILL.md`)
for naming with the run prefix, starting agents with model and effort
pinned, brief delivery by path and the callback channel, waiting and
`blocked` dialogs, rotation onto a new worktree, parallel panes and tabs,
and teardown order. Its helpers are at
`${CLAUDE_SKILL_DIR}/../herdr-delegates/bin/` — `run-prefix.sh`,
`rotate-implementer.sh`, `agent-status.sh` — and it reads this skill's
`environment.md` for every CLI-specific fact.

What this protocol adds for a run:

- **Fast reviewer / investigator / mechanical worker.** One pane, model
  pinned at start (ids drift; the listing command is in environment.md),
  for second-opinion reviews, mechanical refactors, sweeps, and
  investigation (recon, repro hunts, "which of these N files does X") —
  where speed and fresh eyes beat deep design context. Verified
  strengths and failure modes: `agent-trust-profiles.md`
  (independent-review). Scope briefs tightly; the reviewer never touches
  git.
- **CI** is watched with `bin/watch-pr.sh` under the harness's background
  monitor — never a long-lived `gh pr checks --watch` (some platforms kill
  or throttle long watchers silently; notes in environment.md) and never
  an improvised loop: improvised loops grep for success and stay silent
  through failures, which looks identical to "still running".
- **The invariant that does not scale away:** every diff is still triaged
  in your session and risk-bearing code read line-by-line
  (independent-review). Reviews serialize through you — pipeline them,
  queue fix rounds per worktree; if review throughput lags, stagger starts
  or shrink the pool. Never thin the review.

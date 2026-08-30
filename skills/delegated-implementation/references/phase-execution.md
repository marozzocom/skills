# Phase: execution — agent lifecycle, fast reviewer, parallel fan-out

Read at first fan-out. Mesh mechanics (briefs by path, callbacks, the
star): SKILL.md §Communication mesh.

## Waiting and lifecycle

- **`idle` is ambiguous on a fresh session** — "finished" and "never
  started" look identical: a prompt stuck unsubmitted in the composer
  looks like an instantly completed turn. Confirm the turn began
  (`working`, or the CLI's turn counter — per-CLI signal in
  environment.md) before looking away; an unconfirmed agent can sit
  stalled for the length of your next deep read. Routine polls via
  `bin/agent-status.sh`; full pane reads are for adjudication.
- Watch turns with `herdr agent wait <name> --timeout <ms>` in a
  background shell; it settles on `idle`/`done`/`blocked`. `blocked` = an
  approval or question UI: read the pane, adjudicate, `send-keys` the
  choice — then check the composer for stray characters before the next
  prompt (send-keys leftovers prepend to it).
- Watch CI with `bin/watch-pr.sh` under a Monitor-style harness — never
  `gh pr checks --watch` (macOS QoS kills long watchers) and never an
  improvised loop: improvised loops grep for success and stay silent
  through failures, which looks identical to "still running".

## Fast reviewer / investigator / mechanical worker

Start with the model pinned explicitly even when a config default exists —
ids drift (commands and the model-listing command in environment.md). A
freshly split pane may reject the start with `agent_pane_busy`; retry
after ~3 s.

Use it for second-opinion reviews, mechanical refactors, sweeps, and
investigation (recon, repro hunts, "which of these N files does X") —
where speed and fresh eyes beat deep design context. Verified strengths
and failure modes: agent-trust-profiles.md. Scope briefs tightly ("report
only actionable findings with file:line, or: no findings"); on drift,
`send-keys <name> esc`, then "stop investigating — write your final
findings report now."

Approval settings are CLI-specific (environment.md). Invariants:
pre-allowlist recurring read-only tools; a blanket run-everything mode
only for strictly read-only tasks; write-capable reviewer sessions stay
on a mode that surfaces edits, adjudicated like the implementer's. The
reviewer never touches git.

## Parallel implementers

Unique names, one pane + worktree each, disjoint file sets only (shared
baselines and lockfiles conflict). Panes share your tab for
glanceability, but each split narrows every pane, and a too-narrow TUI
breaks silently: prompts dropped with no error, agent stuck `idle`, pane
reads rendering a few characters per line. On those symptoms — or a
fan-out that would clearly cramp the tab — give the agent its own tab:
`herdr tab create --cwd <dir>` (returns the tab; read the new pane_id
from `herdr pane list`). Width thresholds per CLI in environment.md.

Fan out early (scouts) and late (reviewers) by preference — read-only,
conflict-free, cheap. Concurrent *writers* are the expensive width, paid
in merge conflicts and in confusion about which tree a finding refers to.

The invariant that does not scale away: every diff is still triaged in
your session, risk-bearing code read line-by-line (phase-review.md).
Reviews serialize through you — pipeline them, queue fix rounds per
worktree; 2–3 concurrent implementers in practice. If review throughput
lags, stagger starts or shrink the pool. Never thin the review.

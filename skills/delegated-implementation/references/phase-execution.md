# Phase: execution — agent lifecycle, fast reviewer, parallel fan-out

Read at first fan-out. Mesh mechanics (briefs by path, callbacks, the
star) are in SKILL.md §Communication mesh.

## Waiting and lifecycle

- **`idle` is ambiguous on a fresh session** — it means both "finished" and
  "never started", so a prompt that landed in the composer unsubmitted looks
  exactly like a turn that completed instantly. Confirm the turn actually
  began (status `working`, or the CLI's turn counter advanced — per-CLI
  signal in environment.md) before you turn your attention elsewhere. An
  agent nobody confirmed can sit stalled for as long as your next deep read
  takes. Routine liveness polls go through `bin/agent-status.sh <name>`
  (SKILL.md §Token economy) — one line back; a full pane read is for
  adjudication, not polling.
- Watch turns with `herdr agent wait <name> --timeout <ms>` in a background
  shell; it settles on `idle`/`done`/`blocked`. `blocked` means an approval or
  question UI — read the pane (`herdr agent read <name> --source visible`),
  adjudicate, `send-keys` the choice. After a dialog interaction, check the
  composer for stray characters before the next prompt (send-keys leftovers
  prepend to your next message).
- On macOS, long-running background watchers (`gh pr checks --watch`) get
  QoS-killed. Watch CI with the pinned poll script `bin/watch-pr.sh` under a
  Monitor-style harness (invocation in environment.md) — it treats an empty
  check list as still-pending, emits every terminal state (fail and cancel,
  not just pass), and exits when all checks settle. Do not improvise the
  loop per run: the improvised versions are exactly the ones that grep only
  for success and stay silent through a failure, which looks identical to
  "still running".

## Fast reviewer / investigator / mechanical worker

Same protocol, different role. Start with the model pinned explicitly (exact
id, command, and the CLI's model-listing command in
`references/environment.md`) even when a config default exists; ids drift.
A freshly split pane may briefly reject the start with `agent_pane_busy` —
the shell isn't at its prompt yet; retry after ~3 s.

What the fast reviewer is for: independent second-opinion reviews, mechanical
refactors, sweep checks, and generic investigation tasks — codebase recon,
repro hunts, "which of these N files does X" questions — where its speed
beats waiting on a heavier model and a fresh set of eyes matters more than
deep design context. The current reviewer's verified strengths and failure
modes (empirical checking, over-investigation, and the like) are in
`references/agent-trust-profiles.md`. Scope review briefs tightly ("report
only actionable findings with file:line, or: no findings") and when it
drifts, `send-keys <name> esc` to skip the pending command, then prompt:
"stop investigating — write your final findings report now."

Approval behavior is CLI-specific; the current reviewer's recommended
settings and known-good configurations live in environment.md. The
invariants regardless of CLI: pre-allowlist recurring read-only tools so
reviews run without stalls; a blanket run-everything mode is acceptable only
for strictly read-only tasks, never for tasks that edit files; and keep
write-capable reviewer sessions on an approval mode that surfaces edits, and
adjudicate them like the implementer's.

The reviewer never touches git either — the role division and the fix-round
etiquette apply unchanged regardless of which CLI is in the pane.

## Parallel implementers

Multiple implementer agents work: unique names, one pane + worktree each,
disjoint file sets only (shared baselines/lockfiles conflict). Panes share the
overseer's tab by default — that's what keeps the run glanceable — but each
split narrows every pane, and a TUI in a too-narrow pane can break silently:
prompts submitted via `herdr agent prompt` + enter are dropped with no error,
the agent sits at `idle`, and `agent read --source visible` renders a few
characters per line. Width, not pane count, is the variable (count thresholds
depend on window size and split orientation; any CLI-specific numbers live in
environment.md). On those symptoms, or when a fan-out would clearly cramp the
tab, give the agent its own tab instead of another split:
`herdr tab create --cwd <dir>` — note it returns the *tab*, not a pane, so
read the new `pane_id` from `herdr pane list` filtered on the returned
`tab_id`. Launch as many sessions as the work shards into — implementer tokens are flat-rate, herdr
enforces name uniqueness (a collision fails loudly at `agent start`), and
the rotation helper is per-(name, pane) with no shared state, so
concurrent rotations don't interact.

Fan out early and late by preference, not in the middle. Scouts before the
frame and reviewers after a done-report are read-only, conflict-free, and
cheap, so that is where width buys the most; concurrent *writers* are the
expensive kind, paid for in merge conflicts and in confusion about which
tree a finding refers to.

The invariant that does not scale away: every diff is still triaged in your
session and its risk-bearing code read line-by-line before it lands (phase-review.md §Review).
Reviews serialize through you, so pipeline them — review each done-report as
it arrives while the other implementers keep working, and queue fix rounds per
worktree. In
practice that means 2–3 concurrent implementers, not a fleet; if review
throughput can't keep up, stagger task starts or shrink the pool — never
thin the review.

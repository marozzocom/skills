# Phase: landing — landing modes, merge policy, complete deliverables, closeout

Read twice: at contract acceptance (the landing mode is decided there)
and again when landing begins.

## Landing modes — how the run ends is decided at contract time

"PR open, awaiting review" exports the run's hardest step to the human.
Decide each milestone's mode at contract acceptance, record it in the
ledger, drive to it — the one contract acceptance covers the mode, merge
included.

- **`land` — autonomous merge.** The default when acceptance criteria
  are invariants gates and evidence can verify without human judgment:
  open the PR, drive checks green, external bot only per
  phase-review.md's criteria, merge, tear down, report done. The
  accepted contract *is* the human review for these PRs.
- **`stage` — one click left.** For results the human plausibly wants to
  see first: visual or UX judgment, walkthroughs, prose they will read
  as a reader. Deliver to one-click state: PR open, checks green,
  threads closed, preview deployed, evidence inline, merge verdict
  stated. The merge is the *only* remaining act — never a merge plus a
  list of things to verify first (§Complete deliverables).
- **`flag` — autonomous merge behind a feature flag.** When behavior is
  best proven in production, or `land` confidence is missing only on
  runtime exposure: gate the surface behind a flag (mechanics per repo
  in environment.md), verify flag-off is a no-op and flag-on works —
  ideally in a preview — then merge and tear down. Report "done, pending
  rollout via flag `<name>`" with the exact enable/disable commands. A
  first-class tool wherever it converts a `stage` into a landed
  deliverable.

**Autonomous landing is off by default — explicit grant only.** `land`
and `flag` exist in a repo only when its own agent docs, or the
autonomous-landing grant line in its review-checklists.md entry (dated,
sourced), authorize autonomous merge there. No grant — including any
repo you have not checked — caps at `stage`, however strong the contract
feels; the grant authorizes the mechanism, the contract decides per run.
And read the repo's actual review conventions first (branch protection,
CODEOWNERS, required checks, delivery policy — record them in the repo's
entry): a repo expecting other-human review caps at `stage` regardless
of grant. Autonomous modes replace only the granting user's own review,
never a required reviewer or a team's process.

Choosing, within the grant: would a human looking at the result exercise
judgment no gate or checklist encodes? Yes → `stage`; no → `land`, or
`flag` when production exposure is the residual risk. Mid-run you may
always downgrade (`land` → `flag` → `stage`; record why); upgrading
toward autonomy requires the human.

## Merge policy — decided by table plus contract, not by feel

You own the merge. Each repo's entry (review-checklists.md or the repo's
rules file) carries a **default-deny path table**: safe-set paths may
auto-merge on green checks in any mode. For paths the table reserves for
human review, an accepted `land`/`flag` contract supplies that review
**only under the autonomous-landing grant** — merging then executes the
human's decision, not your own arming of auto-merge. No safe-set row and
no grant-backed contract → the PR waits. Required reviewers, branch
protection, and team conventions are never bypassed in any mode.

State the verdict in the PR body: the table row (or "outside safe set"),
the landing mode, and for `land`/`flag` the contract reference (run id +
ledger) — a misclassification must be visible in review, not discovered
after a bad merge. Where the human arms auto-merge personally, never
disable what they armed.

## Complete deliverables — close the loops, don't report them

Banned: reporting done "except one or two things to check". An exported
open loop costs the human more than it costs you — you hold the context,
they must rebuild it. Before any report, sweep the ledger's open
questions and would-be follow-ups and close them yourself: run the
check, read the doc, make the small adjacent fix, extend a gate. **If
closing an item costs less than explaining it well, close it.** "One
more thing to double-check" never appears in a report — checking it was
the run's job.

A follow-up survives only when genuinely not yours to close — blocked
externally, a user-only decision (product vocabulary, spend, infra), or
an agreed scope fence — and then decision-ready: what it is, its origin
(file:line, PR, gate), why not closable autonomously, and the one next
action with its owner. If it can't be stated that way, close it or drop
it. Upstream corollary: prefer one landed (or one-click, or flag-gated)
deliverable over an archipelago of almost-done pieces.

## Closeout — report first, teardown inside it

Closeout is one step, and the report is its forcing function: the run is
not closed without the report, and the report is not complete without
teardown evidence — teardown-by-memory is what gets skipped, sitting
after the reward at the point of longest context. When the run's PRs are
merged or abandoned:

1. **Render the run report** from the ledger per
   `references/run-report.md`: timeline, stats, highlights, next-run
   changes. Only measured values — delegate-side token spend is not
   observable; never invent it. If the project continues, end with the
   continuation prompt (SKILL.md §Context discipline).
2. **Tear down in order:** close agent panes FIRST
   (`herdr pane close <pane_id>` — positional ID, not a `--pane` flag),
   remove worktrees SECOND — an agent whose cwd was deleted spins on
   errors until the user notices. Walk the status matrix: every row ever
   opened must end closed.
3. **Verify with a read, not the mutation**, pasted into the report:
   `herdr pane list` shows only panes you did not create,
   `git worktree list` only trees you did not make. Never suppress
   stderr in a teardown chain or emit your own success marker —
   `2>/dev/null` plus an unconditional `echo CLOSED` once reported
   success over a wrong-syntax close and left three orphaned agents on
   screen. Gate any "cleaned up" claim on exit status plus the
   post-state read.

# Phase: landing — landing modes, merge policy, complete deliverables, closeout

Read twice: at contract acceptance (the landing mode is decided there) and
again when landing begins.

## Landing modes — how the run ends is decided at contract time

A run that stops at "PR open, awaiting review" has exported its last and
hardest step to the human. Decide at contract acceptance which of three
landing modes each milestone gets, record it in the ledger, and drive to it.
The human's one acceptance of the contract covers the mode — including the
merge, where the mode says so.

- **`land` — autonomous merge.** The default when the ask is clear and the
  contract is strong: acceptance criteria are invariants that gates and
  evidence can verify without human judgment. You open the PR, drive checks
  green, run the external review bot only when
  phase-review.md §External review bot's criteria hold and budget allows, merge, tear down, and report done. The
  accepted contract *is* the human review for these PRs.
- **`stage` — everything done pending a single merge.** For work where the
  human plausibly wants to see the result before it lands: visual or UX
  judgment, preview-deployment walkthroughs, docs or copy they will read as
  a reader. Deliver to one-click state: PR open, checks green, review
  threads closed, preview deployed with URLs and visual evidence inline in
  the PR body, merge verdict stated. The merge is the *only* remaining act —
  never a merge plus a list of things to verify first (§Complete
  deliverables).
- **`flag` — autonomous merge behind a feature flag.** When the behavior is
  best proven in production, or when `land` confidence is missing only on
  the runtime-exposure axis. Gate the new surface behind a feature flag
  (mechanism and provisioning rules per repo in
  `references/environment.md`), verify both states — flag off is a no-op
  against existing behavior, flag on works, ideally in a preview
  deployment — then merge autonomously and tear down. Report: done, pending
  rollout via flag `<name>`, with the exact enable/disable commands. Repos
  that support flags make this a first-class tool, not an exotic escape
  hatch — reach for it whenever it converts a `stage` into a landed
  deliverable.

**Autonomous landing is off by default — it exists only under an explicit
grant.** `land` and `flag` are available in a repo only when one of two
sources explicitly authorizes autonomous merge/deployment there: the repo's
own agent documentation (its rules file or delivery policy), or the repo's
entry in this skill's references (the **autonomous-landing grant** line in
`references/review-checklists.md`, recorded with date and source). No
grant — including any repo you have not checked — means `stage` is the
ceiling, however strong the contract feels. The grant authorizes the
*mechanism*; the contract still decides per run whether the mechanism is
used.

**Understand the repo's review conventions before proposing a mode.** The
skill is generic and most codebases still require other-human review. On
first delegation in a repo (and when the entry is stale), read what its
process actually expects — branch protection and required reviewers,
CODEOWNERS, required checks, review bots, the rules file's delivery
section — and record it in the repo's `review-checklists.md` entry. A repo
whose convention expects review by another human caps at `stage` regardless
of any grant: autonomous modes replace only the *granting user's own*
review, never a required reviewer, a protection rule, or a team's process.
Respecting the existing convention beats optimizing past it.

Choosing (within what the grant allows): would a human looking at the
result exercise judgment no gate or checklist encodes? Yes → `stage`.
No → `land`, or `flag` when production exposure is the residual risk.
Mid-run you may always *downgrade* (`land` → `flag` → `stage`) when
something surfaces that genuinely needs human eyes — record why in the
ledger; upgrading toward autonomy mid-run requires the human.

## Merge policy — decided by table plus contract, not by feel

You own the merge. Whether a PR may auto-merge is not a per-PR judgment
call: each repo's entry in `references/review-checklists.md` (or the repo's
own rules file) carries a **default-deny path table** — paths in the safe
set may auto-merge on green checks regardless of landing mode. For paths
the table reserves for human review, an accepted `land` or `flag` contract
supplies that review **only in a repo carrying the autonomous-landing
grant (§Landing modes)**: the human approved the merge when they accepted
the contract, so merging is executing their decision, not arming
auto-merge on your own authority. Outside those — no safe-set row, and no
grant-backed `land`/`flag` contract — the PR waits; and required
reviewers, branch protection, and team review conventions are never
bypassed in any mode.

State the full verdict in the PR body: the table row (or "outside safe
set"), the landing mode, and for `land`/`flag` the contract-acceptance
reference (run id + ledger). A misclassification must be visible in review,
not discovered after a bad merge. Where the human arms auto-merge personally
(that act being their approval), never disable what they armed.

## Complete deliverables — close the loops, don't report them

The failure mode this bans: a run reports done "except one or two things to
check", and those trailing items land on the human, who cannot cheaply
reconstruct where they came from or what hangs on them. An open loop you
export costs the human more than it costs you — you have the context to
close it, they must rebuild it.

So before any report, sweep the ledger's open questions and would-be
follow-ups and close them yourself: run the check, read the doc, make the
small adjacent fix, extend a gate. Doing modestly more than the brief asked
is the cheap branch — the rule of thumb is that **if closing an item costs
less than explaining it well, close it**. "One more thing to double-check"
never appears in a report; checking it was the run's job.

A follow-up survives into a report only when it is genuinely not yours to
close — blocked on an external system, a user-only decision (product
vocabulary, spend, infra), or an explicitly agreed scope fence. Then report
it decision-ready, not as a loose end: what it is, where it came from
(file:line, PR, gate), why it could not be closed autonomously, and the one
concrete next action with its owner. If it cannot be stated that way, it is
not ready to report — go close it or drop it.

This also shapes mode choice upstream: prefer stringing partial results into
one landed (or one-merge-staged, or flag-gated) deliverable over reporting
an archipelago of almost-done pieces.

## Closeout — report first, teardown inside it

Closeout is one step, not two, and the report is its forcing function: a
run is not closed until the run report exists, and the report is not
complete without teardown evidence. Teardown-by-memory is what gets
skipped — the sequence lives at the end of the run, after the reward, at
the point of longest context — so the artifact you want (the report)
carries the cleanup you forget.

When the run's PRs are merged or abandoned:

1. **Render the run report** from the ledger using
   `references/run-report.md` — timeline (agents spawned/rotated/torn down,
   gates, PRs, fix rounds), stats, highlights, and what the next run should
   do differently. Report only what was measured (turns, wall time, rounds,
   diff sizes, PR count); delegate-side token spend is not reliably
   observable — never invent it. When the project continues past this run,
   the report ends with the continuation prompt (SKILL.md §Context
   discipline) —
   proposing the next milestone as a fresh session is part of closing this
   one.
2. **Tear down in order**: close agent panes FIRST (`herdr pane close
   <pane_id>` — positional ID, not a `--pane` flag), remove worktrees
   SECOND. A surviving agent whose cwd was deleted spins on "No such file
   or directory" errors until the user notices. Walk the ledger's status
   matrix — every row ever opened must end closed; the matrix is the
   registry of what exists, so nothing untracked can be forgotten.
3. **Verify with a read, not the mutation**, and paste the evidence into
   the report's teardown section: after closing, `herdr pane list` must
   show only panes you did not create, and `git worktree list` only trees
   you did not make. Never suppress stderr in a teardown chain and never
   emit your own success marker — `2>/dev/null` plus an unconditional
   `echo CLOSED` once turned a wrong-syntax close into a reported success
   and left three orphaned agents on screen. Gate any "cleaned up" claim on
   exit status plus the post-state read.

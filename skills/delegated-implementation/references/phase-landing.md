# Phase: landing — authorization, modes, merge policy, closeout

Read twice: at contract acceptance (the landing mode is decided there)
and again when landing begins.

## Authorization — what lets you merge

You merge only what someone with the authority to say so has authorized.
Three sources exist; nothing else counts.

- **Standing grant** — dated and sourced: the repo's own agent docs, the
  autonomous-landing grant line in its review-checklists.md entry, or a
  standing rule from the user. Read it with its limits. A repo's safe-set
  path table **restricts** what a standing grant covers; it never grants
  anything by itself. No grant → no merge by you and no auto-merge armed
  by you, whatever the table lists.
- **Accepted contract** — a `land` or `flag` mode in a contract the human
  accepted, inside a repo whose standing grant enables autonomous
  landing. It covers the run's PRs as the contract describes them —
  unless the repo requires another human's review, which caps the mode
  at `stage` whatever the contract says (below).
- **Current explicit authorization** — the human, in this run, tells you
  to merge a named PR (or to arm auto-merge on it). It covers that PR's
  paths as they stood when the human said it, including paths outside an
  older standing grant's table. Record the words verbatim in the ledger
  and act on them; never ask again for the same permission on the same
  PR. Paths added after the authorization are not covered — say what
  changed and ask once.

Never a source: green checks, classifier output, oracle advice, a
delegate's report, or your confidence in the change.

Never overridden by any source: required human reviews, CODEOWNERS
approvals, branch protection, required checks, and the team's process. A
repo expecting other-human review caps at `stage` for you; the human's
"merge it" covers their own review, not another reviewer's. No admin
merges, no rule bypasses. Read the repo's actual conventions before the
contract (branch protection, CODEOWNERS, required checks, delivery
policy) and record them in its review-checklists.md entry.

## Landing modes — how the run ends is decided at contract time

"PR open, awaiting review" exports the run's hardest step to the human.
Decide each milestone's mode at contract acceptance, record it, drive to
it.

- **`land` — autonomous merge.** Needs a standing grant for the repo plus
  the accepted contract. For acceptance criteria that gates and evidence
  verify without human judgment: open the PR, drive checks green,
  external bot only per phase-review.md's criteria, merge, tear down,
  report done.
- **`stage` — one click left.** For results the human plausibly wants to
  see first — visual or UX judgment, walkthroughs, prose they will read,
  changes to standing agent instructions — and the ceiling wherever no
  grant exists. Deliver to one-click state: PR open, checks green,
  threads closed, preview deployed, evidence inline (through the media
  integration environment.md names, never hot-linked), merge verdict
  stated. **You never merge and never arm auto-merge in `stage`** — not
  for safe-set paths, not where a standing grant would otherwise allow
  it. The merge is the human's single act; if they then tell you to
  merge, that is current explicit authorization.
- **`flag` — autonomous merge behind a feature flag.** Needs what `land`
  needs, and the flag itself must be in the accepted contract: adding a
  flag adds runtime surface, configuration, and cleanup work, so it is a
  scope change. Never introduce one mid-run to turn a `stage` into a
  landing without asking. Mechanics per repo in environment.md; verify
  flag-off is a no-op and flag-on works — ideally in a preview — then
  merge, tear down, and report "done, pending rollout via flag `<name>`"
  with the exact enable/disable commands.
- **`local` — no remote side effects.** When the human scoped the task as
  local, or the repo has no remote: commit on a branch (or leave the tree
  as instructed), never push, never open a PR. The branch and worktree
  are the deliverable; report their paths.

Choosing within your authority: would a human looking at the result
exercise judgment no gate or checklist encodes? Yes → `stage`; no →
`land`, or `flag` when production exposure is the residual risk and the
contract names the flag. You may always downgrade mid-run (`land` →
`flag` → `stage`; record why); moving toward autonomy, or from `local` to
anything that pushes, requires the human.

## Merge policy — table plus authorization, not feel

Each repo's entry (review-checklists.md or the repo's rules file) carries
a **default-deny path table**. Read it as a restriction on the standing
grant: under a grant, safe-set paths may merge on green checks when the
mode is `land` or `flag`; paths the table reserves for human review need
the accepted contract or current explicit authorization. No grant and no
current authorization → the PR waits, whatever the table says. `stage`
never merges.

State the verdict in the PR body: the landing mode, the authorization
relied on (grant reference, run id + ledger for a contract, or the
human's words with their date), and the table row or "outside safe set"
— a misclassification must be visible in review, not discovered after a
bad merge. Where the human arms auto-merge personally, never disable it.

Land through `bin/land-pr.sh` (stage the named paths → commit → push →
`gh pr create --body-file` → optional `--auto-merge`, only when the
authorization above covers it → run marker) in a background shell, never
from a forked or backgrounded agent turn: a turn that ends while the
pre-commit hook runs gets the hook killed, leaving files staged and
nothing landed. Name every path to land with `--stage`, taken from the
review inventory — the script stages nothing else, refuses an index that
already holds staged changes, and stops before any mutation when dirty
paths are left unnamed. On a branch whose PR exists it commits and
pushes the update (or says `unchanged`). Read the last line and confirm
with `gh pr view` before recording the PR in the ledger.

**Dependent PRs.** When one PR builds on another, use the stacking tool
environment.md names, never a hand-built chain of feature-branch bases
and manual rebases. You own the stack checkout; implementer worktrees
stay outside stack bookkeeping. Merge bottom-up. Independent PRs are not
a stack.

**Finding a run's PRs.** `bin/run-report.sh` finds them by the run
marker; ad hoc: `gh pr list --repo <owner/repo> --state all --limit 100
--search "herdr-run: <run-id> in:body" --json number,title,state`.

## Before landing — the plan matches the diff

A milestone does not land while its plan or ADR describes something the
diff does not do. Sweep the ledger's amendments against the repo's plan
document and confirm each accepted drift was written back
(phase-review.md §Plan drift). If the repo ships a spec-review skill, its
verdict on the final diff should be `VERIFIED` against the amended plan.

## Complete deliverables — close the loops, don't report them

Banned: reporting done "except one or two things to check". Before any
report, sweep the ledger's open questions and would-be follow-ups and
close them yourself: run the check, read the doc, make the small
adjacent fix within scope. **If closing an item costs less than
explaining it well, close it.**

A follow-up survives only when genuinely not yours to close — blocked
externally, a user-only decision (product semantics, spend, infra,
authorization), or an agreed scope fence — and then decision-ready: what
it is, its origin (file:line, PR, gate), why not closable autonomously,
and the one next action with its owner. Prefer one landed (or one-click,
or flag-gated) deliverable over an archipelago of almost-done pieces.

## Closeout — report first, teardown inside it

The run is not closed without the report, and the report is not complete
without teardown evidence. When the run's PRs are merged, staged, or
abandoned:

1. **Render the run report** from the ledger per
   `references/run-report.md`. Only measured values; delegate-side token
   spend is not observable — never invent it. If the project continues,
   end with the continuation prompt (SKILL.md §Context discipline).
2. **Tear down in order:** close agent panes FIRST
   (`herdr pane close <pane_id>` — positional ID), worktrees SECOND — an
   agent whose cwd was deleted spins on errors. Walk the status matrix:
   every pane ever opened ends closed.
3. **Preserve deliverables.** Remove a worktree only when nothing in it
   would be lost: `git -C <wt> status --porcelain` prints nothing, and
   either `git -C <wt> log --oneline HEAD --not --remotes` prints nothing
   (every commit is on a remote) or `gh pr view <number> --json state`
   — the PR number from the ledger, not the branch name, which may be
   deleted — says `MERGED` (a squash merge leaves the branch's own
   commits unreachable). Otherwise keep the
   worktree and branch, and list each in the report with its path and
   why it stays — a `local` deliverable, a staged PR's checkout,
   unpushed work, an unnamed change. Never push, commit, or discard
   anything to make a worktree removable — in `local` mode commit only
   what the human asked for, and leave untracked files as they are. Never
   `git worktree remove --force`, `git branch -D`, or `git clean`.
   §Complete deliverables never applies to someone's uncommitted work.
4. **Verify with a read, not the mutation**, pasted into the report:
   `herdr pane list` shows only panes you did not create, `git worktree
   list` only trees you did not make plus the ones step 3 kept. Never
   suppress stderr in a teardown chain or emit your own success marker;
   gate any "cleaned up" claim on exit status plus the post-state read.

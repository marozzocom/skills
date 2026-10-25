---
name: independent-review
description: "Independent verification and tiered review of an implementation
before it is committed, whoever wrote it — you, a subagent, or a delegated
CLI agent — and on any done-report. Owns the acceptance re-run of
deterministic gates, the review inventory and triage, the risk-range deep
read, mutation checks on new tests, centralized checklists, fix rounds,
review threads, and the external-bot escalation rule. Use PROACTIVELY
before committing your own direct implementation of more than a trivial
diff, when a delegate or subagent reports done, and when asked for a
second-opinion review. The reviewer is never the author of the diff and
never shares the author's context. Never activate in a session executing
an assigned brief from an orchestrator: the orchestrator reviews."
---

# Independent review

Verdicts never move: gates, security semantics, design conformance, and
adjudication stay with you. Everything else about review is I/O you may
delegate. The one rule above all others: **whoever wrote the diff does not
review it, and the reviewer does not share the author's context.** When
you implemented directly, that means a fresh reviewer that has not seen
your reasoning, not a fork of your session.

Helpers are at `${CLAUDE_SKILL_DIR}/bin/`; each header comment is its
contract. Per-repo policy lives in `references/review-checklists.md`;
per-agent calibration in `references/agent-trust-profiles.md` (both
local, created from the templates beside them).

## Who reviews — pick the reviewer, then the transport

- **The author never reviews.** Not the implementer, not a fork of your
  own context if you implemented. Fresh eyes are the point.
- **Deterministic checks need no reviewer:** the verdict is the exit code.
- **Routine diffs:** a fast reviewer of any family, briefed by path with a
  read fence (below). A native subagent is the cheapest transport; a
  pane-hosted CLI when the environment pins one or the human asked.
- **Risk-bearing surfaces** (auth, permissions, data integrity,
  concurrency, money): your own line-by-line read, **and** where a
  confidently wrong "clean" is the expensive failure, a reviewer from a
  **different model family** than the implementer — same-family review
  shares the implementer's blind spots. A "no findings" from a
  same-family fast reviewer on these surfaces is not clearance.
- **Small direct diffs** (single-digit files, no risk surface): your own
  read against the inventory is the review; no fan-out. Gates and the
  mutation check still run.
- Record per node in the ledger or notes: who reviewed, which family,
  what they were fenced to. "Who verified this?" must always be
  answerable.

## Verification ownership — the verdict decides the runner

- **Deterministic checks** (tests, type-check, lint, gate runners): the
  runner is interchangeable, so run them twice. The implementer runs them
  in its own loop; you re-run at the gate via
  `${CLAUDE_SKILL_DIR}/bin/run-gates.sh <worktree> "NAME:COMMAND" ...`,
  and that re-run is the acceptance. Green is necessary, not sufficient:
  never let "tests pass" clear work that hardcoded an expected value,
  weakened an assertion, or bypassed a requirement — spot-check the diff
  for exactly that.
- **A test written in the same run gets no verdict from its own exit
  code.** For any test that pins something (a default, an invariant, a
  regression guard): mutate the implementation and confirm the test
  fails — the only evidence it is load-bearing. When it does not fail,
  ask which layer actually holds the invariant.
- **Judgment checks** (UI, visual QA, semantic review, a11y beyond scans)
  split three ways: the **standard** is written and centralized; the
  **evidence** is delegable (screenshots, preview URLs, recordings); the
  **verdict** is yours or one named judge per domain. Delegates produce
  evidence, never clearance.
- **Report facts are checked, not read.** Before judging a done-report,
  confirm its deterministic facts directly: each check's exit status and
  `not run` lines, that every cited log exists and is non-empty, that
  the files-changed list matches the inventory. A missing log or an
  unexplained `not run` is a red gate, whatever the narrative says.

## Tiered review — you keep judgment, delegate I/O

Every diff is triaged; risk-bearing code you read line-by-line;
mechanical code passes on tooling plus a delegated sweep.

1. **Inventory.** The review snapshot is everything changed since the
   task's base SHA — committed, staged, unstaged, untracked:
   `${CLAUDE_SKILL_DIR}/bin/review-inventory.sh <worktree> <base>`. A bare
   working-tree diff is never the inventory.
2. **Triage** by a reviewer who did not write the diff: *"Classify every
   path in `<inventory file>` against base `<sha>` — mechanical
   (rename/generated/lockfile/snapshot), routine, or risk-bearing (auth,
   data, contracts, concurrency). Write to `<triage file>` one line per
   file (`<file> <tier> <one-line reason>`); for a risk-bearing file add
   one line per risk range in NEW-side line numbers
   (`<file>:<start>-<end> risk <reason>`); use `<file>:all` for a
   deletion, rename, mode or binary change. Edit nothing."* Reconcile the
   manifest against the inventory **by path identity**, never by count.
3. **Deep-read the risk ranges** via
   `${CLAUDE_SKILL_DIR}/bin/diff-hunks.sh <worktree> <base> <file>
   <start>-<end>|all` (exits 3, never silently, when a range selects
   nothing). Spot-check the routine set; accept the mechanical set on
   gates green plus type-check green plus a clean sweep. Never a bare
   `git diff` once the manifest exists.
4. **Asymmetry, non-negotiable:** triage and any classifier may
   *escalate* a hunk to your read, never demote one you would call risky.

Triage lands before your deep read; routing your attention is its whole
purpose. Checklist and aspect passes run on a **settled** tree — park
reviewers during fix rounds and re-brief with what changed. Where the
frame names several risk surfaces, fan one read-only reviewer per
surface. Three or more reviewer reports on one tree → a cheap fresh
reviewer merges them into one deduplicated, source-cited list keeping
every dissent; you adjudicate the merged list.

## Reviewer briefs — by path, read-fenced, write-forbidden

Brief every reviewer by path to a file, never inline past a few lines.
Every reviewer brief carries:

- the tree, the base SHA, and the files or checklist it is to read —
  **never** the implementer's report, pane, transcript, or
  self-assessment, so the verdict is its own;
- *"Report only actionable findings with file:line, or 'no findings'.
  Do NOT edit anything, even if a checklist tells its reader to
  auto-fix."* The reviewer is read-only in a tree it does not own; fixes
  route to the implementer or to you — never two writers in one tree;
- for a spec reviewer, the accepted task or plan and its amendments,
  named by you. Independence is kept by withholding the implementer's
  self-assessment, not the requirement being checked.

Ask for demonstrations, not opinions: a hedge ("not sure this always
mounts after the cache is warm") is an unsettled claim and the
highest-yield thing a reviewer says. Settle it by reading the installed
source or making it fail.

## Checklists — centralized with you, run on a reviewer

Implementers never run the repo's review skills or checklists; one
centralized reviewer configuration gates every implementer consistently.
Repo → checklist map, escalation domains, and the verification matrix:
`references/review-checklists.md`; for an unmapped repo, discover (rules
file, skill directories) and add an entry. Brief the reviewer per
checklist (batch small ones): *"Read `<doc>` and apply it as a review
checklist to the changes in `<worktree>` (`git -C <worktree> diff
<base>` plus untracked files — the tree is intentionally dirty)."*
Re-run affected checklists after each fix round.

Security and authorization checklists — and "no findings" on any diff
touching auth or permissions — get your own read or the stronger,
different-family reviewer the repo's entry names.

## Plan drift — write it back

Accepted drift that changes what the repo's plan or ADR says is amended in
that document before the milestone lands, in the same PR as the code;
otherwise the next spec review reads a plan the merged diff contradicts.

## Fix rounds

Send back constraints, not just symptoms: the gate's first relevant error
verbatim, what must NOT change (don't weaken a proof, touch baselines,
cast unsafely), and the re-run in the standard report shape (verdict line
plus log path). When a gate flags something, first ask whether the
flagged thing should exist at all — "make the gate pass" is the wrong
instruction when "delete it" is available. A fix that touched a pinned
test has shown only that the test now agrees with the code; send it back
with the test restored.

## Review threads — close the loop yourself

Every addressed comment gets a reply naming the fix commit, then gets
resolved; addressed-but-unresolved reads as unhandled. Resolve only what
was fixed or verified wrong (say which); leave explicitly deferred items
open. `${CLAUDE_SKILL_DIR}/bin/resolve-thread.sh <owner/repo> <pr>
<comment-id> "Fixed in <sha>: <one line>."`; `--no-resolve` to reply and
leave open.

## Preview deployments

Opt in (mechanism and budget per repo in the environment reference the
orchestration skill names) when a live URL earns its keep: UI-facing
changes, client+backend integration, anything you would otherwise
screenshot. Skip for docs, tooling, sweeps, CI-only changes.

## External review bot — final pass, sparingly

Usage-billed escalation, never a pipeline stage. At most once per PR,
after the checklist pass and your tiered review are clean, and only if
one holds: the diff touches auth/payments/data deletion or
migration/infra; residual uncertainty you can name; or you and the
reviewer disagree and the code didn't settle it. Routine PRs never
qualify. Verify every finding against the code — bot confidence is not
evidence — route real fixes, close threads. Re-trigger only when a fix
round materially changed risk-bearing code.

## Record

Per node, for the run report: reviewer families, findings by family
(and how many the implementer's own family also raised), fix rounds,
mutation checks run, what you deep-read. Trust earned or lost by a
delegate goes into `references/agent-trust-profiles.md` — verified
behavior only, never vendor claims; a new agent kind starts at zero.

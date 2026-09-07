# Phase: review — verification, tiered review, checklists, threads

Read at the first done-report. Verdicts never move: gates, security
semantics, design conformance, and adjudication stay with you.

## Verification ownership — the verdict decides the runner

- **Deterministic checks** (tests, type-check, lint, gate runners): the
  verdict is the exit code, so the runner is interchangeable — run them
  twice. The implementer runs them in its own loop (feedback stays local;
  lint/type fixes stay with the implementer or the cheapest worker); you
  re-run at the gate via `bin/run-gates.sh`, and that re-run is the
  acceptance. Green is necessary, not sufficient: never let "tests pass"
  clear work that hardcoded an expected value, weakened an assertion, or
  bypassed a requirement — spot-check the diff for exactly that.
- **A test the delegate wrote in the same run gets no verdict from its
  own exit code** — green says the assertion held, not that it would fail
  if the behaviour regressed, and an agent testing its own diff pulls
  toward green. For any test that pins something (a default, an
  invariant, a regression guard): mutate the implementation and confirm
  the test fails — the only evidence it is load-bearing. When it does
  not fail, ask which layer actually holds the invariant — often a
  library default nobody named, worth learning and pinning either way.
- **Judgment checks** (UI, visual/UX QA, semantic review, a11y beyond
  scans) split three ways: the **standard** is written and centralized (a
  bar living in one model's head is not a standard); the **evidence** is
  delegable (screenshots, preview URLs, recordings); the **verdict** is
  yours, or one named judge per domain — never each implementer privately
  interpreting the standard. Delegates produce evidence, never clearance.
- The check → runner → verdict-owner → evidence matrix is per-repo in
  review-checklists.md; record per-run deviations in the ledger so "who
  verified this?" is always answerable.

## Review — tiered: you keep judgment, delegate I/O

Every diff is triaged; risk-bearing code you read line-by-line;
mechanical code passes on tooling plus a delegated sweep.

The review snapshot is **everything changed since the task's base SHA**
— committed (a red test you committed), staged, unstaged, and untracked
alike: `bin/review-inventory.sh <worktree> <base>` lists it, one path per
line with its status. A bare working-tree diff misses the commits and
the untracked additions, so it is never the inventory.

On a done-report, first send the fast reviewer — never the implementer
whose diff it is — a **triage pass**: *"Classify every path in
`<inventory file>` against base `<sha>` — mechanical (rename/generated/
lockfile/snapshot), routine, or risk-bearing (auth, data, contracts,
concurrency). Write to `<triage file>` as a routing manifest: one line per
file (`<file> <tier> <one-line reason>`); for a risk-bearing file add one
line per risk range in NEW-side line numbers (`<file>:<start>-<end> risk
<reason>`) — hunks of that file outside the named ranges are routine
unless you say otherwise — and use `<file>:all` for a deletion, rename,
mode or binary change. Edit nothing."* Reconcile the manifest against
the inventory **by path identity** before trusting it: equal counts can
hide an omitted path and a spurious one, and a label cannot protect a
file you never learn exists. A hunk-per-row table for a large mechanical
diff would cost nearly what the diff does — hence per-file rows.
Deep-read the risk ranges via `bin/diff-hunks.sh <worktree> <base>
<file> <start>-<end>|all` (a bare `git diff -- <file>` returns every hunk
in the file; the script exits 3, never silently, when a range selects
nothing), spot-check the routine set, accept the mechanical set on gates
green + type-check green + a clean sweep. Never a bare `git diff` once
the manifest exists. One asymmetry is non-negotiable: triage may
*escalate* a hunk, never demote one you'd call risky — when in doubt, you
read it.

The triage lands **before** your deep read: routing your attention is its
whole purpose. Checklist and aspect passes run on a **settled** tree —
findings against a half-applied fix round are noise, so park reviewers
during fix rounds and re-brief with what changed. Where the frame names
several risk surfaces, fan one read-only reviewer per surface; that width
is conflict-free.

Also delegable as I/O: recon before briefing, repro hunts, CI collection,
cross-file consistency sweeps. Per-agent trust:
agent-trust-profiles.md — a new agent kind starts at zero trust.

## Review checklists — centralized with you, run on the fast reviewer

Implementers never run the repo's review skills or checklists — the brief
says so explicitly, overriding any repo rules file that tells agents to
self-review. One centralized reviewer configuration gates every
implementer consistently and stops duplicate spend. Repo → checklist map:
review-checklists.md; discover and add entries for unmapped repos.

Brief the reviewer per checklist (batch small ones): *"Read `<doc>` and
apply it as a review checklist to the changes in `<worktree>`
(`git -C <worktree> diff <base>` plus untracked files — the tree is
intentionally dirty). Report only
actionable findings with file:line, or 'no findings'. Do NOT edit
anything, even if the checklist tells its reader to auto-fix."* A spec
reviewer additionally gets the accepted task or plan and its ledger
amendments, named by you — independence is kept by withholding the
implementer's self-assessment, not the requirement being checked. The
reviewer is read-only in a tree it does not own; fixes route to the
owning implementer — never two writers in one tree. Reviewer briefs carry
the read fence too (brief-template.md): the tree, the checklist, and the
files named — never the implementer's report or pane; the implementer's
brief only when it is the accepted task and you name it — so the verdict
is its own, not a re-reading of the implementer's self-review.
Re-run affected checklists after each fix round; collate multi-reviewer
findings per
SKILL.md §Token economy.

Security/authorization checklists — and "no findings" on any diff
touching auth or permissions — get your own read or the stronger reviewer
the repo's entry names. That is the model-routing lever: fast model by
default, a stronger one where a confidently wrong "clean" is the
expensive failure.

## Plan drift — write it back, don't just record it

Implementers report plan/code drift in every report (phase-design.md
§Briefs) and the ledger records what you adjudicated. The ledger is not
in the repo. Any accepted drift that changes what the repo's own plan or
ADR says — a point the plan left open, a step done another way, scope
added or dropped — is amended in that document before the milestone
lands, in the same PR as the code. Otherwise the next run's spec
reviewer reads a plan the merged diff contradicts and every finding
against it is noise. Route the amendment to the implementer that owns
the tree, scoped to the plan document; it is the one write a spec
finding produces.

## Fix rounds

Send back constraints, not just symptoms: the gate's first relevant
error verbatim, what must NOT change (don't weaken a proof, touch
baselines, cast unsafely), and the re-run in the standard report shape
(verdict line plus log path — SKILL.md §Token economy). When a gate flags
something, first ask whether the flagged thing should exist at all —
"make the gate pass" is the wrong instruction when "delete it" is
available.

## Review threads — close the loop yourself

Every addressed comment (yours, a bot's, a human's) gets a reply naming
the fix commit, then gets resolved — addressed-but-unresolved reads as
unhandled and re-derails the next reviewer. Resolve only what was fixed
or verified wrong (say which); leave explicitly-deferred items open.
Mechanics: `bin/resolve-thread.sh <owner/repo> <pr> <comment-id>
"Fixed in <sha>: <one line>."` — comment id = the finding's `databaseId`;
`--no-resolve` to reply and leave the thread open.

## Preview deployments

Opt in (mechanism and budget per repo in environment.md) when a live URL
earns its keep: UI-facing changes, client+backend integration, anything
you would otherwise screenshot. Skip for docs, tooling, sweeps, and
CI-only changes — previews spend a bounded budget.

## External review bot — final pass, sparingly

Usage-billed escalation, never a pipeline stage (mechanics in
environment.md). Trigger at most once per PR, after the checklist pass
and your tiered review are clean, and only if one holds: the diff touches
auth/payments/data deletion or migration/infra; residual uncertainty you
can name; or you and the fast reviewer disagree and the code didn't
settle it. Routine PRs never qualify. Poll with short foreground checks
where the platform kills long watchers (environment.md). Verify every
finding against the code —
bot confidence is not evidence — route real fixes to the implementer,
close threads per above. Re-trigger only when a fix round materially
changed risk-bearing code; incremental-review behavior is bot-specific
(environment.md).

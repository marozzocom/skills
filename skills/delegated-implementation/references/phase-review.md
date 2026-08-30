# Phase: review — verification, tiered review, checklists, threads

Read at the first done-report. Verdict ownership never moves: gates,
security semantics, design conformance, and adjudication stay with the
orchestrator.

## Verification ownership — the verdict decides the runner

Who runs a check is decided by where its verdict lives:

- **Deterministic checks** (tests, type-check, lint, format, gate runners) —
  the verdict is in the exit code, so the runner is interchangeable: run
  them twice. The implementer runs them in its own loop (feedback stays
  local; lint/type fixes are mechanical and stay with the implementer or the
  cheapest worker). You re-run at the gate — that re-run is the acceptance,
  the implementer's run just saves round-trips — and it runs through
  `bin/run-gates.sh <worktree> "<name>:<command>" ...`: one verdict line
  per gate, failure tails only, full logs on disk. A green exit code is
  necessary, not sufficient: never let "tests pass" clear work that
  hardcoded an expected value, weakened an assertion, or bypassed a stated
  requirement to get there — spot-check the diff for that specifically.
- **The exit code is not a verdict for a test the delegate wrote in the same
  run.** Green reports that the assertion held, not that it would break if the
  behaviour it names regressed — and an agent authoring tests for its own diff
  has a structural pull toward green. So for any test whose whole job is to pin
  something (a default, an invariant, an idempotency claim, a regression guard),
  mutate the implementation and confirm the test fails. Cheap, and it is the
  only evidence that the test is load-bearing rather than decorative. When it
  does *not* fail, the useful question is not "is this tautological" but **which
  layer is actually holding the invariant** — often a library default nobody
  named, which is worth learning and worth pinning either way.
- **Judgment checks** (UI verification, visual/UX QA, semantic review,
  accessibility beyond automated scans) — split into three parts with
  different owners. The **standard** is centralized and written (repo
  guidelines/checklists — a quality bar that lives in one model's head isn't
  a standard; written, it constrains any agent, model, or human equally).
  The **evidence** is delegable: screenshots, preview URLs, recordings,
  structured observations. The **verdict** stays with you, or one named
  judge per domain — never with each implementer privately interpreting the
  standard, which yields a fragmented product where every diff individually
  "passed".
- Delegates produce evidence, never clearance: an implementer's "UI looks
  right" is a report of what it did, not a verification.
- The who-verifies-what matrix is per-environment: each repo's entry in
  `references/review-checklists.md` names the checks, runners, verdict
  owners, and evidence types. Record per-run deviations in the ledger so
  "who verified this?" is always answerable.

## Review — tiered: you keep judgment, delegate I/O

The review invariant, stated honestly: every diff is **triaged**,
risk-bearing code is read line-by-line by you, mechanical code is verified
by tooling plus a delegated sweep. For a 200-line auth change nothing
changes; for a 2,000-line rename it's the difference between a burned
context window and a ten-minute gate.

On a done-report, first send the fast reviewer a **triage pass**:
*"Classify this diff hunk-by-hunk — mechanical
(rename/generated/lockfile/snapshot), routine, or risk-bearing (auth, data,
contracts, concurrency). Write the result to <triage file> as a routing
table — one line per hunk, `<file>:<start>-<end> <tier> <one-line
reason>` — and do not edit anything."* The triage is a routing file, not a
report to read end-to-end. Deep-read the risk-bearing ranges yourself,
pulling each one scoped — `git -C <worktree> diff -U5 -- <file>`, read the
cited range — never a bare `git diff` over the whole tree: once the routing
file exists, the full diff enters your context at most once, and ideally
never. Spot-check the routine set, and accept the mechanical set on gates
green + type-check green + a clean sweep. One asymmetry is non-negotiable:
the triage may
*escalate* a hunk to risk-bearing but never demote one you'd call risky —
misclassification toward "mechanical" is the expensive failure, so when in
doubt you read it.

Order matters as much as the tiers. The triage lands **before** your deep
read — routing your attention is its whole purpose, and a triage that
arrives while you are already reading everything has bought nothing. Any
checklist or aspect pass runs on a **settled** tree: findings against a
half-applied fix round are noise, so park a reviewer rather than let it
review a tree that does not exist, and re-brief it with what changed when
you unpark it. Where the brief names several distinct risk surfaces, fan out
one reviewer per surface — contracts, async and loading states, tests, the
repo's own checklists — instead of asking one agent for all of it; the frame
already enumerated the surfaces. Reviewers are read-only, so this width is
free of conflicts.

Also delegable to the fast reviewer as mechanical I/O: recon before
briefing, repro hunts, collecting CI results, cross-file consistency sweeps.
What never leaves you: design conformance, security semantics, gate
verdicts, and adjudicating findings — yours, the reviewers', or the
implementer's own.

How far to trust each delegate's claims is recorded per agent kind in
`references/agent-trust-profiles.md` — consult it when deciding what to
independently verify. A new agent kind starts at zero trust (verify
everything) and earns a profile entry from verified behavior.

## Review checklists — centralized with you, run on the fast reviewer

If the repo ships review skills or checklists — guardian skills, review
sections inside a rules file, testing-review docs — implementers never run
them themselves; the brief says so explicitly, overriding any repo rules file
that tells agents to self-review. Centralizing the pass in your session is
what makes results consistent: one reviewer configuration gates every
implementer's work instead of each CLI's variable self-review, and parallel
implementers stop burning tokens duplicating the same checks.

`references/review-checklists.md` maps each repo on this machine to its
checklist sources, path→checklist mapping, and escalation rules. For an
unmapped repo, discover them (rules file, `.claude/skills/`) and add the
entry.

On a done-report, run the applicable checklists through the fast reviewer,
alongside your own tiered read (§Review):

- Map changed files to checklists per the repo's entry in the reference file.
- Brief the reviewer per checklist (batch small ones): *"Read `<doc path>` and
  apply it as a review checklist to the changes in `<worktree>`
  (`git -C <worktree> diff` — the tree is intentionally dirty). Report only
  actionable findings with file:line, or 'no findings'. Do NOT edit anything,
  even if the checklist tells its reader to auto-fix."*
- The reviewer is read-only in a worktree it does not own. Checklist fixes
  route to the implementer that owns the worktree as a normal fix round — never
  two
  writers in one tree.
- Re-run the affected checklist after each fix round.

When several reviewers report on the same settled tree, do not read N
overlapping reports — have a cheap harness subagent (model pinned per
environment.md's cost table) merge the finding files into one deduplicated
list, clustered by file, every finding citing its source report and
file:line. You adjudicate the merged list; the collation was I/O, not
judgment.

For security/authorization checklists, and for "no findings" on any diff
touching auth or permissions, verify the semantics yourself or escalate that
one domain to the stronger reviewer the repo's entry names. That is the
model-routing lever: the fast model by default, a stronger model where a
confidently wrong "clean" verdict is the expensive failure.

## Fix rounds

Send failures back to the implementer with constraints, not just symptoms:
name the gate/error verbatim, state what must NOT change (don't weaken a
proof, don't touch baselines, no unsafe casts), and require the re-run output
verbatim.
When a quality gate flags something, first ask whether the flagged thing
should exist at all (an unconsumed preload, a test restating literals) —
"make the gate pass" is the wrong instruction when "delete the thing" is
available.

## Review threads — close the loop yourself

After a review comment is addressed (yours, a review bot's, or a human's), the
thread gets a reply naming the fix commit, then gets resolved — an addressed
finding left "unresolved" reads as unhandled and re-derails the next
reviewer. Only resolve what was actually fixed or was verified wrong (say
which); leave explicitly-deferred items open.

`gh` has no native resolve, so the mechanics are scripted:
`bin/resolve-thread.sh <owner/repo> <pr> <comment-id> "Fixed in <sha>: <one
line>."` posts the in-thread reply, locates the review thread containing
that comment id, resolves it, and prints one line back. Comment ids are the
finding comments' `databaseId`. For a reply that must leave the thread open
(a deferred item, a question back to the reviewer), append `--no-resolve`.

## Preview deployments — opt in when a live URL earns its keep

Some repos offer per-PR preview deployments; which ones, the opt-in
mechanism, and the budget are per repo in `references/environment.md`. Opt
in when a reviewer or verification step benefits from a live URL: UI-facing
changes, client+backend pairs whose integration is the point, anything you
would otherwise screenshot from a local run. Skip it for docs, tooling,
mechanical sweeps, and CI-only changes — previews spend a bounded budget.

## External review bot — final pass, sparingly

An external PR review bot (which one, its enablement, and its trigger/poll
commands: `references/environment.md`) can serve as a last outside pass.
Runs are typically usage-billed — treat it as an escalation spent on
residual risk, never a pipeline stage.

Trigger at most once per PR, after the checklist pass and your own tiered
review are clean and the PR is open, and only when at least one
condition holds:

- the diff touches auth/RBAC/permissions, payments/billing, data deletion or
  migration, or infra/deploy workflows;
- the change is cross-cutting enough that your review left residual
  uncertainty you can name;
- your review and the fast reviewer's second opinion disagree and reading
  the code did not settle it.

Routine UI/feature/docs/config PRs never qualify — the checklist pass is
their review.

Trigger it per environment.md, then poll for its review with short
foreground checks (macOS QoS kills long watchers).

Triage findings like checklist findings: verify each against the code before
acting — a bot's confidence is not evidence — route real fixes to the
implementer, then close each thread per §Review threads. Re-trigger only
when a fix round materially changed risk-bearing code; incremental-review
and effort-routing behavior is bot-specific (noted in environment.md).

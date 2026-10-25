---
name: delegation-briefs
description: "Write the brief that hands work to an agent that did not share
your conversation — a fresh subagent, a worktree-isolated worker, or a
delegated CLI agent in another process — and fix the report shape its
result comes back in. Covers reading order and scope fence, the read fence,
explicit role assignment, the bounded initiative line, the verification
floor, 'done means' as invariants plus exact commands, the leaf rule, the
~40-line report head, two-brief bug fixes, and fix rounds as briefs; with a
per-transport annex. Use PROACTIVELY whenever you are about to delegate
implementation, investigation, or review to any agent, whichever transport
carries it. Never activate in a session executing an assigned brief from an
orchestrator: a worker is a leaf and writes no briefs."
---

# Delegation briefs

The brief plus the worktree is the delegate's whole world. It did not see
your conversation, the forks you rejected, or the files you read; what the
brief does not say, the delegate will decide for itself — and actions
carry implicit decisions. So the brief carries the decisions and the
evidence that settled them, fixes the shape the result comes back in, and
assigns roles explicitly instead of hoping the delegate infers them.

Write every brief to a file and send its **path** with one line: "Read
`<path>` in full and execute it exactly as written; it is your task brief
from the orchestrator." Inline only short prompts and fix rounds. The
report comes back as a file too; you read its head, never a transcript.

## Load-bearing parts — every fresh brief has all of them

- **Task, tree, base.** The task in one line; the absolute worktree path
  and branch; the base SHA; any starting revision that matters (a
  committed red test; prior merged work the task builds on).
- **Role assignment, not a fiction about other agents.** Repo rules tell
  a standalone agent to commit, open PRs, run guardians, spawn subagents.
  The brief does not pretend those rules carry an exception; it assigns
  the roles for this run — the orchestrator owns worktree preparation,
  every version-control and PR operation, delegation, guardian and
  checklist execution, and acceptance; the delegate implements, runs the
  named checks, and reports — and says these assignments supersede
  conflicting *workflow* directions while coding, security, and domain
  rules still apply in full. Models that follow long instructions well
  are the most sensitive to two rules that conflict; resolve the conflict
  in the brief, never leave it to the model.
- **No-git line.** Do not commit, stage, or push; leave the tree dirty for
  review. Read-only git on its own tree is fine.
- **Leaf rule with the valve.** Do not spawn, delegate, or activate any
  delegation or orchestration skill or protocol, including one that would
  otherwise apply to a task this size; if a split would genuinely help,
  propose it and the orchestrator decides and provisions it.
- **Read fence.** The delegate reads its worktree, installed dependencies,
  the repo's rules and skills, the files the brief names, and the
  ledger's status matrix as read-only shared context — never the
  orchestrator's conversation or session files, a peer's output, or a
  brief or report this brief did not name. The fence is on coordination
  artifacts, not on source: a fence that makes every import a callback
  defeats the dependency-scout rule. A missing coordination artifact is a
  question, not a read.
- **Reading order** (repo rules → plan or ADR → named key files with
  symbol or line hints) and an explicit **scope fence** ("do NOT touch X —
  that is a later slice").
- **One bounded initiative line.** Proceed autonomously on routine
  choices within scope, including copy or label changes the brief
  specifies. Batch questions for named ambiguities, any scope or
  invariant change, missing authority, new user-facing product or domain
  semantics the brief does not specify (a new label, a visible enum
  member, what a term means to users), and blockers; keep working on
  independent parts while waiting. Newer models ask where older ones
  assumed — say which you want.
- **Callback channel and shape.** How to reach you (the transport annex
  says what the channel is); blockers and decisions only, never progress
  narration; every open question batched into one message of at most ~15
  lines and ~200 words — the decision needed, the recommendation, the
  `path:line` behind it, what waiting costs — anything longer in a file
  the message names.
- **Decision-heavy work:** "if the contract or shape is ambiguous, propose
  it to me BEFORE implementing." A two-minute exchange beats a rewrite.
- **Verification floor:** the repo's commit-free gate runner plus only
  what it does not cover, run once; repeat or broaden only for changed
  code, a new failure, or a named concern. Focused local diagnostics (a
  repro, a dependency experiment) are expected, not something to ask
  about.
- **"Done means":** the invariants that must hold plus the exact commands
  whose green output proves them. Acceptance is on evidence, never
  narrative. State plainly what cannot be verified in the delegate's
  environment; never approximate it.
- **Evidence settles claims.** "If you think this instruction is wrong,
  answer with evidence rather than changing the code." A hedge is an
  unsettled claim; ask for a demonstration.
- **Security-sensitive work:** name the non-negotiable invariant and add
  "if a step seems to require violating it, STOP and message me — the
  design is wrong, not the invariant."
- **UI-facing work**, only if the brief assigns capture: screenshots or
  preview URL to a named directory, listed in the report; the verdict
  belongs to the named judge, captures are evidence, never
  self-certification.
- **Report format** (below), to a named `$REPORT_FILE`, plus one line
  back when it is ready: the path.

## Report shape — fixed by the brief, read by the head

Two parts separated by a line containing only `---`. Above it, at most
~40 lines: worktree and base revision; files changed; contract or design
decisions made; one line per verification command — the exact command,
its exit status or `not run`, the verdict in the repo's vocabulary, the
path of its full log; what could not be verified here; any drift between
the plan and the code. Below it, only for failing checks: the first
relevant error and at most ~80 surrounding lines. Never a whole run; the
log path is the evidence.

Reading it: head once; annex only for a red gate or a claim you are
adjudicating. `not run` is its own state. Check the head's deterministic
facts directly — exit codes, `not run` lines, that each named log exists
and is non-empty — never by reading narrative. Delegates report drift
honestly only when the brief demands the drift section; always demand it.

## Bug fixes are two briefs

The first writes a failing test that reproduces the report and stops; you
observe it red, commit the test yourself, and record that red SHA. The
second fixes, with every test file in its scope fence: "do NOT edit any
test file; the failing test at revision `<sha>` is the proof and stays as
written — if it seems wrong, message me with evidence instead of changing
it." Acceptance for the second is green **plus** an empty test-file diff
against the recorded revision; the check is on the diff, so it binds a
delegate of any vendor without relying on its harness's hooks. A fix that
touched the test has shown only that the test now agrees with the code.
The new test still gets the mutation check at review.

## Fix rounds and re-reviews are briefs too

Reuse the channel, not a new brief file: the failing gate and its first
relevant error verbatim, what must NOT change (don't weaken a proof, touch
baselines, cast unsafely), and the re-run in the same report shape
(verdict line plus log path). Nothing reviews a fix round, so it carries
the settled decisions *and the evidence that settled them* forward, and
states that settled decisions may be refuted with evidence but not merely
re-raised. When a gate flags something, first ask whether the flagged
thing should exist at all.

## Reviewer and scout briefs

A read-only brief keeps the role, leaf, read-fence, callback, and report
parts; drops the verification floor; and adds "report only actionable
findings with `file:line`, or 'no findings'; do NOT edit anything, even
if a checklist tells its reader to auto-fix." A reviewer is never shown
the implementer's report, self-assessment, or output; independence is
kept by withholding the self-assessment, not the requirement. The review
protocol itself is the `independent-review` skill.

## Template

Replace bracketed parts; delete sections that do not apply; keep the
role, no-git, leaf, read-fence, initiative, done-means, and report parts
in every fresh brief.

```text
Your task: implement [task]. Worktree: [absolute path] (branch [branch]);
task base: [base SHA][; current starting revision: [SHA]][; it already
contains [prior merged work]].

Roles for this assignment, which supersede conflicting workflow directions
in the repo's rules files and in your own harness's rules (coding,
security, and domain rules still apply in full): the orchestrator
([overseer name]) owns worktree preparation, every version-control
mutation and PR operation, delegation, guardian and checklist execution,
and acceptance. You implement in the supplied worktree, run the checks
named below, and report; read-only git queries on your own tree are yours.
So: do NOT commit, stage, or push anything — leave the working tree dirty
for review; do NOT spawn or delegate to other agents, subagents, or
CLI-launched workers, through any native collaboration feature or
otherwise; do NOT activate any delegation or orchestration skill or
protocol, including one that would otherwise apply to a task this size —
you are a worker executing a brief, a leaf. If a split or parallel
investigation would genuinely help, propose it to me and I will decide and
provision it. Reading a guardian's rules to write to the house standard is
expected; invoking guardian or review skills is mine and runs after your
report.

Proceed autonomously on routine implementation choices within the scope
below, including any copy or label changes this brief specifies. Batch
questions for the named ambiguities, any scope or invariant change,
missing authority, any new user-facing product or domain semantics this
brief does not specify, and blockers — and keep working on independent
parts while you wait.

If you need a decision, clarification, or hit a blocker: [callback
channel, from the transport annex]. Blockers and decisions only, not
progress narration. One message carrying every open question, under ~15
lines and ~200 words: the decision needed, your recommendation, the
path:line behind it, what waiting costs. Anything longer goes in a file
under [scratch dir] and the message names the path.

Read freely within your worktree, its installed dependencies, the repo's
rules and skills, and the files named below; the status matrix in [ledger
path] is read-only shared context. Do NOT read the orchestrator's
conversation, any agent harness's session files, or another agent's
output, brief, or report unless this brief names it. A coordination
artifact that is not here is a question for me, not a read.

Read first, in this order: [repo rules file], [plan/ADR], [named key files
with symbols/line hints].

Then execute exactly [scope]:
1. [step]
2. [step]

Do NOT touch [out-of-scope areas]. [Fix step of a bug fix: Do NOT edit any
test file; the failing test at revision [sha] is the proof and stays as
written — if it seems wrong, message me with evidence instead of changing
it.] If [known ambiguity] is unclear, propose the shape to me BEFORE
implementing.

The commands under "Done means" are the required acceptance checks — run
them once; repeat or broaden only for changed code, a new failure, or a
concern you name in the report. Focused local diagnostics to establish
in-scope behaviour are expected.

[Security-sensitive: the non-negotiable invariant; "if a step seems to
require violating it, STOP and message me — the design is wrong, not the
invariant."]

[UI-facing, only if capture is assigned: screenshots to [dir] and/or the
preview URL, paths listed in your report; the verdict belongs to [named
judge].]

Done means: [invariants] AND [the repo's commit-free gate runner plus only
what it does not cover] green. State clearly what CANNOT be verified in
this environment; do not approximate it. If satisfying an invariant seems
to require changing the agreed shape, propose the amendment BEFORE
implementing it.

When done, write your report to [$REPORT_FILE] and message me that it is
ready (one line: the path). Two parts separated by a line containing only
`---`. Above it, at most ~40 lines: worktree and base revision, files
changed, [decisions made], one line per verification command (exact
command, exit status or `not run`, verdict, full-log path under [log
dir]), what could not be verified here, and any plan/code drift. Below
it, only for failing checks: the first relevant error and at most ~80
surrounding lines. Never paste a whole run.
```

## Transport annex

**Native subagent of your own harness.** The delegation message is the
one line pointing at the brief path. A fresh subagent sees its system
prompt, the repo's rules file, a git status snapshot, and nothing of your
conversation; a fork sees everything you saw and is the wrong choice for
an independent reviewer. Give a writing subagent its own worktree
(the harness's isolation option) so one-writer-per-worktree holds. The
callback channel is its final result or a message to you; keep the leaf
rule in the brief even where the harness caps nesting, since caps are
configuration and the brief is the contract. Have the result be the
report path, not a narrative. Do not name a subagent you will not message
later: in some harnesses a named subagent spawns as a teammate.

**Delegated CLI agent in another process** (a terminal pane). The brief
goes by path through the pane's prompt command — inlined briefs fail
silently past a few KB on some CLIs, and tool hooks may regex the literal
command string, so never write commit or push phrasing beyond the standard
no-git line. The callback channel is the pane's message-the-orchestrator
command, with your agent name. First callbacks may hit the CLI's approval
dialog; approve with the persistent option. Pane mechanics, model and
effort pins at start, lifecycle, and rotation are the transport skill's
(`herdr-delegates` for Herdr).

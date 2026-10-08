# Phase: design — task fit, task shape, briefs

Read with SKILL.md before the contract or any brief.

## Task fit — decide after recon, from what the recon showed

§Task shape bounds the top; this bounds the bottom: delegation's fixed
overhead (brief, report round-trips, worktree, pane) can dominate a
small, well-specified change. SKILL.md §Routing runs first — a worker
stops there, an explicit "do it yourself" or "delegate this" decides the
question, and a review-only request never reaches this gate.

**Do not size up front, and do not size by label.** "Quick fix",
"hotfix", and "one file" describe the request, not the work; a
pre-recon guess is a self-prediction at the moment you know least. Decide
at the design gate's recon pass, from observed signals.

Delegate if **any** holds: two-plus disjoint file sets could run in
parallel; more than one landable milestone; a migration, sweep, or audit
across many call sites; the surface to read exceeds what you want
resident in your own context; a plan or ADR already breaks it into
phases.

Implement directly if **all** hold: one app or package, single-digit
file count, nothing shardable, no migration character, and recon already
put the code in front of you. A deliverable that is prose whose
content is your own judgment — a policy, a design note, a review — is
also direct: writing it is the judgment. Otherwise — or when the signals conflict —
delegate: a wasted small delegation costs latency; an undelegated large
task risks a blown context and an abandoned run. Urgency is not a
signal either way; an urgent fix gets the same recon, just a shorter one.

This bound gates *implementation* only, never read-only fan-out: an
adjudication-shaped task (compare N implementations, audit N call sites)
still fans out the read. Nor does the verdict switch off the design gate
or the review half (phase-review.md) — typing the code yourself changes
who implements the frame, not whether the frame is right. The specific
failure the gate exists for: one agent pre-decides a fork, gets no
critique, implements its own answer faithfully, and every gate goes
green. Implementing directly also keeps the repo's isolation rules: its
worktree and branch convention, never the user's checkout unless the
repo says so (SKILL.md §Routing).

Record the verdict as one ledger line naming the deciding signal. If it
takes more than a line to settle, delegate.

## Task shape — graphs, milestones, gates

Work runs as a layered graph: fan out a layer, collect at a **gate**,
judge, then brief the next layer — or stop.

- **Up-front (the contract the human accepts once):** goals, a
  feasibility scout pass under real uncertainty, the layer skeleton
  ("scouts → design gate → 2 implementers → review gate → integration"),
  explicit stop criteria ("if the migration touches >N call sites, stop
  and report").
- **The design gate is the default first gate**, sized to the open
  questions: a direct change with no open fork needs only the frame line
  in the ledger, no reviewer fan-out. Layer 1's brief carries
  the design; nothing downstream corrects a wrong frame. Fan the fast
  reviewer over the open questions, one agent per question, then state the
  frame in the ledger: what the task asks, each pre-decided decision
  **with its supporting `file:line`**, the forks and why the loser lost,
  the scope fence. A decision without a citation is a question — send it
  to a scout, the reviewer, or the human. Then hand the frame itself to
  the fast reviewer — *"which of these decisions is wrong or
  under-considered, and what did I not consider?"* — before any
  implementation starts. If the repo ships a plan-review skill, run it on
  the frame here too.
- **Point a scout at the dependency, not just your own code:** someone
  reads the source or typings of what you build on — what it guarantees,
  its normalisation and removal semantics, what hooks it already exposes,
  whether it solves this outright. A frame built on an assumed library
  contract passes every gate; the hand-rolled substitute looks correct in
  review because the reviewer shares the assumption.
- **Write briefs just-in-time**, after judging the previous layer at its
  gate — briefs written earlier are fiction. Gates are where re-planning
  and killing happen; a gate passed mechanically isn't a gate.
- **Results travel by file:** briefs go by path, reports to a named
  `$REPORT_FILE`, the next brief says "read `<report>` first". You judge
  reports; you don't ferry them through your context.
- **Sizing:** each node's diff reviewable in one sitting; each gate lands
  a reviewable artifact (merged PR or integration-branch commit), not a
  pile of dirty worktrees. Width stays 2–3 implementers (reviews
  serialize through you — phase-execution.md §Parallel implementers);
  graphs extend depth, not width. What can't be a sequence of landable
  gates is a multi-session project — plan it as one.

## Reasoning effort — set per brief, escalated on evidence

The implementer's reasoning effort is pinned at session start (the ladder
and the exact args per CLI in environment.md), so it is decided where the
brief is written, per node. Default is the environment's **default pin**.
Raise to the **escalation pin** when the brief carries any of:

- security or authorization semantics;
- concurrency, ordering, or cache-coherence invariants;
- data integrity and irreversible transitions — deletion, migration
  rollback, idempotent replay, deploy-ordering compatibility — even when
  the edit itself is mechanically uniform;
- a contract two parallel implementers must meet;
- a named ambiguity where the implementer must propose the shape first;
- a migration whose call sites are not mechanically identical;
- a second fix round on the same node after a red gate, once you have
  ruled out the causes more thinking cannot fix — a wrong frame, stale
  evidence, an environment failure (missing secrets, an inert vendor
  group, an unavailable service). Diagnose first; escalate for unresolved
  reasoning only.

When a classifier is configured, its effort-signal set (classifier.md)
is a cross-check on this list, never a substitute: a signal it raises that
you had not flagged sends you back to the frame; a signal it misses that
you flagged still escalates.

Keep the default for well-specified slices whose frame cites `file:line`,
mechanical sweeps, test-first briefs, docs, and fix rounds that name the
exact error. Never size by line count or repository size. The default is
a measured policy, not a documented equivalence with the previous pin:
record effort, CLI version, task type, fix rounds, and callback causes per
node so the run report can compare like with like. Record the pin in the
status matrix row and the ledger's brief entry. A mid-task escalation is a
rotation onto the same worktree
(`bin/rotate-implementer.sh` with the higher pin — a rotation without the
pin silently drops to the config default) and the re-brief says "read
your previous report first". Never a level that enables the CLI's own
delegation or multi-agent mode — it breaks the leaf rule; environment.md
names any such level so it is never chosen by accident.

## Briefs

Use `references/brief-template.md`. The load-bearing parts:

- **Reading order** (repo rules → plan/ADR → named key files) and an
  explicit scope fence ("do NOT touch X — that is a later slice").
- **Read fence** (SKILL.md §Transcript boundary): the delegate reads its
  worktree, dependencies, repo rules, the ledger's status matrix, and the
  files the brief names — never the overseer's pane or session files, a
  peer's pane, or a brief or report the brief did not name. The fence is
  on coordination artifacts, not on source; a fence that makes every
  import a callback defeats the dependency-scout rule above.
- **Role assignment, not a fiction about other agents.** Repo rules tell
  a standalone agent to commit, open PRs, run guardians, and spawn
  subagents. The brief does not pretend those rules carry an exception;
  it assigns the roles explicitly for this run — the overseer owns
  worktree preparation, every version-control and PR operation,
  delegation, guardian and checklist execution, and acceptance; the
  implementer implements, runs the named checks, and reports — and says
  these assignments supersede conflicting *workflow* directions while
  coding, security, and domain rules still apply. Reading a guardian's
  rules to write to the house standard is fine; invoking the guardian is
  the overseer's. Models that follow long instructions well are also the
  most sensitive to two rules that conflict — resolve the conflict in the
  brief, never leave it to the model.
- **One bounded initiative line** in every fresh brief: proceed on routine
  choices within scope — including copy or label changes the brief
  specifies; batch questions for named ambiguities, scope or invariant
  changes, missing authority, new user-facing product or domain semantics
  the brief does not specify, and blockers; keep working on independent
  parts while waiting. Newer models ask where older ones assumed — say
  which you want. The callback screen (classifier.md) asks about exactly
  this line, so keep the two worded alike.
- **Verification floor**, including the repo's commit-free gate runner
  (review-checklists.md) — without it, gate failures surface at your
  commit step and cost a round-trip each.
- **"Done means":** the invariants plus the exact commands whose green
  output proves them. Acceptance is on evidence, never narrative; the
  report carries each check's exit status and log path and you re-run
  the gates before committing.
- **Leaf rule** with the escalation valve (standard line in the template).
- **Report format:** files changed, one line per check (command, exit
  status or `not run`, verdict, log path), what cannot be verified in the
  sandbox (said plainly, not approximated), and plan/code drift —
  implementers report drift honestly only when asked
  (agent-trust-profiles.md). The shape is SKILL.md §Token economy
  §Report shape: a ~40-line head you always read, a `---` marker, then a
  bounded annex you open only on a red gate; full logs on disk.
- Decision-heavy work: *"if the contract/shape is ambiguous, propose it
  to me BEFORE implementing."* A two-minute exchange beats a rewrite.
- **Evidence settles claims, not just gates.** Every behavioural claim
  the work rests on is settled by whoever makes it — by reading the
  installed source or making it fail. Ask for demonstrations, not
  opinions: *"if you think this instruction is wrong, answer with
  evidence rather than changing the code."* A hedge ("not sure this
  always mounts after the cache is warm") is an unsettled claim — the
  highest-yield thing a reviewer says. Settle it.
- **Bug fixes are two briefs.** The first writes a failing test that
  reproduces the report and stops; you observe it red, commit the test
  yourself (you own git — a dirty tree's revision does not pin an
  uncommitted test), and record that red SHA in the ledger. The second
  fixes, with every test file
  in its scope fence. Acceptance for the second is green **plus** an
  empty test-file diff against the recorded revision — the check is on
  the diff, so it binds an implementer of any vendor without relying on
  that CLI's hooks. A fix that needed to touch the test has shown only
  that the test now agrees with the code; send it back with the test
  restored. Delegate-written tests still get the mutation check
  (phase-review.md §Verification ownership) — red-then-green proves the
  test sees the bug, not that it pins the invariant.
- **Fix rounds and re-reviews are briefs**, bound by all of the above —
  and nothing reviews them, so they carry the settled decisions *and the
  evidence that settled them* forward, stating that settled decisions may
  be refuted with evidence but not merely re-raised.

# Phase: design — task fit, task shape, briefs

Read with SKILL.md before the contract or any brief.

## Task fit — check the lower bound, after recon

§Task shape bounds the top; this bounds the bottom: delegation's fixed
overhead (brief, report round-trips, worktree, pane) dominates a small,
well-specified change.

**Do not size up front.** Pre-recon sizing is a self-prediction at the
moment you know least, made by the same judgment that writes the frame,
under a standing pro-delegation default — it gets rationalised, not
evaluated. Decide at the design gate's recon pass, from observed signals.

Delegate if **any** holds: two-plus disjoint file sets could run in
parallel; more than one landable milestone; a migration, sweep, or audit
across many call sites; the surface to read exceeds what you want resident
in your own context; a plan or ADR already breaks it into phases.

Implement directly only if **all** hold: one app or package, single-digit
file count, nothing shardable, no migration character, and recon already
put the code in front of you. Ambiguous → delegate: a wasted small
delegation costs latency; an undelegated large task risks a blown context
and an abandoned run.

This bound gates *implementation* only — never read-only fan-out (scouts,
triage, checklist passes carry no brief/worktree/pane overhead), so
"implement directly" never means "read everything yourself": an
adjudication-shaped task (compare N implementations, audit N call sites)
still fans out the read. Nor does the verdict switch off the review half
(phase-review.md) or the design gate — typing the code yourself changes
who implements the frame, not whether the frame is right. The specific
failure the gate exists for: one agent pre-decides a fork, gets no
critique, implements its own answer faithfully, and every gate goes green.

Record the verdict as one ledger line naming the deciding signal. If it
takes more than a line to settle, that is the signal: delegate.

## Task shape — graphs, milestones, gates

Work runs as a layered graph: fan out a layer, collect at a **gate**,
judge, then brief the next layer — or stop.

- **Up-front (the contract the human accepts once):** goals, a
  feasibility scout pass under real uncertainty, the layer skeleton
  ("scouts → design gate → 2 implementers → review gate → integration"),
  explicit stop criteria ("if the migration touches >N call sites, stop
  and report").
- **The design gate is the default first gate.** Layer 1's brief carries
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

## Briefs

Use `references/brief-template.md`. The load-bearing parts:

- **Reading order** (repo rules → plan/ADR → named key files) and an
  explicit scope fence ("do NOT touch X — that is a later slice").
- **Verification floor**, including the repo's commit-free gate runner
  (review-checklists.md) — without it, gate failures surface at your
  commit step and cost a round-trip each.
- **"Done means":** the invariants plus the exact commands whose green
  output proves them. Acceptance is on evidence, never narrative; the
  report carries the output verbatim and you re-run the gates before
  committing.
- **Leaf rule** with the escalation valve (standard line in the template).
- **Report format:** files changed, verification output verbatim, what
  cannot be verified in the sandbox (said plainly, not approximated), and
  plan/code drift — implementers report drift honestly only when asked
  (agent-trust-profiles.md).
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
  reproduces the report and stops; you observe it red and record the
  tree's revision in the ledger. The second fixes, with every test file
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

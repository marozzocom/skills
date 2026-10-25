# Phase: design — load the design-gate skill, then write briefs

Read with SKILL.md before the contract or any brief. The design half of
this protocol lives in the **`design-gate`** skill, installed alongside
this one: invoke it (the Skill tool, or read
`${CLAUDE_SKILL_DIR}/../design-gate/SKILL.md`) and run it in full —
recon, the cited frame, the independent critique, the task shape and stop
criteria, the contract, the per-node transport choice, and the per-node
reasoning effort. SKILL.md §Routing runs first: a worker stops there, an
explicit "do it yourself" or "delegate this" is recorded as the transport
signal, and a review-only request never reaches the gate.

What this protocol adds for a delegated run:

- **The `delegate` transport is a pane.** Its fixed overhead — brief file,
  report round-trips, worktree, pane start, approval dialogs — is what
  design-gate §6 weighs against a one-node task. Its advantages here are
  the ones only an external process gives: a different vendor's model as
  implementer or reviewer, a billing path cheaper than yours, a run that
  spans sessions on the ledger, and a pane the human can read and steer.
  A `native` node is your own harness's subagent; a `delegate` node is
  briefed per §Briefs below.
- **Critique and scouts fan out on the fast reviewer** (phase-execution.md
  §Fast reviewer), one pane per open question, read-only. The dependency
  scout is a delegate too: it runs in parallel and spends none of your
  context.
- **Effort is a start-time pin.** The ladder and the exact args per CLI
  are in environment.md; design-gate §7 decides the level, this protocol
  pins it when the agent starts (phase-execution.md §Starting an
  implementer) and records it in the status matrix row and the ledger's
  brief entry. A mid-task escalation is a rotation onto the same worktree
  (`bin/rotate-implementer.sh` with the higher pin — a rotation without
  the pin silently drops to the config default) and the re-brief says
  "read your previous report first". Never a level that enables the CLI's
  own delegation or multi-agent mode — it breaks the leaf rule;
  environment.md names any such level so it is never chosen by accident.
  A configured classifier's effort-signal set (classifier.md) is a
  cross-check on design-gate §7's list, never a substitute.
- **Record per node, every node:** one ledger line with transport,
  deciding signal, and effort pin (`direct` nodes included — the run
  report's per-node table is rendered from these lines, and a missing row
  is a missing data point). Record effort, CLI version, task type, fix
  rounds, and callback causes per node so the report compares like with
  like.
- **Width.** Two or three concurrent implementer panes in practice;
  reviews serialize through you (phase-execution.md §Parallel
  implementers). Graphs extend depth, not width.

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
  (independent-review §Verification ownership) — red-then-green proves the
  test sees the bug, not that it pins the invariant.
- **Fix rounds and re-reviews are briefs**, bound by all of the above —
  and nothing reviews them, so they carry the settled decisions *and the
  evidence that settled them* forward, stating that settled decisions may
  be refuted with evidence but not merely re-raised.

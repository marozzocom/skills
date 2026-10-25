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
  pins it when the agent starts (herdr-delegates §Starting an
  agent) and records it in the status matrix row and the ledger's
  brief entry. A mid-task escalation is a rotation onto the same worktree
  (herdr-delegates `rotate-implementer.sh` with the higher pin — a rotation without
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
  reviews serialize through you (herdr-delegates §Parallel
  implementers). Graphs extend depth, not width.

## Briefs — load the delegation-briefs skill

The brief — load-bearing parts, template, report shape, two-brief bug
fixes, fix rounds and re-reviews as briefs — is the **`delegation-briefs`**
skill (`${CLAUDE_SKILL_DIR}/../delegation-briefs/SKILL.md`). For a pane
delegate, `references/brief-template.md` supplies the Herdr delivery and
callback lines and the oracle consult. Two things this protocol insists
on when filling the template:

- the **verification floor** names the repo's commit-free gate runner
  from `review-checklists.md` (independent-review) — without it, gate
  failures surface at your commit step and cost a round-trip each;
- the **initiative line** is worded like the classifier's callback screen
  (classifier.md), since that checkpoint asks about exactly this line.

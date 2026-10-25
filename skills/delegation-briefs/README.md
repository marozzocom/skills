# delegation-briefs — orientation

For humans and skill-editing sessions; nothing here loads at runtime. The
agent entrypoint is [SKILL.md](SKILL.md).

## What it is

How to hand work to an agent that did not share your conversation, on any
transport: a native subagent, a worktree-isolated worker, or a delegated
CLI agent in its own process. Extracted from `delegated-implementation`
(migration step 4 of its
[decomposition proposal](../delegated-implementation/docs/decomposition-proposal.md))
because every vendor's guidance converges on the same lesson — the
delegate needs an objective and an output format — and the parts of a
good brief that are not transport-specific are most of it.

The skill fixes the brief's load-bearing parts, the ~40-line report head
the result comes back in, two-brief bug fixes, fix rounds as briefs, and
a short annex per transport. Pane mechanics live in `herdr-delegates`;
the review protocol lives in `independent-review`; the decision of
whether and what to delegate lives in `design-gate`.

## Why the rules are what they are

- **Role assignment over exceptions.** Repo rules tell a standalone agent
  to commit and spawn. A brief that pretends those rules carry an
  exception leaves the conflict to the model; models that follow long
  instructions well are the most sensitive to two rules that conflict.
- **The read fence protects authority, not secrecy.** The orchestrator's
  conversation holds the human's words, rejected forks, and unadjudicated
  claims; a delegate that reads it acts on all three as instruction.
- **Report head, not transcript.** The orchestrator's context is the
  scarcest resource in the run; a fixed head with exit codes and log paths
  is what lets it judge without ingesting.
- **Two-brief bug fixes.** A fix that needed to touch the test proved only
  that the test agrees with the code. The empty test-file diff is a check
  on the diff, so it binds any vendor's agent without relying on hooks.
- **Drift only when asked.** Observed across agents: plan/code drift is
  reported honestly when the report format demands it and not otherwise.

## Install

```bash
ln -s "$(pwd)/skills/skills/delegation-briefs" ~/.claude/skills/
/bin/bash tests/validate-skill.sh
```

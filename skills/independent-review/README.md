# independent-review — orientation

For humans and skill-editing sessions; nothing here loads at runtime. The
agent entrypoint is [SKILL.md](SKILL.md).

## What it is

The review half of an implementation run, as its own skill: independent
verification and tiered review of a diff before it is committed, whoever
wrote it. Extracted from `implementation-orchestration` (migration step 2 of
its [decomposition proposal](../implementation-orchestration/docs/decomposition-proposal.md))
because the review half is the part that measurably carried its weight
and the part that applies on every implementation path — direct, native
subagent, or delegated CLI agent.

One rule governs the rest: the author of a diff never reviews it, and the
reviewer never shares the author's context. On risk-bearing surfaces the
reviewer also comes from a different model family than the implementer.

## Where things live

| File | Holds |
|---|---|
| [SKILL.md](SKILL.md) | who reviews, verification ownership, inventory → triage → deep read, reviewer briefs, checklists, drift, fix rounds, threads, previews, external bot |
| `references/review-checklists.md` | local, gitignored: per-repo checklists, escalation domains, review conventions, landing grants and safe sets, verification matrix. Create from [the template](references/review-checklists.template.md). |
| `references/agent-trust-profiles.md` | local, gitignored: verified per-agent behavior. Create from [the template](references/agent-trust-profiles.template.md). |
| `bin/run-gates.sh` | acceptance re-run: one verdict line per gate, failure tails, logs on disk |
| `bin/review-inventory.sh` | every path changed since the base: committed, staged, unstaged, untracked |
| `bin/diff-hunks.sh` | only the hunks a triage range names; exits 3 when nothing matches |
| `bin/resolve-thread.sh` | reply to a review comment and resolve its thread in one call |
| `tests/` | offline tests; `validate-skill.sh` checks structure and portability |

## Install

```bash
ln -s "$(pwd)/skills/skills/independent-review" ~/.claude/skills/
cd skills/skills/independent-review/references
cp review-checklists.template.md review-checklists.md
cp agent-trust-profiles.template.md agent-trust-profiles.md
```

Requires `git`, `gh` (authenticated for the repos you review in), and the
system `bash` (3.2 on macOS). Install alongside `implementation-orchestration`
when you use that skill: it loads this one at the first done-report and
calls these helpers by `${CLAUDE_SKILL_DIR}/../independent-review/bin/`.

Validate:

```bash
/bin/bash tests/validate-skill.sh
/bin/bash tests/run.sh
```

## Why the rules are what they are

- **Author never reviews.** An agent testing its own diff pulls toward
  green; a reviewer that has seen the author's reasoning inherits its
  assumptions. Independence is kept by withholding the self-assessment,
  not the requirement.
- **Different family on risk-bearing code.** Same-family reviewers share
  training-correlated blind spots. The claim is argued and anecdotally
  supported, not measured in a controlled study; the per-node outcome
  rows in the orchestration skill's run report exist to measure it.
- **Triage may escalate, never demote.** A label cannot protect a file you
  never learn exists, and a reviewer's "routine" is cheaper to overrule
  than its "risk-bearing" is to miss.
- **Mutation check on new tests.** Red-then-green proves the test sees
  the bug it was written for, not that it pins the invariant.

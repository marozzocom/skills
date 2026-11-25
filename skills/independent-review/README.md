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
reviewer preferably comes from a different vendor than the implementer.

## Where things live

| File | Holds |
|---|---|
| [SKILL.md](SKILL.md) | who reviews, verification ownership, inventory → triage → deep read, reviewer briefs, checklists, drift, fix rounds, threads, previews, external bot |
| `references/review-checklists.md` | local, gitignored: per-repo checklists, escalation domains, review conventions, landing grants and safe sets, verification matrix. Create from [the template](references/review-checklists.template.md). |
| `references/agent-trust-profiles.md` | local, gitignored: verified per-agent behavior. Create from [the template](references/agent-trust-profiles.template.md). |
| `bin/run-gates.sh` | acceptance re-run: one verdict line per gate with its seconds, failure tails, logs on disk; optional lock and timing record |
| `bin/with-lock.sh` | run a command under a machine-wide named lock, so heavy runs queue across sessions and agents; max hold, holder liveness, `--status` |
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
- **Different vendor preferred on risk-bearing code.** Reviewers sharing
  the author's training share correlated blind spots; a same-model
  reviewer with an empty context still catches what the author's own
  context hides, so it is the fallback, not a violation. The claim is argued and anecdotally
  supported, not measured in a controlled study; the per-node outcome
  rows in the orchestration skill's run report exist to measure it.
- **Triage may escalate, never demote.** A label cannot protect a file you
  never learn exists, and a reviewer's "routine" is cheaper to overrule
  than its "risk-bearing" is to miss.
- **Locks have a maximum hold, enforced by the holder.** A hung heavy run
  used to keep every other session queued indefinitely. `run-gates.sh`
  now holds its locks at most `WITH_LOCK_MAX_HOLD` seconds (default 3600,
  `0` disables; `with-lock.sh --max-hold` elsewhere). The deadline is an
  absolute time exported as `WITH_LOCK_DEADLINE`, so a lock taken inside a
  gate inherits it, and inner holders kill first (the wait before KILL
  grows by `WITH_LOCK_DEPTH_STEP` per level outward). Only the holder's
  supervisor ends the command, and only after its whole process group has
  exited is the kernel lock released: waiters never unlink a lock or
  bypass it, so two holders never overlap. `WITH_LOCK_KILL_GRACE` (default
  5 seconds) is the TERM-to-KILL grace; give `desktop` runs more when a
  GUI suite needs time to close, on the outermost call
  (`RUN_GATES_LOCK=heavy,desktop WITH_LOCK_KILL_GRACE=30`). Each holder
  exports when it will send KILL (`WITH_LOCK_OUTER_KILL_AT`, and
  `WITH_LOCK_OUTER_KILL_WAIT` relative to a TERM), and a nested holder
  clamps its own KILL to before that, whatever grace it was given:
  otherwise an outer KILL could free the outer lock while the inner
  command still ran. `WITH_LOCK_DEPTH_STEP` must be at least 1 with a
  deadline for the same reason.
- **The caller's errexit never reaches the lock scripts.** With
  `SHELLOPTS=errexit` or a `BASH_ENV` that runs `set -e`, the supervisor's
  1-second wait would fail and end it, freeing the lock mid-command. Both
  scripts turn errexit off at once and hand it, with `BASH_ENV` and `ENV`,
  back to the command they run. The cost is one supervisor shell per
  held lock; `kill -9` of that shell frees the lock while the command
  may still run, which `--status` then reports as a warning.
- **Staleness is reported, never acted on by waiters.** The holder samples
  its command's processes (`WITH_LOCK_SAMPLE_INTERVAL`, default 30 s) and
  writes `NAME.meta`; waiters and `with-lock.sh --status NAME` show its
  age, idle time (`STALE` from `WITH_LOCK_STALE_IDLE`, default 300 s) or
  that it waits on another lock. Without `ps` liveness is "uncheckable"
  rather than guessed.
- **Mutation check on new tests.** Red-then-green proves the test sees
  the bug it was written for, not that it pins the invariant.

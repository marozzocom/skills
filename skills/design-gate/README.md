# design-gate — orientation

For humans and skill-editing sessions; nothing here loads at runtime. The
agent entrypoint is [SKILL.md](SKILL.md).

## What it is

The planning half of an implementation run as its own skill: recon, a
cited frame, an independent critique of the frame, the task shape, the
contract, and the per-node transport and effort decisions. Extracted from
`delegated-implementation` (migration step 3 of its
[decomposition proposal](../delegated-implementation/docs/decomposition-proposal.md))
so that the gate runs on every implementation path — direct, native
subagent, or delegated CLI agent — not only inside a delegated run.

It encodes three of the shared charter's principles directly
([vision.md](../delegated-implementation/docs/vision.md) §8–10): a node is
briefed only when what proves it done is already written; human judgment
is scheduled into the graph, not fallen back on; and decisions are taken
where the better option is still available.

## Where things live

| Section | Holds |
|---|---|
| §1 Recon | read before deciding; the dependency scout |
| §2 Frame | decisions with `file:line`, forks, scope fence; decide with options open |
| §3 Critique | a reviewer who did not write the frame |
| §4 Task shape | gates, landable artifacts, depth over width, stop criteria |
| §5 Contract | invariants, verifiability before start, exploratory v0, planned human gates, landing mode |
| §6 Transport | direct / native / delegate per node, from observed signals |
| §7 Effort | per-node reasoning effort and its escalation signals |

No helpers and no local references: everything here is judgment. Where
the orchestration skill is installed, its `environment.md` supplies the
concrete effort ladder and transport mechanics; the landing skill or the
repo's rules supply the landing modes.

## Install

```bash
ln -s "$(pwd)/skills/skills/design-gate" ~/.claude/skills/
/bin/bash tests/validate-skill.sh
```

## Why the rules are what they are

- **Decide after recon, from signals, never by label.** The obvious
  version of the transport gate is "judge up front whether this is big
  enough". That asks for a calibrated self-prediction before the code
  has been read, produced by the same judgment that writes the frame.
  Observable post-recon signals are the only version that decides rather
  than rationalises.
- **Critique by someone else.** The measured failure the gate exists for
  is a frame nobody questioned that every downstream gate then passed.
- **Verifiable before start.** A brief whose "done means" cannot be
  written sends an implementer to discover the spec by building; the
  discovery belongs in a scout.
- **Planned human gates.** A run that reaches the human only when it runs
  out of ideas has already lost the option the human would have chosen.
- **Do not pin design decisions for repeatability.** Two runs on one
  ticket produced two competent, different architectures; the variance
  lives in the frame and is where the search happens. Gate the frame, do
  not script it.

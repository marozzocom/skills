# delegated-implementation — maintainer notes

For humans and skill-editing sessions only. Nothing here is loaded when the
skill runs — operational instructions belong in SKILL.md and references/;
this file holds setup, the roadmap, and design rationale that would
otherwise waste context tokens.

## Setup

The skill reads three local-by-nature reference files that are gitignored
here. Create them from their templates and fill in your stack:

```bash
cd references
cp environment.template.md environment.md
cp review-checklists.template.md review-checklists.md
cp agent-trust-profiles.template.md agent-trust-profiles.md
```

Requires [Herdr](https://herdr.dev/) (the skill checks `HERDR_ENV=1`) and a
companion `herdr` skill covering CLI mechanics — this skill only adds the
orchestration protocol on top. The protocol itself (roles, briefs, gates,
tiered review, verification ownership) is multiplexer-agnostic; adapting
the mechanics to tmux or another multiplexer is possible but not done here.

## Layout

- `SKILL.md` — the generic orchestration protocol. Stack-, org-, and
  machine-agnostic by design; no vendor names in the body (the frontmatter
  keeps "(e.g. Codex, Cursor)" solely as trigger keywords for skill
  routing).
- `references/environment.md` — the concrete stack: which CLI/model fills
  each role, start commands, CLI quirks, org/repo integrations. Porting the
  skill = rewriting the references, never SKILL.md.
- `references/review-checklists.md` — per-repo checklist sources and the
  verification matrix (check → runner → verdict owner → evidence type).
- `references/agent-trust-profiles.md` — per-agent-kind trust calibration
  from empirically verified behavior; new kinds start at zero trust.
- `references/brief-template.md` — the implementer brief skeleton.
- `bin/` — tracked, generic helpers shipped with the skill.
  `rotate-implementer.sh` rotates any Herdr agent onto a new worktree in one
  state-verified step (quit with an escalation ladder → confirmed cd → fresh
  start with your model pin passed after `--`).
- `scripts/` — does not exist here and is gitignored: it is the slot where an
  installer may overlay machine-local helper scripts.

## Roadmap / to evaluate

- **Per-domain judges.** §Verification ownership says the verdict on a
  judgment check stays with "you, or one named judge per domain". The
  per-domain-judge option is permitted but unbuilt — e.g. a
  design-specialized agent owning UI verdicts instead of the orchestrator.
  Build only when a real need shows up; it needs a trust profile, a written
  standard, and a matrix entry before it may own verdicts.
- **Graph/ledger/milestone machinery is design, not yet battle-tested.**
  §Task shape, the ledger, and quiesce→teardown→compact→re-fan-out were
  reasoned out in a 2026-08 design pass, unlike the CLI quirk material,
  which was learned from real failures. Treat the first substantial
  multi-layer run as validation; expect follow-up adjustments.
- **Implementer-internal scouts.** Currently a flat leaf rule: delegates
  never spawn subagents. The considered-and-deferred alternative: allow
  read-only, low-effort scouts inside the implementer's own worktree
  (implementer tokens are flat-rate, so cost is nil). Deferred for
  enforceability — revisit if the leaf rule measurably slows implementers.
- **Reasoning-effort routing per task.** The implementer is pinned at high
  effort unconditionally. Medium may suffice for routine, well-specified
  slices; marginal while mechanical work routes to the fast reviewer, so
  only worth evaluating if implementer throughput or quota becomes a
  bottleneck.
- **Ledger format.** Free-form file today. If runs get long enough that
  resuming from summary+ledger is common, a light structure (per-node
  status table, decision log, amendment log) may earn its keep.
- **Trust-profile decay.** Profiles record verified behavior per CLI/model
  pin; a model swap invalidates them. No mechanism marks entries stale —
  convention is to re-verify after any pin change in environment.md.

## Origins

The orchestration-graph, autonomy-contract, verification-ownership, and
trust-profile sections came out of a design discussion (2026-08) prompted
by eric provencher's "Practical multi-agent orchestration in Codex" article
on Codex Multi-Agent V2. The CLI quirk material predates that and was
learned from real failures.

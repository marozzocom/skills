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

## Per-repo adaptation (once per repository)

Three facts to nail down before the first brief, then record them as an entry
in `references/review-checklists.md`:

1. **Rules file** the implementer reads first — `AGENTS.md`, `CLAUDE.md`,
   `CONTRIBUTING`.
2. **Commit-free gate runner** — one script running lint + type-check + tests
   without committing. If none exists, list the individual commands in every
   brief; otherwise gate failures surface at your commit step and cost a full
   round-trip each.
3. **Worktree convention** — where task worktrees live and how branches are
   named. One task = one worktree = one implementer session, always.

## Anti-goals

- **Do not pin design decisions for repeatability.** Two runs of this
  protocol on one ticket produced two competent but materially different
  architectures, because the orchestrator's unpinned calls are where the
  variance lives. The temptation is to remove the variance by fixing the
  answers in the skill. Resist it: the right answer on those runs was
  repo-specific and only visible after reading the code, and one run found a
  third option the other never generated. A skill that forced one answer
  would lock in the worse answer exactly as easily. Gate the design pass
  (§design gate in SKILL.md) — do not script it. Determinism on a design task
  buys consistency at the price of the search.

- **Do not make §Task fit a capability self-estimate.** The obvious way to
  write that gate is "judge up front whether this task is big enough" — and
  that is the version to avoid. It asks for a calibrated self-prediction
  before the code has been read, produced by the same judgment that writes the
  frame, while a standing default-mode rule says to prefer delegating. Three
  forces all point one way, so the gate would rationalise rather than decide.
  It is written as observable post-recon signals for that reason. If it ever
  starts drifting back toward "is this substantial enough", that is the
  failure mode returning.

## Why §Task fit exists — the measured comparison

One ticket, ~700 lines, single app, well specified, implemented three times:
twice through this protocol and once by the orchestrator model alone with no
delegation. Measured from the session transcripts, priced at list rates:

| | delegated (run 2) | solo (run 3) |
| --- | ---: | ---: |
| Active time | 55 min | 26 min |
| Total tokens | 36.1 M | 20.8 M |
| Orchestrator cost | ~2× | 1× |
| Self-correction rounds | 2 | 0 |

The delegated run also consumed implementer and reviewer budget the table
cannot price, so the real gap is wider. Both passed the same gates
independently re-run; the solo run shipped slightly more tests and found one
in-scope case both delegated runs missed (a raw URL read that neither found,
because both grepped for the framework hook instead of the underlying API).

**What this does and does not establish.** It does not show delegation produces
worse work: the best of the three artifacts was a delegated run, and the spread
*within* the delegated arm exceeded the spread between arms — so with one run
per arm, quality is unresolved. What it does show is that the overhead is real
and, on a task this size, buys no design improvement. Hence a lower bound, not
a discouragement.

Two further readings worth keeping:

- **The review half carried its weight; the delegation half did not.** The
  delegated run's review pass caught a user-visible regression before it
  shipped. The solo run shipped a defect of similar severity, caught only
  because a benchmark existed to diff against. That asymmetry is why §Task fit
  explicitly refuses to gate §Review — the cheap configuration to try next is
  solo implementation plus the centralised review pass.
- **Recon target, not delegation, explained most of the artifact spread.** Both
  the delegated and solo runs spent a similar recon budget; they aimed it
  differently. The solo run spent half of its reading the *dependency's* source
  — serializers, undefined-removal semantics, the decoded-value cache, the
  schema library's generic signature — and every mechanism advantage it held
  traces to a specific one of those reads, including the one in-scope call site
  both delegated runs missed (found by searching for the underlying API rather
  than the framework hook). The delegated run spent the equivalent budget
  authoring the brief, never read the library, and hand-rolled substitutes for
  primitives that already existed. The implementer then faithfully built the
  brief. Nothing in the pipeline created a reason for anyone to read the
  dependency — hence the dependency-scout bullet in §Task shape. Note this cuts
  *for* the protocol: scouts are read-only, parallel and near-free, so the
  delegated path can afford this check more easily than a solo run can.
- **This measured the overhead floor, not the protocol.** The task was one
  node, one layer: no parallel implementers, no milestone gates, no worktree
  isolation for concurrent writers, nothing overflowing a single context. The
  graph machinery remains untested (see the roadmap entry below); a fair test
  needs a task a single context genuinely cannot hold.

## Roadmap / to evaluate

- **Judge-panel the frame, not just the implementation.** SKILL.md names the
  judge-panel pattern but applies it nowhere near the brief, which is where
  the variance actually is. For design-heavy tickets: generate two
  independent frames, score them, synthesize from the winner while grafting
  the runner-up's ideas. The design gate is the cheap version of this (one
  reviewer critiques one frame); the panel is the expensive version and
  unbuilt. Evidence that it would pay: on a same-ticket comparison, one run
  won three of four design forks, and the loser's PR shipped a defect two
  review passes and a mutation test all missed — found only by diffing
  against the other implementation.

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
- **Preview deployments are unmapped, not absent.** §Preview deployments
  expects a per-app opt-in mechanism in `environment.md`. Fill in each app's
  mechanism, URL scheme, and budget the first time you use it. Until an app
  has an entry, treat its UI evidence as local-run screenshots.
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

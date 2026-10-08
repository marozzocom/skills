# delegated-implementation — orientation

For humans and skill-editing sessions. Nothing here is loaded when the
skill runs. Installation and per-repo setup: [SETUP.md](SETUP.md). The
agent entrypoint is [SKILL.md](SKILL.md).

## What it is

A protocol for an orchestrator agent that runs CLI coding agents in
sibling [Herdr](https://herdr.dev/) panes: implementers write code in
their own worktrees, fast reviewers triage and run checklists, an
optional oracle advises on intent, an optional classifier raises
scrutiny. The orchestrator keeps design authority, review, independent
verification, and every git, PR, and merge operation. The protocol is
harness-, vendor-, and model-agnostic; everything local lives in
gitignored reference files created from templates.

## Where things live

| File | Read by | When | Holds |
|---|---|---|---|
| [SKILL.md](SKILL.md) | orchestrator | on activation | routing, roles, guard, contract, context, mesh, helper index |
| [references/phase-design.md](references/phase-design.md) | orchestrator | before the contract | task fit, task shape, effort pins, briefs |
| [references/phase-execution.md](references/phase-execution.md) | orchestrator | first fan-out | agent lifecycle, fast reviewer, parallel implementers |
| [references/phase-review.md](references/phase-review.md) | orchestrator | first done-report | verification ownership, tiered review, checklists, threads |
| [references/phase-landing.md](references/phase-landing.md) | orchestrator | contract and landing | authorization, landing modes, merge policy, closeout |
| [references/classifier.md](references/classifier.md) | orchestrator | when a classifier is pinned | the one classifier policy: checkpoints, helper, recording, experiments |
| [references/classifier/](references/classifier/) | `bin/classify-escalate.sh` | each checkpoint call | versioned question sets |
| [references/brief-template.md](references/brief-template.md) | orchestrator | writing a brief | implementer and oracle brief skeletons |
| [references/run-report.md](references/run-report.md) | orchestrator | closeout | report sections |
| `references/environment.md` | orchestrator | as phases point to it | local stack: CLIs, model pins, commands, quirks, billing, repos |
| `references/review-checklists.md` | orchestrator | review and landing | per-repo checklists, grants, safe-set tables |
| `references/agent-trust-profiles.md` | orchestrator | review | per-agent verified behavior |
| `bin/*.sh` | orchestrator | as SKILL.md §Helpers lists | deterministic helpers; each header comment is its contract |
| `tests/` | maintainers | before every change | offline fixture and mock tests, skill validation |

The three unlinked references are local by nature and gitignored; their
`*.template.md` files are tracked. Model pins and environment details
belong only there.

## Anti-goals

- **Do not pin design decisions for repeatability.** Two runs of this
  protocol on one ticket produced two competent but materially different
  architectures, because the orchestrator's unpinned calls are where the
  variance lives. The temptation is to remove the variance by fixing the
  answers in the skill. Resist it: the right answer on those runs was
  repo-specific and only visible after reading the code, and one run found a
  third option the other never generated. A skill that forced one answer
  would lock in the worse answer exactly as easily. Gate the design pass
  (the design gate in phase-design.md) — do not script it. Determinism on
  a design task buys consistency at the price of the search.

- **Do not make §Task fit (phase-design.md) a capability self-estimate.**
  The obvious way to write that gate is "judge up front whether this task
  is big enough" — and
  that is the version to avoid. It asks for a calibrated self-prediction
  before the code has been read, produced by the same judgment that writes the
  frame, while a standing default-mode rule says to prefer delegating. Three
  forces all point one way, so the gate would rationalise rather than decide.
  It is written as observable post-recon signals for that reason. If it ever
  starts drifting back toward "is this substantial enough", that is the
  failure mode returning.

- **First-run calibration of the effort default.** The 2026-09-06
  implementer-model consultation (the new model reviewing this protocol at
  high effort) endorsed medium as a *trial* default, not an equivalence
  with the previous high pin, and noted the vendor's own migration advice
  is to preserve effort. Treat the first two runs as the measurement: per
  node, effort, fix rounds, callback causes, review burden.
- **Transcript boundary is a rule, not a mechanism.** SKILL.md §Transcript
  boundary forbids delegates reading the overseer's pane and session files,
  and the overseer ingesting delegate transcripts — but Herdr lets any
  agent `agent read` any pane, and the harness's session files are plain
  files in the home directory. Enforcement today is the brief's read fence
  plus the orchestrator's own discipline. If a delegate is ever observed
  acting on something only the overseer's transcript contained, the fix is
  mechanical (a Herdr per-pane read ACL, or session files outside the
  delegate's readable tree), not more prose.

## Why the transcript boundary exists

Two transcripts, two different reasons to keep them apart. The overseer's
context is the scarcest in the mesh and fills from the inside: every pane
read, every pasted test run, every narrated callback is context spent
where a verdict line, a report head, or a file path would have done. So delegate output is *accessible* — the pane, the logs, the
full report tail are all there — but never *broadcast*; it enters only in
the shapes the brief fixed, when the overseer pulls it. For the
delegate's context the concern runs the other way: not cost but
authority. The overseer's transcript holds the human's words, the forks the
overseer rejected, and other delegates' claims nobody has adjudicated. A
delegate that reads it treats all three as instruction, and the star mesh —
one adjudicator, one ledger — quietly becomes a shared scratchpad. Hence
the brief as the delegate's whole world, the ledger's status matrix as the
only broadcast, and every gap a callback rather than a read.

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
  explicitly refuses to gate the review phase — the cheap configuration
  to try next is solo implementation plus the centralised review pass.
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
  dependency — hence the dependency-scout bullet in phase-design.md §Task
  shape. Note this cuts *for* the protocol: scouts are read-only and run in
  parallel on delegates, so the delegated path can afford this check
  without spending the orchestrator's own context.
- **This measured the overhead floor, not the protocol.** The task was one
  node, one layer: no parallel implementers, no milestone gates, no worktree
  isolation for concurrent writers, nothing overflowing a single context. The
  graph machinery remains untested (see the roadmap entry below); a fair test
  needs a task a single context genuinely cannot hold.

## Roadmap / to evaluate

- **Judge-panel the frame, not just the implementation.** The protocol names the
  judge-panel pattern but applies it nowhere near the brief, which is where
  the variance actually is. For design-heavy tickets: generate two
  independent frames, score them, synthesize from the winner while grafting
  the runner-up's ideas. The design gate is the cheap version of this (one
  reviewer critiques one frame); the panel is the expensive version and
  unbuilt. Evidence that it would pay: on a same-ticket comparison, one run
  won three of four design forks, and the loser's PR shipped a defect two
  review passes and a mutation test all missed — found only by diffing
  against the other implementation.

- **Per-domain judges.** phase-review.md §Verification ownership says the
  verdict on a judgment check stays with "you, or one named judge per
  domain". The
  per-domain-judge option is permitted but unbuilt — e.g. a
  design-specialized agent owning UI verdicts instead of the orchestrator.
  Build only when a real need shows up; it needs a trust profile, a written
  standard, and a matrix entry before it may own verdicts. The split that
  *is* built: a UI *verifier* pane captures evidence (the model strongest
  at computer use), the orchestrator keeps the verdict.
- **Graph/ledger/milestone machinery is design, not yet battle-tested.**
  phase-design.md §Task shape, the ledger, and
  quiesce→teardown→compact→re-fan-out were
  reasoned out in a 2026-08 design pass, unlike the CLI quirk material,
  which was learned from real failures. Treat the first substantial
  multi-layer run as validation; expect follow-up adjustments.
- **Preview deployments are unmapped, not absent.** phase-review.md
  §Preview deployments
  expects a per-app opt-in mechanism in `environment.md`. Fill in each app's
  mechanism, URL scheme, and budget the first time you use it. Until an app
  has an entry, treat its UI evidence as local-run screenshots.
- **Implementer-internal scouts.** Currently a flat leaf rule: delegates
  never spawn subagents. The considered-and-deferred alternative: allow
  read-only, low-effort scouts inside the implementer's own worktree,
  drawing on the implementer's allowance rather than the orchestrator's.
  Deferred for enforceability — revisit if the leaf rule measurably slows implementers.
- **Reasoning-effort routing — built 2026-09, unmeasured.** phase-design.md
  §Reasoning effort pins the environment's default effort per brief and
  escalates on named signals (security, concurrency, seams, named
  ambiguity, non-mechanical migrations, second fix round). The signal list
  is reasoned, not measured: record in the run report which escalations
  paid (a fix round avoided) and which defaults failed (a second fix round
  on a default-pinned node), and prune the list from that.
- **Advisors — built 2026-10, unmeasured.** SKILL.md §Advisors adds an
  optional oracle (a model stronger at reading intent, consulted at
  decision points) and a classifier (a typed-judgment service that may
  escalate, never relax). The classifier runs through a fail-closed
  helper with versioned question sets, records a baseline and an
  independent outcome per call, samples its no-signals, and runs one
  bounded experiment per substantive run (references/classifier.md). Its
  helper is tested offline only: no live accuracy has been measured, and
  every shipped threshold is uncalibrated. Record in the run report which
  oracle consults changed a decision; drop either role if it stops
  paying.
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

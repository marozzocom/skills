# Proposal: decompose delegated-implementation into a scaffolded skill set

Status: proposal, 2026-10-25. Implements the charter in `vision.md`. Nothing here is loaded when the skill runs.
For humans and skill-editing sessions. Decisions are marked **Decision**;
open questions **Open**.

## 1. The question

The skill today is one protocol with one trigger: inside a Herdr session,
starting implementation work activates it, and from then on the
orchestrator runs a harness inside the harness — panes, briefs, ledger,
tiered review, landing. The question is whether the same value is better
delivered as a set of skills the harness picks up on its own merits, with
Herdr delegation as one transport among several rather than the frame
everything else hangs from.

Short answer: yes, decompose — but into a small hierarchy, not a pile of
micro-skills, and move the decision from "am I in Herdr?" to a per-node
transport choice driven by observable signals and recorded outcomes.

## 2. What vendors currently recommend

Primary sources read 2026-10-25; secondary sources excluded unless noted.

**Anthropic, Claude Code subagents doc and blog.** Subagents are for side
work that would flood the main context (search, logs, test output),
independent parallel research, unbiased review of code the subagent did
not write, and verification before commit. Stay in the main session for
sequential dependent work ("a single session handling the chain is
usually cleaner than a relay of subagents passing state through files"),
same-file edits, small tasks, and anything needing shared history. Rough
scale signal: ten-plus files or three-plus independent pieces. A
non-fork subagent "doesn't see your conversation history, the skills
you've already invoked, or the files Claude has already read"; the
delegation message is its whole world. Subagents can take
`isolation: worktree`. Nesting defaults to three levels; concurrency to
twenty.

**Anthropic, agent teams doc.** Experimental, off by default. Strongest
for research and review, competing hypotheses, and new modules each
owned by one teammate. "For sequential tasks, same-file edits, or work
with many dependencies, a single session or subagents are more
effective." Start with research and review before parallel
implementation. Partition by file ownership. 3–5 teammates. Lead stays
coordinator; teammates message each other directly (unlike subagents).
No session resume, no nested teams. Split-pane mode (tmux or iTerm2)
gives each teammate a human-inspectable pane.

**Anthropic, multi-agent research system.** Multi-agent spends ~15× the
tokens of a chat and pays off for breadth-first, parallelizable, high-value
work. "Most coding tasks involve fewer truly parallelizable tasks than
research." Lessons that transfer regardless: each subagent needs an
objective and an output format; scale effort to complexity explicitly;
checkpoint and resume rather than restart; judge outcomes, not paths.

**Anthropic, effective context engineering.** Three long-horizon
techniques, each with a fit: compaction for extended conversational work,
structured note-taking for "iterative development with clear milestones",
sub-agents for research that benefits from parallel exploration. The
protocol's ledger is structured note-taking by another name, and the
milestone-compaction rule is the recommended pairing.

**Anthropic, agent skills best practices (agentskills.io).** Scope a skill
like a function: "Skills scoped too narrowly force multiple skills to load
for a single task, risking overhead and conflicting instructions. Skills
scoped too broadly become hard to activate precisely." SKILL.md under 500
lines, references loaded on explicit triggers ("read X if Y"). Procedures
over declarations; defaults, not menus; explain *why* where the agent has
freedom, be prescriptive where the step is fragile; gotchas in SKILL.md;
bundle scripts the agent would otherwise reinvent; refine from execution
traces.

**OpenAI, Codex subagents doc.** "Use parallel agents for read-heavy tasks
such as exploration, tests, triage, and summarization." Built-in roles:
default, worker, explorer. Subagents inherit the sandbox; instructions
cannot create a read-only sandbox. Examples sequence writes: read-only
agents map the code, then one implementation agent edits. "Subagent
workflows consume more tokens than comparable single-agent runs."

**Cognition, "Don't build multi-agents" (2025, still their position).**
Share context, share full traces; "actions carry implicit decisions, and
conflicting decisions carry bad results." Parallel implementers that did
not see each other's reasoning diverge. Prefer a single-threaded agent,
with a compression model when context overflows. Partially dated (vendors
now ship parallel implementers), but the principle survives as: one
design authority, one writer per surface, briefs that carry decisions and
their evidence.

**Cross-model review.** Practitioner reports and one 2026 methodology
paper argue that a reviewer from a different model family has
decorrelated blind spots and so catches errors same-family review misses;
one vendor-affiliated campaign reports concrete finds. No controlled
study with matched baselines exists. Treat as a sound design argument
with anecdotal support, roughly doubling review-call cost.

**Where the vendors agree.** Orchestrator keeps requirements, decisions,
integration, and the final verdict. Delegates get a detailed brief with an
objective and an output format. Read-only fan-out is the safe default;
parallel writes need file ownership. Small, sequential, same-file work
stays with one agent. Cost scales with agent count and must be bought by
task value. None of this is Herdr-specific; the current skill already
follows all of it.

## 3. What the current skill actually contains

Reading SKILL.md and the phase files as capabilities rather than as one
protocol:

| Capability | Today | Depends on Herdr? | Valuable when implementing directly? | Native analogue |
|---|---|---|---|---|
| A. Routing / task fit | SKILL.md §Routing, phase-design §Task fit | trigger only | yes | none (the harness has no decision rule) |
| B. Design gate and contract | phase-design §Task shape, SKILL.md §Autonomy | no | yes | plan mode, Plan subagent |
| C. Brief authoring | brief-template, phase-design §Briefs | no | n/a | the delegation message; subagent `.md` definitions |
| D. Execution mesh | phase-execution, §Communication mesh, §Transcript boundary, run-prefix, rotate, agent-status | **yes** | no | subagents, agent teams |
| E. Independent verification and tiered review | phase-review, review-inventory, diff-hunks, run-gates, resolve-thread | no | **yes, measured** | a fresh review subagent |
| F. Landing and authorization | phase-landing, land-pr, watch-pr | no | yes | none; global CLAUDE.md mirrors part |
| G. Run ledger and context discipline | §Context discipline, ledger-append, run-report | no | yes for any long run | structured note-taking, compaction |
| H. Advisors | §Advisors, classifier.md, classify-escalate | no | yes | none |

Only D requires Herdr. A, B, E, F, G are worth having on every
implementation path and are already written harness-agnostically. C is
needed by every delegation transport, native or CLI. The skill's own
measurement (README §Why Task fit exists) says the review half (E)
carried its weight while the delegation half (D) did not on a one-node
task. The trigger, though, is gated on Herdr and routes everything
through D. That is the structural mismatch.

## 4. Benefits, honestly stated

Each benefit with what it rests on today. "Measured" means from the
skill's own runs; "argued" means a sound mechanism without a controlled
result; "claimed" means neither.

**Independent, centralized review.** Measured. A fresh reviewer that has
not seen the implementer's reasoning caught a user-visible regression
before it shipped; the solo run shipped a comparable defect. Every
vendor recommends the same pattern. This benefit does not require
Herdr: the reviewer can be a native subagent. It does require the
reviewer not share the implementer's context, so a fork subagent cannot
be it.

**Adversariality across model families.** Argued, not measured. Native
Claude Code can only pick Claude models for subagents and teammates. A
different vendor's reviewer or implementer requires an external process:
a Herdr pane, or an MCP bridge to that vendor's CLI. This is the one
capability native orchestration structurally lacks. Expect it to pay
where a confidently wrong "clean" is the expensive failure (auth, data
integrity, security semantics), not on routine diffs. Record, per run,
findings by reviewer family so the claim becomes measured.

**Cost.** Claimed, and the one measurement cuts the other way: the
delegated run cost ~2× the orchestrator's tokens plus implementer and
reviewer budget. Savings exist only as billing-path arbitrage: an
implementer on a flat-rate subscription while the orchestrator is
usage-billed, and the orchestrator's context being the scarce resource.
State it as that, never as token savings.

**Repeatable process, consistency, predictability.** Real for process
(ledger, run id, report shape, gate verdicts, landing modes), and the
README's first anti-goal says it must never extend to output: two runs on
one ticket produced two competent, different architectures, and pinning
the design would have locked in the worse one. The benefit is an
auditable trail and a consistent bar, not a consistent artifact.

**Control and visibility for the human.** Real, and a preference rather
than an outcome. Herdr panes let the human read, steer, and kill any
delegate mid-run and talk to it directly. Agent teams split-pane mode now
offers the same for Claude-only teammates. Native subagents offer less:
a result when they finish, a transcript on demand. Whether this is worth
the overhead is the human's call, so the decision rule should treat
"the human wants to watch" as an explicit input, not something the model
infers.

**Control and context economy for the overseer.** Real, and native
subagents give most of it for free: isolated context, a summary back.
What the protocol adds is the shapes: fixed report heads, verdict lines,
status probes, the transcript boundary. Those shapes are what let the
overseer run a long multi-node graph without flooding; they are useful
whichever transport carries the delegate.

**Isolation and one writer per worktree.** Real; now also native via
`isolation: worktree`. The leaf rule (delegates never spawn) is stronger
than the native default (three nesting levels) and worth keeping on both
transports.

**Cross-session continuity.** Real and currently Herdr-only in practice:
a ledger plus continuation prompt survives a session boundary; agent
teams do not resume. For work that genuinely exceeds one context window
this is the deciding capability.

**Capabilities native has that Herdr delegation does not.**

- Fork subagents share the orchestrator's full context: the Cognition
  concern (a delegate that never saw the reasoning) disappears for
  sequential dependent work.
- Zero transport cost: no pane, no brief file, no approval dialog, no
  status misreporting; results arrive as task notifications.
- Hooks (`TeammateIdle`, `TaskCompleted`, `PreToolUse`) and permission
  modes enforce rules mechanically where the protocol today relies on
  the brief's prose (README §Anti-goals, transcript boundary).
- Read-only fan-out via Explore is cheaper and faster than any CLI pane.

## 5. Decision rule: transport per node, from observed signals

The gate stays where phase-design §Task fit put it: after recon, from
observable signals, never from the request's label or a capability
self-estimate (README §Anti-goals). What changes is the output: not
"delegate or direct" but a transport per node, and the review half is
never gated.

**Decision.** Three transports, chosen per node at the design gate and
recorded in the ledger with the deciding signal:

| Transport | Pick when | Not when |
|---|---|---|
| **Direct** (orchestrator types, in the repo's isolation) | one app or package, single-digit files, nothing shardable, sequential and dependent, recon already loaded the code; or the deliverable is the orchestrator's own judgment in prose | the surface to read exceeds what should stay resident |
| **Native subagent** (fresh, worktree-isolated for writes; fork for context-dependent sequential steps; Explore for reads) | read-only fan-out (scouts, triage, repro hunts, checklist passes); a self-contained write whose brief fits one message and whose result is a summary; a review that must be independent of the implementer and same-family is acceptable | a different model family is required; the human wants to watch and steer; the node must survive a session boundary |
| **Herdr delegate** (CLI pane, pinned model and effort) | a different vendor is wanted for decorrelated review or implementation on risk-bearing code; billing path makes the implementer materially cheaper; the run spans sessions or needs the ledger-and-continuation machinery; the human asked to watch or to delegate | one-node tasks with no cross-family need (measured overhead with no design gain) |

Explicit requests still win ("do it yourself", "delegate this", "no
agents at all") and are recorded as the deciding signal. Agent teams are
not a transport yet: experimental, no resume, and enabling them changes
how named subagents behave (they become teammates). Revisit when they
leave experimental.

**Outcome-driven, not opinion-driven.** The run report gains a
per-node row: transport, model family, effort pin, fix rounds, review
findings by reviewer family, defects found after landing, orchestrator
tokens, wall time. After a handful of runs this table, not a preference,
revises the table above. The cheap experiment README already names
(solo implementation plus centralized cross-family review) is the first
one to run.

## 6. Proposed skill set

Six skills, one spine. Each is a coherent unit by the agentskills.io
test: a task that needs one of them rarely needs more than two others
loaded at once.

```
implementation-orchestration/   spine: routing, transport choice, roles, ledger
├── design-gate/                frame, forks with file:line, dependency scout, contract
├── delegation-briefs/          brief authoring for any transport; report shape; leaf rule
├── herdr-delegates/            the Herdr transport: panes, mesh, transcript boundary, quirks
├── independent-review/         verification ownership, inventory, triage, deep read, checklists
└── landing/                    authorization, landing modes, land-pr, threads, closeout
```

**`implementation-orchestration`** (replaces SKILL.md). Under 150 lines.
Holds §Routing (including the worker guard), the transport table above,
§Roles, §Autonomy and the contract, §Context discipline (ledger, run id,
milestone compaction, continuation prompt), and an index saying which
child to load when. Triggers on starting implementation work in any
session, Herdr or not. Advisors move to a reference under it.

**`design-gate`.** phase-design §Task shape and §Reasoning effort, plus
the dependency-scout rule, the contract (§5 of the charter's principles 8
and 9 encoded), and — a change from the first draft — the transport
table itself, since the per-node transport is decided where the frame is
known and a standalone user of the gate needs the rule too; the spine
cites it. Triggers before a contract or any brief,
including when the orchestrator will implement directly, and when a
plan or ADR is being reviewed. Model-invocable on its own: this is the
skill most likely to be picked up outside a delegated run.

**`delegation-briefs`.** brief-template plus phase-design §Briefs,
written transport-neutrally: reading order, scope fence, read fence,
role assignment, initiative line, verification floor, done-means, leaf
rule, report shape, two-brief bug fixes. A short per-transport annex
says how the brief travels (native: the delegation message plus a
preloaded skill; Herdr: a path, never inline). Triggers whenever work is
handed to any agent that did not share the conversation.

**`herdr-delegates`.** The only skill that requires `HERDR_ENV=1`.
phase-execution, §Communication mesh, §Transcript boundary, run-prefix,
rotate-implementer, agent-status, and environment.md's CLI quirks. Reads
the existing `herdr` skill for mechanics. Triggers only when the spine
or the user chose the Herdr transport.

**`independent-review`.** phase-review in full with its helpers. Triggers
on any done-report, and on the orchestrator's own direct implementation
before commit. Says plainly that a reviewer must not share the
implementer's context, and names the model-family lever for
risk-bearing surfaces.

**`landing`.** phase-landing with land-pr, watch-pr, resolve-thread,
run-report. Triggers at contract acceptance and when landing begins.
Overlaps the global CLAUDE.md delivery rules; the skill holds the
mechanics and modes, CLAUDE.md the policy.

**What stays shared.** Each child owns the helpers only it uses, with
their tests; the spine keeps the ledger, landing, report, and classifier
helpers. Of the three gitignored local references, checklists and trust
profiles moved to `independent-review` (step 2). `environment.md` stays
with the spine — a change from the first draft — because its classifier,
bot, billing, media, and repo sections are not transport facts;
`herdr-delegates` reads the CLI sections from it by path (step 4).

## 7. Risks and how the design meets them

- **Conflicting instructions when several children load.** The
  agentskills.io warning. Mitigation: the spine is the only skill that
  states roles and authority; children never restate them, they cite the
  spine. Children's descriptions are scoped to a phase so at most two are
  live at once.
- **The worker guard must survive.** A worker session has the same
  skills installed. The guard moves into the spine's description and
  into `delegation-briefs` and `herdr-delegates` descriptions: a session
  executing an assigned brief loads none of them. Detection stays
  textual, as today.
- **Over-triggering on small work.** `design-gate` and
  `independent-review` on a three-line fix would be the new overhead.
  Their descriptions carry the direct-path shortcut: a direct change with
  no open fork needs only the frame line in the ledger; a review of a
  single-digit-file diff is the orchestrator's own read, no fan-out.
- **Losing the measured discipline.** The report shape, verdict lines,
  and transcript boundary exist because the overseer's context fills
  from the inside. They apply to native subagents too (subagent results
  "can consume significant context"). `delegation-briefs` keeps them for
  every transport.
- **Agent teams interplay.** With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
  a named subagent launches as a teammate. The spine notes this and the
  native transport names subagents only when a later message is needed.

## 8. Open questions

- **Open:** does the orchestrator pick up `design-gate` and
  `independent-review` unprompted on native work? That is the hybrid's
  whole bet. Test with the skill-eval tooling (`claude plugin eval`) on
  three prompts: a small direct fix, a multi-file feature, a review
  request; grade on whether the right children loaded and nothing else.
- **Open:** is `landing` a skill or a CLAUDE.md section plus scripts?
  Its prose is mostly policy the global instructions already carry.
- **Open:** where the oracle and classifier live. They are decision-point
  advisors, so the spine; but both are unmeasured and may be dropped.
- **Open:** whether `delegation-briefs` should also emit a native
  subagent definition (`.claude/agents/<role>.md`) from the brief, so the
  native transport gets a pinned tool set and model rather than a prose
  fence.

## 9. Migration order

1. ~~Land this note; per-node transport and outcome rows in
   run-report.md~~ — done (#23, #24).
2. ~~Extract `independent-review`~~ — done (#25).
3. ~~Extract `design-gate`; transport table~~ — done (#26); the table
   lives in `design-gate` §6, not the spine.
4. ~~Split `delegation-briefs` from `herdr-delegates`~~ — done (#27);
   `environment.md` stays with the spine.
5. ~~Shrink SKILL.md into the spine~~ — done (this PR): 291 → 173
   lines, against a 150-line target; advisors moved to `references/advisors.md`; each child owns
   its helpers and tests. The directory keeps the name
   `delegated-implementation` rather than becoming
   `implementation-orchestration`: the operator's standing instructions
   on installed machines name it, and a rename is the operator's call.
6. **Open:** the trigger eval (§8) and the cheap experiment (§5) need a
   live run and the plugin-eval tooling; neither has been done. Until
   they are, the transport table in `design-gate` §6 is reasoned, not
   measured, and the next substantive run is the measurement.

Each step is its own PR; the skill keeps working between them because
every phase file is already read just-in-time.

## Sources

- Anthropic, Claude Code docs: [Subagents](https://code.claude.com/docs/en/sub-agents), [Agent teams](https://code.claude.com/docs/en/agent-teams), [Skills](https://code.claude.com/docs/en/skills)
- Anthropic blog: [How and when to use subagents in Claude Code](https://claude.com/blog/how-and-when-to-use-subagents-in-claude-code)
- Anthropic engineering: [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system), [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- Agent Skills spec: [Best practices for skill creators](https://agentskills.io/skill-creation/best-practices)
- OpenAI: [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- Cognition: [Don't build multi-agents](https://cognition.com/blog/dont-build-multi-agents)
- Cross-model review: [Refute-or-Promote (arXiv 2604.19049)](https://arxiv.org/pdf/2604.19049), [Adversarial code review (Augment Code)](https://www.augmentcode.com/guides/adversarial-code-review), [Cross-model adversarial review (practitioner)](https://codex.danielvaughan.com/2026/03/28/cross-model-adversarial-review/), [claude-code issue #67559](https://github.com/anthropics/claude-code/issues/67559)

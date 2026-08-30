---
name: delegated-implementation
description: "Orchestrate CLI coding agents (via Herdr) as workers while Claude oversees, reviews, verifies, and owns all git operations — an implementer CLI plus a fast reviewer/investigator/mechanical-refactorer CLI, with the concrete stack (e.g. Codex, Cursor) pinned in references/environment.md. Use PROACTIVELY, low threshold, whenever starting substantial implementation inside a Herdr session (HERDR_ENV=1): executing a written plan, building a feature, any change expected to span multiple files or need its own worktree. Also use when the user explicitly asks to delegate implementation to a CLI agent (e.g. Codex) or get a fast second-opinion review or investigation (e.g. from Cursor/Grok). Skip for single-file quick fixes, urgent hotfixes, pure review-only requests, when Herdr or the CLI login is unavailable, or when the user asks Claude to implement directly. Read the herdr skill first for CLI mechanics; this skill only adds the orchestration protocol."
---

# Delegated implementation protocol

Run an implementer CLI agent in a sibling Herdr pane; keep design
authority, review, independent verification, and every git/PR/merge operation
in your own session. This division is the point: implementation tokens burn in
the implementer's context (flat-rate on a subscription login), your context
stays orchestration-sized, and nothing lands unreviewed.

Preconditions: `test "${HERDR_ENV:-}" = 1`, and the implementer CLI's login
is on the expected subscription plan (check command per
`references/environment.md`) — if it reports an API key instead, tell the
user before proceeding, since that changes the cost model.

The protocol in this file is generic; read it with
`references/environment.md`, which pins the concrete stack — the CLI and
model filling each role (**implementer**; **fast reviewer / investigator /
mechanical worker**), start commands, repo names, CI integrations,
escalation reviewers, and the **cost table** — per-role marginal cost and
the routing rule that follows from it. The standing cost principle: the
orchestrator runs on the best available model, which makes its tokens the
most expensive in the whole mesh, so anything that needs neither your
accumulated context nor your authority (git, gate verdicts, adjudication)
runs on a delegate or a cheaper subagent — and mechanical workflow steps run
as **scripts** (`bin/`): deterministic, reviewed once, token-free
thereafter. Per-repo review checklists:
`references/review-checklists.md`. Per-agent trust calibration:
`references/agent-trust-profiles.md`. Porting to another machine or org
means adapting the references — never this file.

## Phase files — read just-in-time

The detailed protocol lives in `references/`, one file per phase. Read a
phase file when the run enters that phase — not all up front — and after a
milestone compaction re-read only the phase you are in: the split exists so
each context window carries the rules it is actually using.

- `references/phase-design.md` — task fit (the lower bound), task shape
  (graphs, milestones, gates, the design gate), and briefs. Read before
  writing the contract or any brief.
- `references/phase-execution.md` — starting and waiting on agents,
  lifecycle, the fast-reviewer role, parallel implementers. Read at first
  fan-out.
- `references/phase-review.md` — verification ownership, the tiered review,
  checklist passes, fix rounds, review threads, preview deployments, the
  external review bot. Read at the first done-report.
- `references/phase-landing.md` — landing modes, merge policy, complete
  deliverables, closeout. Read twice: at contract acceptance (the landing
  mode is decided there) and again when landing begins.

What stays in this file is what every phase needs: roles, the contract,
context discipline, the communication mesh, and the token-economy
mechanics.

## Roles — non-negotiable

- The implementer implements, runs its own tests, and reports. It never
  commits, stages, or pushes; every brief says so explicitly.
- Delegated agents are leaves. They never spawn or delegate to other agents
  or subagents — every brief says so, with the escalation valve: if a split
  or parallel investigation would genuinely help, they propose it to you and
  you decide and provision it. Several CLIs now ship native multi-agent
  tooling, which makes this line load-bearing: an implementer that forks its
  own workers silently breaks one-writer-per-worktree and centralized review.
- You triage every diff and read its risk-bearing code line-by-line (see
  references/phase-review.md), re-run the verification commands yourself before committing, and
  own commit, PR, and merge. Never forward a delegate's claimed results as
  your own verification.
- One task = one fresh worktree = one fresh implementer session. Agent
  sessions have a fixed cwd; rotating the worktree means restarting the agent
  (the rotation helper named in environment.md does quit → cd pane → start in
  one step).
- Verify factual claims the implementer's work depends on against the code
  yourself — especially security semantics. Its self-review is input, not
  clearance.

## Autonomy and the contract

You run the work autonomously: design, delegate, judge gates, kill lines of
work that stop earning, and land results without per-step permission. What
goes back to the human (or whatever prompted the run) is exceptions, not
progress: scope changes, safety concerns, a tripped stop criterion, a
contract amendment that alters the goal, or a decision that would invent
user-facing data or vocabulary (labels, product copy, enum members a user
sees) — flag those and wait. Inventing product data is never yours to do,
however obvious the gap looks from the code. Everything
else, decide and record in the ledger.

Before a long run, get one explicit acceptance of the contract: goals, the
graph skeleton (phase-design.md §Task shape), the stop criteria, and the **landing mode**
(phase-landing.md §Landing modes — whether the run merges autonomously, stages for one human
merge, or lands behind a feature flag). After that acceptance, silence from
the human is not a blocker.

State acceptance criteria as **invariants, not exhaustive contracts**:
properties that must hold ("no route reachable without an RBAC check",
"module X's public surface unchanged", "migration reversible", named gates
green), leaving implementation details to the implementer. Full up-front
interface contracts ossify — layer N's findings routinely require amending
them, and a strict contract regime drags the work back into planning, where
verification is hardest. Reserve pinned interface contracts for the one case
that needs them: seams where two parallel implementers must meet. Everywhere
else, amendment is the normal path — implementer proposes via the callback
channel, you adjudicate, the ledger records. The ledger is the living
contract; agility costs one message, not a re-planning phase.

## Context discipline — the ledger, and compacting at milestones

Durable state lives in files, not in your context window.

- Keep a **task ledger** file (scratchpad or repo, one per run): graph state,
  per-node status, decisions made, gate verdicts, contract amendments, open
  questions. Update it as you go, **timestamping entries** — the ledger
  doubles as the run's event log, and the closeout (phase-landing.md
  §Closeout) renders the report from it.
  Once the ledger is authoritative, losing conversational context is
  survivable — summary plus ledger reconstructs the run. Chronological
  entries go through `bin/ledger-append.sh` (§Token economy).
- **Assign a run id when you create the ledger** (`YYYY-MM-DD-<slug>`), and
  put it in every PR the run opens as an invisible HTML comment in the body:
  `<!-- herdr-run: <run-id> -->`. Reviewers see nothing; you (and the closeout)
  can pin any PR back to its run deterministically (lookup command in
  environment.md), and the ledger lists PR numbers the other way.
- **Head the ledger with a status matrix** — one row per live agent: name,
  role, worktree, the paths it owns, current state, what it is waiting on.
  The multiplexer already exposes liveness to every pane (`herdr agent
  list`), so what the matrix adds is *semantics*: who owns which files and
  which decisions are settled. Treat that status as advisory, not ground
  truth — for some CLIs it misreports (quirks in environment.md); before
  concluding an agent is idle or stuck, confirm with
  `herdr agent read <name> --source visible`. Name the ledger path in every brief as
  read-only shared context. **You are its only writer** — a delegate that
  writes it, or that acts on a peer's row instead of asking you, has become
  a second orchestrator.
- **Compact only at milestones, via full quiescence:** all agents idle →
  merge everything worth keeping into the ledger → tear down panes and
  worktrees (phase-landing.md §Closeout order) → compact → re-fan-out from the next milestone
  with fresh sessions and worktrees. Never compact with agents in flight.
  Teardown-before-compaction also means a context loss can never orphan a
  live agent.
- **Token budget is a gate input, and the preferred exit is a fresh session,
  not compaction.** Check remaining budget at every gate. Once roughly 400k
  tokens are consumed, start shaping the next milestone as a fresh-session
  start rather than a continuation; never begin a layer that could take the
  remaining budget below 500k mid-flight. At that boundary: land or stage
  what is landable, close out per phase-landing.md §Closeout, and put a **continuation
  prompt** in the ledger and the run report — self-contained (repo, run id,
  ledger path, contract state including landing mode, settled decisions with
  their evidence, the next milestone's goal and skeleton) so pasting it into
  a fresh session resumes the project with zero archaeology. Proposing that
  handoff is yours to do proactively; a run that limps to the context floor
  mid-milestone chose the worst of the three exits.
- Supporting hygiene: read agent reports from their files once, don't pull
  the same diff into context twice, and prefer targeted
  `herdr agent read --source visible` snippets over history dumps.

## Communication mesh

Name yourself once so delegates can address you:

```bash
herdr agent rename "$HERDR_PANE_ID" overseer
```

Every brief includes the callback line: *"If you need a decision,
clarification, or hit a blocker, message me with:
`herdr agent prompt overseer "<message>"` — use it for blockers and decisions,
not progress narration, and batch — one message carrying every open
question, not one per question."* Callbacks arrive in your session formatted like user
messages; treat them as agent traffic, not the human, and answer with
`herdr agent prompt <name> '...'`.

**All traffic is star-shaped: delegates message you, never each other.** The
multiplexer makes agent-to-agent prompting perfectly possible, and it stays
unused. The star is what keeps one adjudicator, one ledger, and one account
of why each decision was made; with the leaf rule (§Roles) it means every
fact a delegate learns reaches its peers only through you — deliberately,
because you are the only node that can weigh two agents' claims against each
other. Broadcasting is a file, not a message: agents read the ledger's status
matrix, and a peer's row is context, never an instruction.

Write briefs to a scratchpad file and send the **path**, never the text:

```bash
herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly as
written. It is your task brief from the orchestrator (the agent named overseer)."
```

Two reasons. Inlining the body with `"$(cat "$BRIEF_FILE")"` **fails silently
past a few KB** on at least one CLI — the agent accepts the paste, flickers
`blocked` → `idle`, and runs nothing, leaving an empty composer and no error
(evidence per CLI in environment.md; assume any CLI can do this). And
PreToolUse hooks may regex the literal command
string, so a brief that merely *mentions* "git commit/push" can be blocked as
if you were committing. The path sidesteps both, and keeps the brief
re-readable mid-task instead of buried in scrollback. Inline only short
prompts and fix rounds.

When a delegate first tries to message you, its CLI's own approval dialog
may block the `herdr agent prompt` command. Approve it with the CLI's
"don't ask again for commands that start with…" (or equivalent persistent
allow) option so the channel never stalls again.

## Token economy — mechanics

The cost principle made mechanical. Deterministic workflow steps run as
`bin/` scripts — reviewed once, token-free thereafter — and each rule here
exists because the habit it replaces was observed burning orchestrator
context:

- **Gate re-runs:** `bin/run-gates.sh <worktree> "<name>:<command>" ...` —
  one verdict line per gate, failure tails only, full logs kept on disk.
  Your acceptance re-run needs verdicts, not scrollback; the verbatim
  output already lives in the implementer's report file.
- **Status probes:** `bin/agent-status.sh <name> [tail-lines]` — herdr
  status plus the last visible pane line, one line per poll. Full pane
  reads (`herdr agent read --source visible`) are for adjudicating a
  `blocked` dialog or a suspect state, never for routine polling.
- **Review threads:** `bin/resolve-thread.sh <owner/repo> <pr> <comment-id>
  "<message>"` — in-thread reply plus resolve in one call, one line back
  (usage in phase-review.md §Review threads).
- **Ledger appends:** `bin/ledger-append.sh <ledger> "<entry>"` —
  timestamped append with no read-modify-write round-trip. Everything
  chronological goes through it; structural edits (the status matrix,
  rewriting a section) still use a normal edit.
- **No bare `git diff` on a triaged tree.** The triage's routing file
  (phase-review.md §Review) names the ranges you must read; pull those with
  per-file scoped diffs, never the whole diff "to be safe". The full diff
  enters your context at most once, and ideally never.
- **Callbacks are batched.** Every brief tells delegates to send one
  callback carrying every open question, not one message per question —
  each callback is a full orchestrator turn.
- **Collation is delegable.** When three or more reviewers report on one
  tree, a cheap harness subagent (model pinned per environment.md's cost
  table) merges the finding files into one deduplicated list, each finding
  citing its source report. You adjudicate the merged list; reading N
  overlapping reports is I/O, not judgment.

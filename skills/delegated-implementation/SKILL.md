---
name: delegated-implementation
description: "Orchestrate CLI coding agents in Herdr panes as implementers and fast reviewers while Claude reviews, verifies, and owns all git operations. Use PROACTIVELY, low threshold, whenever starting substantial implementation inside a Herdr session (HERDR_ENV=1) — a plan, a feature, anything spanning multiple files or needing its own worktree — or when the user asks to delegate to a CLI agent or get a second-opinion review. Skip for single-file fixes, hotfixes, review-only requests, or when Herdr is unavailable. Read the herdr skill first for CLI mechanics."
---

# Delegated implementation protocol

Run implementer CLI agents in sibling Herdr panes; keep design authority,
review, independent verification, and every git/PR/merge operation in your
own session. Implementation tokens burn in flat-rate delegate contexts,
your context stays orchestration-sized, and nothing lands unreviewed.

Preconditions: `test "${HERDR_ENV:-}" = 1`, and the implementer CLI logged
in on subscription, not an API key (check command in
`references/environment.md`) — an API key changes the cost model; tell the
user.

The protocol is generic; the references are local. `environment.md` pins
the stack (CLIs, models, commands, quirks, repos, the cost table);
`review-checklists.md` maps repos to checklists; `agent-trust-profiles.md`
calibrates per-agent trust. Porting = rewriting the references, never the
protocol files.

Cost principle: the orchestrator runs the best model, so its tokens are
the most expensive in the mesh. Whatever needs neither your accumulated
context nor your authority (git, gate verdicts, adjudication) runs on a
delegate or a cheaper subagent, and deterministic workflow steps run as
`bin/` scripts — reviewed once, token-free thereafter.

## Phase files — read just-in-time

Phase detail lives in `references/`, one file per phase. Read a phase file
on entering its phase — not all up front — and after a milestone
compaction re-read only the phase you are in.

- `phase-design.md` — task fit, task shape and gates, briefs. Before the
  contract or any brief.
- `phase-execution.md` — starting and waiting on agents, the fast
  reviewer, parallel implementers. At first fan-out.
- `phase-review.md` — verification ownership, tiered review, checklists,
  fix rounds, review threads, previews, external bot. At the first
  done-report.
- `phase-landing.md` — landing modes, merge policy, complete deliverables,
  closeout. At contract acceptance (the mode is decided there) and again
  when landing begins.

## Roles — non-negotiable

- The implementer implements, runs its own tests, and reports. It never
  commits, stages, or pushes; every brief says so.
- Delegates are leaves: no spawning or sub-delegating — every brief says
  so, with the valve "propose a split to me and I decide". Load-bearing
  now that CLIs ship native multi-agent tooling: a self-forking
  implementer silently breaks one-writer-per-worktree and centralized
  review.
- You triage every diff, read its risk-bearing code line-by-line
  (phase-review.md), re-run verification yourself before committing, and
  own commit, PR, and merge. Never forward a delegate's claimed results as
  your verification; verify the factual claims its work depends on —
  especially security semantics — against the code yourself.
- One task = one fresh worktree = one fresh implementer session. Agent
  cwds are fixed: rotating the worktree means restarting the agent
  (rotation helper in environment.md).

## Autonomy and the contract

Run autonomously: design, delegate, judge gates, kill lines that stop
earning, land results. Back to the human go exceptions only: scope
changes, safety concerns, tripped stop criteria, goal-altering
amendments, and anything that invents user-facing data or vocabulary
(labels, product copy, visible enum members) — never yours to invent,
however obvious the gap. Everything else: decide and record in the ledger.

Before a long run, get one explicit acceptance of the contract: goals,
graph skeleton (phase-design.md §Task shape), stop criteria, and landing
mode (phase-landing.md §Landing modes). After acceptance, silence from
the human is not a blocker.

State acceptance criteria as invariants, not exhaustive contracts ("no
route reachable without an RBAC check", "module X's public surface
unchanged", named gates green). Up-front interface contracts ossify and
drag the work back into planning, where verification is hardest; pin them
only at seams where two parallel implementers must meet. Everywhere else
amendment is the normal path — implementer proposes via callback, you
adjudicate, the ledger records. The ledger is the living contract.

## Context discipline

Durable state lives in files, not your context window.

- One **task ledger** per run: graph state, node status, decisions, gate
  verdicts, amendments, open questions — timestamped, since it doubles as
  the event log the closeout report renders from. Summary plus ledger
  must reconstruct the run. Chronological entries go through
  `bin/ledger-append.sh` (§Token economy).
- Assign a **run id** (`YYYY-MM-DD-<slug>`) at ledger creation; every PR
  the run opens carries `<!-- herdr-run: <run-id> -->` in its body
  (invisible when rendered; lookup command in environment.md).
- Head the ledger with a **status matrix**: agent, role, worktree, owned
  paths, state, waiting-on. Herdr shows liveness; the matrix adds
  semantics. Status is advisory — some CLIs misreport (environment.md);
  confirm with a pane read before concluding idle or stuck. Name the
  ledger in every brief as read-only shared context; **you are its only
  writer** — a delegate that writes it, or acts on a peer's row, has
  become a second orchestrator.
- **Compact only at milestones, via full quiescence:** all agents idle →
  merge keepers into the ledger → tear down panes and worktrees
  (phase-landing.md §Closeout) → compact → re-fan-out fresh. Never
  compact with agents in flight.
- **Token budget is a gate input; prefer a fresh session over
  compaction.** From ~400k tokens consumed, shape the next milestone as a
  fresh-session start; never begin a layer that could drop the remaining
  budget below 500k mid-flight. At the boundary: land or stage what is
  landable, close out per phase-landing.md §Closeout, and leave a
  self-contained **continuation prompt** (repo, run id, ledger path,
  contract state incl. landing mode, settled decisions with evidence,
  next milestone's goal and skeleton) in the ledger and run report.
  Propose the handoff proactively — limping to the context floor
  mid-milestone is the worst exit.
- Read each agent report file once; never pull the same diff into context
  twice.

## Communication mesh

Name yourself once so delegates can address you:
`herdr agent rename "$HERDR_PANE_ID" overseer`.

Every brief carries the callback line: *"If you need a decision,
clarification, or hit a blocker, message me with:
`herdr agent prompt overseer "<message>"` — blockers and decisions, not
progress narration, and batch every open question into one message."*
Callbacks arrive formatted like user messages — treat them as agent
traffic, not the human, and answer with `herdr agent prompt <name> '...'`.

**All traffic is star-shaped: delegates message you, never each other.**
The star keeps one adjudicator, one ledger, one account of every decision;
only you can weigh two agents' claims against each other. Broadcasting is
a file, not a message: agents read the ledger's status matrix, and a
peer's row is context, never an instruction.

Send briefs as a **path, never inline text**:

```bash
herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly as
written. It is your task brief from the orchestrator (the agent named overseer)."
```

Inlining fails silently past a few KB on at least one CLI — the agent
accepts the paste, flickers `blocked` → `idle`, and runs nothing
(evidence per CLI in environment.md; assume any CLI can) — and PreToolUse
hooks may regex the literal command string, blocking a brief that merely
mentions "git commit/push". Inline only short prompts and fix rounds. A
delegate's first callback may hit its own CLI's approval dialog — approve
with the persistent "don't ask again" option so the channel never stalls
again.

## Token economy — mechanics

- **Gate re-runs:** `bin/run-gates.sh <worktree> "<name>:<command>" ...` —
  one verdict line per gate, failure tails only, full logs on disk.
- **Status probes:** `bin/agent-status.sh <name> [tail-lines]` — one line
  per poll. Full pane reads are for adjudicating a `blocked` dialog or a
  suspect state, never routine polling.
- **Review threads:** `bin/resolve-thread.sh <owner/repo> <pr>
  <comment-id> "<message>"` — reply plus resolve, one line back.
- **Ledger appends:** `bin/ledger-append.sh <ledger> "<entry>"`;
  structural edits (the status matrix) still use an editor.
- **No bare `git diff` on a triaged tree** — read only the ranges the
  triage routing file names (phase-review.md §Review), as scoped per-file
  diffs. The full diff enters your context at most once, ideally never.
- **Batch callbacks** — enforced by the brief's callback line above.
- **Delegate collation:** three or more reviewer reports on one tree → a
  cheap harness subagent (model per environment.md's cost table) merges
  them into one deduplicated, source-cited list; you adjudicate the
  merged list.

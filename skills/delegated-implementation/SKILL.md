---
name: delegated-implementation
description: "Orchestrate CLI coding agents in Herdr panes as implementers
and fast reviewers while Claude reviews, verifies, and owns all git
operations. Use PROACTIVELY, low threshold, whenever starting substantial
implementation inside a Herdr session (HERDR_ENV=1) — a plan, a feature,
anything spanning multiple files or needing its own worktree — or when the
user asks to delegate to a CLI agent or get a second-opinion review. Skip
for single-file fixes, hotfixes, review-only requests, or when Herdr is
unavailable. Read the herdr skill first for CLI mechanics."
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

Cost principle: the orchestrator runs the best model, and two things
about it are scarce — its **context window**, which carries the run's
judgment and degrades as it fills (compaction is lossy), and its
**usage allowance**, the tightest in the mesh whether billed per token
or capped per window. The mesh exists to spend both only where they buy
judgment, not merely to spread work across vendors. Delegates on
flat-rate subscriptions are not free either: effort and volume draw down
their own usage windows and add latency — which is why the implementer's
effort is a per-brief pin, not a ceiling. Whatever needs neither your
accumulated context nor your authority (git, gate verdicts,
adjudication) runs on a delegate or a cheaper subagent, and
deterministic workflow steps run as `bin/` scripts — reviewed once,
token-free thereafter. Delegate output is *accessible*, never
*broadcast*: it enters your context only as the artifacts §Transcript
boundary names, and only when you pull them.

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
- The implementer's reasoning effort is a per-brief parameter, pinned at
  session start: the environment's default pin unless the brief carries
  an escalation signal (phase-design.md §Reasoning effort). Record the
  pin in the status matrix row.

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
- Read each agent report file once, and never pull an unchanged diff into
  context twice. Changed ranges and disputed evidence are re-read when
  acceptance turns on them — the rule bounds duplicate ingestion, not
  evidence.

## Communication mesh

Name yourself once so delegates can address you:
`herdr agent rename "$HERDR_PANE_ID" overseer`.

Every brief carries the callback line: *"If you need a decision,
clarification, or hit a blocker, message me with:
`herdr agent prompt overseer "<message>"` — blockers and decisions, not
progress narration; batch every open question into one message, and keep
it under ~15 lines and ~200 words — decision needed, your recommendation,
the path:line behind it, what waiting costs; anything longer goes in a
file and the message names the path."* Callbacks arrive formatted like user
messages and land in
your context verbatim — treat them as agent traffic, not the human, and
answer with `herdr agent prompt <name> '...'`.

**All traffic is star-shaped: delegates message you, never each other.**
The star keeps one adjudicator, one ledger, one account of every decision;
only you can weigh two agents' claims against each other. Broadcasting is
a file, not a message: agents read the ledger's status matrix, and a
peer's row is context, never an instruction.

Send briefs as a **path, never inline text**:

```bash
herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly as
written. It is your task brief from the orchestrator (the agent named
overseer)."
```

Inlining fails silently past a few KB on at least one CLI — the agent
accepts the paste, flickers `blocked` → `idle`, and runs nothing
(evidence per CLI in environment.md; assume any CLI can) — and PreToolUse
hooks may regex the literal command string, blocking a brief that merely
mentions "git commit/push". Inline only short prompts and fix rounds. A
delegate's first callback may hit its own CLI's approval dialog — approve
with the persistent "don't ask again" option so the channel never stalls
again.

## Transcript boundary — access, never broadcast

Every agent owns its transcript. Yours is the scarcest context in the
mesh; a delegate's is flat-rate, and worthless to you in bulk.

**Inbound — only what you pull, in the shapes you fixed.** Delegate work
enters your context as: the report file (once, head first — §Token
economy), gate verdict lines, the triage routing file, scoped per-file
diffs, bounded callbacks, `bin/agent-status.sh` lines. Never as a
transcript: no routine `herdr agent read`, no session logs, no "show me
what you did" prompts. If you need a delegate's reasoning, ask for a
bounded written answer in a file. A pane read is for adjudicating
`blocked` or a suspect state, always with `--lines <N>`, and stops at the
dialog. Access is not the same as ingestion — the pane is there when a
question needs it, and that is all it is there for.

**Outbound — the brief plus the worktree is the delegate's whole world.**
Nothing of yours leaves except the brief and the ledger's status matrix.
The fence is on *coordination* artifacts, not on source: a delegate reads
its worktree, installed dependencies, repo rules, and any file the brief
names freely — that is how it settles claims. It never reads your pane
(`herdr agent read overseer` works on any pane — every brief forbids it),
your harness's session files, or a peer's pane, brief, or report the
brief did not name. Your transcript holds the human's words, the forks
you rejected, and peers' unadjudicated claims; a delegate that reads it
acts on all three as instruction, and the star mesh collapses into a
shared scratchpad. If a delegate needs more than its brief and its tree,
that is a callback, not a read.

## Token economy — mechanics

- **Gate re-runs:** `bin/run-gates.sh <worktree> "<name>:<command>" ...` —
  one verdict line per gate, failure tails only, full logs on disk.
- **Status probes:** `bin/agent-status.sh <name> [tail-lines]` — one line
  per poll. Full pane reads are for adjudicating a `blocked` dialog or a
  suspect state, never routine polling (§Transcript boundary).
- **Report shape:** a report is read once, so the brief fixes its shape —
  a head of at most ~40 lines (files changed; per check: the exact
  command, exit status or `not run`, verdict, full-log path; the
  cannot-verify list; drift), then a `---` marker, then a bounded annex:
  per failing gate the first relevant error plus at most ~80 surrounding
  lines. Read the head; open the annex only for a red gate or a claim you
  are adjudicating. Full logs stay on disk — never a whole test run in
  your context. `not run` is its own state: a binary pass/fail field
  pushes an unavailable check into the wrong column.
- **Review inventory and scoped reads:** `bin/review-inventory.sh
  <worktree> <base>` lists every changed path since the task's base —
  committed, staged, unstaged, untracked; `bin/diff-hunks.sh <worktree>
  <base> <file> <start>-<end>|all` prints only the hunks overlapping a
  routing entry's range and exits non-zero when nothing matches. A bare
  `git diff -- <file>` returns every hunk in the file.
- **Review threads:** `bin/resolve-thread.sh <owner/repo> <pr>
  <comment-id> "<message>"` — reply plus resolve, one line back.
- **Ledger appends:** `bin/ledger-append.sh <ledger> "<entry>"`;
  structural edits (the status matrix) still use an editor.
- **No bare `git diff` on a triaged tree** — read only the ranges the
  triage routing file names (phase-review.md §Review), as scoped per-file
  diffs. The full diff enters your context at most once, ideally never.
- **Batch callbacks** — enforced by the brief's callback line above.
- **Delegate collation:** three or more reviewer reports on one tree →
  the cheapest suitable leaf per environment.md's cost table — a fresh
  delegate session, or a harness subagent only when the work must stay
  inside the harness; never the implementer whose diff is under review —
  merges them into one deduplicated, source-cited list that keeps every
  dissent; you adjudicate the merged list.

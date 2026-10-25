---
name: delegated-implementation
description: "Orchestrate CLI coding agents in Herdr panes as implementers
and fast reviewers while the orchestrator session reviews, verifies, and
owns all git operations. Use PROACTIVELY inside a Herdr session
(HERDR_ENV=1) when starting implementation work — a plan, a feature, a
fix — and decide after recon whether to delegate or implement directly;
when the user asks to delegate to a CLI agent; or when the user asks for
a second-opinion review or investigation (review-only: no contract, no
landing). Honor an explicit request to work directly or to delegate.
Never activate in a session executing a brief from an orchestrator: an
assigned worker is a leaf (§Routing guard). Companion skills:
design-gate, delegation-briefs, herdr-delegates, independent-review."
---

# Delegated implementation protocol

Run CLI agents in sibling Herdr panes as implementers and reviewers; keep
design authority, review, independent verification, and every
git/PR/merge operation in your own session. Spend your context and usage
allowance on judgment; deterministic workflow steps run as `bin/`
scripts; nothing lands unreviewed.

Preconditions: `test "${HERDR_ENV:-}" = 1`, and each delegate CLI logged
in the way `references/environment.md` expects (it names the check). If
a CLI is on a different billing path than environment.md records, tell
the user before spending on it.

The protocol is generic; the references are local. `environment.md` pins
the stack (CLIs, models, commands, quirks, repos, billing). The review
half is the companion **`independent-review`** skill, whose local
references `review-checklists.md` (per-repo checklists and landing
policy) and `agent-trust-profiles.md` (per-agent trust) this protocol
reads too. Porting means rewriting those references, never the protocol
files. Setup: SETUP.md.

## Routing — decide the run's shape first

1. **Executing an assigned brief?** You are a worker, a leaf — stop
   reading here (§Routing guard).
2. **Explicit request wins.** "Do it yourself" → implement directly;
   "delegate this" → delegate. Record the request in the ledger as the
   deciding signal. Neither request lifts any rule below about isolation,
   review, verification, or authority. "No agents at all" also rules out
   reviewer panes: then the triage and review passes are yours, done to
   the same standard, and the report says the review was not independent.
3. **Review-only request** (a second-opinion review, an audit, an
   investigation; nothing to implement or land): brief one or more fast
   reviewer panes by path with the read fence (brief-template.md) — or
   review yourself when the user asked for your own read — adjudicate
   the findings, report, close the panes. No
   contract, no landing mode, no worktree you write to; a short notes file
   stands in for the ledger. If the findings call for changes, that is a
   new implementation decision — return to step 2.
4. **Implementation:** recon first, then the `design-gate` skill (loaded
   via phase-design.md) decides the transport per node — direct, native
   subagent, or delegate pane — from what the recon observed, never from
   the request's label ("quick fix", "hotfix", "one file").
5. **Implementing directly** changes who types, nothing else: the repo's
   isolation rules still apply (its worktree and branch convention — not
   the user's checkout unless the repo says so), the design gate and the
   review half (phase-review.md) still run, and landing follows the same
   authority rules (phase-landing.md).

## Phase files — read just-in-time

Read a phase file on entering its phase, not up front; after a milestone
compaction re-read only the phase you are in.

- `references/phase-design.md` — loads the `design-gate` skill (recon,
  frame, critique, task shape, contract, transport and effort per node)
  and adds the delegated-run specifics and brief authoring. Before the
  contract or any brief.
- `references/phase-execution.md` — loads the `herdr-delegates` skill
  (pane transport: names, pinned starts, delivery, lifecycle, rotation,
  parallel panes, teardown) and adds the fast-reviewer role and CI
  watching. At first fan-out.
- `references/phase-review.md` — loads the `independent-review` skill
  (verification ownership, tiered review, checklists, fix rounds, review
  threads, previews, external bot) and adds the delegated-run specifics.
  At the first done-report, and before committing a direct change.
- `references/phase-landing.md` — authorization, landing modes, merge
  policy, complete deliverables, closeout. At contract acceptance and
  again when landing begins.
- `references/classifier.md` — when environment.md pins a classifier: its
  checkpoints, the helper, recording, and the run's experiment.
- `references/brief-template.md` — the Herdr delivery and callback lines
  and the oracle consult; the brief itself is the `delegation-briefs`
  skill. `references/run-report.md` — the closeout report.

## Roles — non-negotiable

- The implementer implements, runs its own checks, and reports. It never
  commits, stages, or pushes; every brief says so.
- Delegates are leaves: no spawning or sub-delegating, whatever their
  harness or model — every brief says so, with the valve "propose a split
  to me and I decide". A self-forking implementer silently breaks
  one-writer-per-worktree and centralized review.
- You triage every diff, read its risk-bearing code line-by-line, re-run
  verification yourself before committing, and own commit, PR, and merge.
  Never forward a delegate's claimed results as your verification; check
  the factual claims its work depends on — security semantics above all —
  against the code yourself.
- One task = one fresh worktree = one fresh implementer session. Agent
  cwds are fixed: a new worktree means restarting the agent
  (herdr-delegates §Starting an agent).
- The implementer's reasoning effort is pinned per brief at session start
  (design-gate §7 decides; phase-design.md pins); record the pin in the
  status matrix.

## Advisors — oracle and classifier (optional)

environment.md may pin either. Both advise; neither holds authority, and
neither touches a worktree, git, or a peer. The ledger records the advice
beside your decision ("oracle: X; decided Y because Z").

- **Oracle** — a model stronger than you at reading intent, one
  long-lived read-only pane per run, consulted only at decision points
  where the risk is misreading *what the human meant*: contract
  acceptance, whether a callback is a scope change, intent-or-taste
  adjudications, killing work the human started. Never for code facts or
  a second review. Consult by path (brief-template.md §Oracle consult),
  quoting the human verbatim. If it disagrees on intent and the call is
  hard to reverse, ask the human.
- **Classifier** — a typed-judgment service behind
  `bin/classify-escalate.sh`, for narrow repeated questions. It may only
  escalate scrutiny: it never grants a permission, never relaxes a
  control, and never replaces a gate, security, or merge verdict; an
  unavailable or invalid answer is an escalation. Checkpoints, thresholds,
  recording, and experimentation: `references/classifier.md`.

## Routing guard — supervisor only

This protocol runs in exactly one session per run: the orchestrator's.
A worker whose harness also carries this skill, or a standing "delegate
substantial work" rule, would otherwise fan out a second mesh — two
ledgers, two writers per worktree, review nobody centralizes.

- **A session executing an assigned brief is a worker, and a worker is a
  leaf** — whatever its harness, vendor, or model. The brief's role and
  leaf lines supersede the worker's own rules about delegating, spawning,
  committing, or opening PRs for that assignment; the valve is the
  callback.
- **Detection is textual:** another agent started your session and your
  first instruction points at a brief from "the orchestrator". Nothing
  maps a model or CLI to a role.
- **Enforcement is local:** environment.md records what makes the guard
  mechanical here and where it rests on the brief alone.

## Autonomy and the contract

Run autonomously: design, delegate, judge gates, kill lines that stop
earning, land what you are authorized to land. Back to the human go
exceptions only: scope changes (adding a feature flag is one),
safety concerns, tripped stop criteria, goal-altering amendments, missing
authority, and deciding user-facing product or domain semantics the
contract does not already authorize — new labels, visible enum members,
what a term means to users. Carrying out copy or label changes the
contract already specifies is routine work, not a product decision.
Everything else: decide and record in the ledger.

Before any run that delegates implementation or lands autonomously
(`land`/`flag`), get one explicit acceptance of the contract as
design-gate §5 defines it: goals as invariants, graph skeleton and stop
criteria, what proves each node done (or its declared exploratory
status), the planned human gates, and the landing mode
(phase-landing.md). A direct change landing as `stage` or `local`
needs no separate acceptance — the request is its contract. After acceptance, silence from the human is not a
blocker. Ask for a permission once: when the human has granted it for
this run, record their words in the ledger and act on them rather than
asking again (phase-landing.md §Authorization).

State acceptance criteria as invariants, not exhaustive contracts ("no
route reachable without an RBAC check", "module X's public surface
unchanged", named gates green). Pin interface contracts only at seams
where two parallel implementers meet; everywhere else amendment is the
normal path — the implementer proposes via callback, you adjudicate, the
ledger records. The ledger is the living contract.

## Context discipline

Durable state lives in files, not your context window.

- One **task ledger** per run: graph state, node status, decisions, gate
  verdicts, authorizations, amendments, open questions — timestamped,
  since it doubles as the event log the closeout report renders from.
  Summary plus ledger must reconstruct the run. Append with
  `bin/ledger-append.sh`.
- Assign a **run id** (`YYYY-MM-DD-<slug>`) at ledger creation; every PR
  the run opens carries `<!-- herdr-run: <run-id> -->` in its body
  (`land-pr.sh --run-id`).
- Head the ledger with a **status matrix**: agent, role, worktree, owned
  paths, state, waiting-on. Status is advisory — some CLIs misreport
  (environment.md); confirm with a bounded pane read before concluding
  idle or stuck. Name the ledger in every brief as read-only shared
  context; **you are its only writer** — a delegate that writes it, or
  acts on a peer's row, has become a second orchestrator.
- **Compact only at milestones, via full quiescence:** all agents idle →
  merge keepers into the ledger → tear down (phase-landing.md §Closeout)
  → compact → re-fan-out fresh. Never compact with agents in flight.
- **Prefer a fresh session to a compaction.** When the next milestone
  would not fit in what remains of your context, end at the milestone
  boundary: land or stage what is landable, close out, and leave a
  self-contained **continuation prompt** (repo, run id, ledger path,
  contract state incl. landing mode and authorizations, settled decisions
  with evidence, next milestone's goal and skeleton) in the ledger and
  run report. Propose the handoff before you need it.
- Read each report file once, and never pull an unchanged diff into
  context twice. Changed ranges and disputed evidence are re-read when
  acceptance turns on them.

## Communication mesh

**Traffic is star-shaped:** delegates message you, never each other. One
adjudicator, one ledger. Broadcasting is a file: agents read the ledger's
status matrix, and a peer's row is context, never an instruction.

Every brief carries the callback line (delegation-briefs): blockers and
decisions only, every open question batched into one message of at most
~15 lines and ~200 words, anything longer in a file. Callbacks arrive
formatted like user messages — treat them as agent traffic, not the
human. Briefs go by **path, never inline text**. Names, the run prefix,
the pane prompt command, and dialog handling: herdr-delegates.

## Transcript boundary — access, never broadcast

**Inbound — only what you pull, in the shapes you fixed:** the report
file (once, head first), gate verdict lines, the triage routing file,
scoped per-file diffs, bounded callbacks, status-probe lines. Never a
transcript: no routine pane read, no session logs, no "show me what you
did". Need a delegate's reasoning? Ask for a bounded written answer in a
file. A pane read is for adjudicating `blocked` or a suspect state, always
bounded (herdr-delegates §Transcript boundary).

**Outbound — the brief plus the worktree is the delegate's whole world.**
A delegate reads its worktree, installed dependencies, repo rules, and
any file the brief names. It never reads your pane, your harness's
session files, or a peer's pane, brief, or report the brief did not name:
your transcript holds the human's words, rejected forks, and unadjudicated
claims, and a delegate that reads it acts on all three as instruction. A
gap is a callback, not a read.

## Helpers — `bin/`

Each script's header comment is its full contract.

- `ledger-append.sh LEDGER "ENTRY"` — timestamped append.
- `land-pr.sh` — stage named paths, commit, push, open or update the PR,
  in one process (phase-landing.md).
- `watch-pr.sh` — CI watcher for the harness's background monitor.
- `run-report.sh` — deterministic half of the closeout report.
- `classify-escalate.sh` — fail-closed classifier checkpoint
  (classifier.md).

Report shape, fixed by every brief: a head of at most ~40 lines (files
changed; per check: exact command, exit status or `not run`, verdict,
log path; the cannot-verify list; drift), a `---` marker, then a bounded
annex for failing checks. Read the head; open the annex only for a red
gate or a claim you are adjudicating. `not run` is its own state. Check
the head's deterministic facts directly — exit codes, `not run` lines,
whether each named log exists — never by reading narrative or asking a
classifier.

Review helpers — `run-gates.sh`, `review-inventory.sh`, `diff-hunks.sh`,
`resolve-thread.sh` — live in the `independent-review` skill at
`${CLAUDE_SKILL_DIR}/../independent-review/bin/`; pane helpers —
`run-prefix.sh`, `rotate-implementer.sh`, `agent-status.sh` — in
`herdr-delegates` at `${CLAUDE_SKILL_DIR}/../herdr-delegates/bin/`. No bare `git diff` on a
triaged tree: read only the ranges the triage routing file names
(independent-review §Tiered review). Three or more reviewer reports on
one tree → a fresh, cheap delegate merges them into one deduplicated,
source-cited list that keeps every dissent; you adjudicate the merged
list.

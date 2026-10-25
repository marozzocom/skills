---
name: delegated-implementation
description: "The spine of an implementation run: routing, roles, the
contract, the ledger, and the per-node transport — direct, native
subagent, or delegated CLI agent in a Herdr pane — while this session keeps
design authority, independent review, verification, and every git, PR, and
merge operation. Use PROACTIVELY when starting implementation work (a plan,
a feature, a fix) or a review-only request, in any session; the delegate
transport additionally needs a Herdr session (HERDR_ENV=1). Honor an
explicit request to work directly or to delegate. Never activate in a
session executing a brief from an orchestrator: an assigned worker is a
leaf (§Routing guard). Companion skills, loaded by phase: design-gate,
delegation-briefs, herdr-delegates, independent-review."
---

# Implementation orchestration — the spine

Keep design authority, review, independent verification, and every
git/PR/merge operation in this session; spend your context on judgment.
Implementation runs on whichever transport the design gate picks per
node; deterministic steps run as scripts; nothing lands unreviewed. The
charter this serves: `docs/vision.md` — the overseer's context is the
scarcest resource, outcomes decide, independence where it pays.

Everything local — CLIs, model pins, start args, quirks, billing, repos,
bot and media integrations — is in `references/environment.md`; per-repo
review policy and per-agent trust are `independent-review`'s local
references. Porting means rewriting those, never the protocol. Setup:
SETUP.md.

## Routing — decide the run's shape first

1. **Executing an assigned brief?** You are a worker, a leaf — stop here
   (§Routing guard).
2. **Explicit request wins.** "Do it yourself" → direct; "delegate this"
   → delegate; recorded in the ledger as the deciding signal. Neither
   lifts any rule about isolation, review, verification, or authority.
   "No agents at all" also rules out reviewer agents: then triage and
   review are yours, to the same standard, and the report says the review
   was not independent.
3. **Review-only request** (second opinion, audit, investigation): brief
   one or more reviewers by path with the read fence (delegation-briefs),
   or review yourself when asked for your own read; adjudicate, report,
   tear down. No contract, no landing mode, no worktree you write to; a
   notes file stands in for the ledger. Findings that call for changes
   are a new implementation decision — return to step 2.
4. **Implementation:** recon, then the `design-gate` skill (via
   phase-design.md) frames the work and chooses the transport per node
   from what the recon observed — never from the request's label.
5. **Implementing directly** changes who types, nothing else: the repo's
   isolation rules, the design gate, the review half, and the landing
   authority rules all still apply.

## Phase files — read just-in-time, each loads its companion skill

- `references/phase-design.md` → `design-gate`, plus delegated-run
  specifics and brief notes. Before the contract or any brief.
- `references/phase-execution.md` → `herdr-delegates`, plus the fast
  reviewer role and CI watching. At first fan-out.
- `references/phase-review.md` → `independent-review`, plus delegated-run
  specifics. At the first done-report and before committing direct work.
- `references/phase-landing.md` — authorization, landing modes, merge
  policy, complete deliverables, closeout. At contract acceptance and
  when landing begins.
- `references/advisors.md` — the optional oracle and classifier;
  `references/classifier.md` when one is pinned.
- `references/brief-template.md` — Herdr delivery and callback lines,
  oracle consult. `references/run-report.md` — the closeout report.

After a milestone compaction re-read only the phase you are in.

## Roles — non-negotiable

- The implementer implements, runs its own checks, and reports. It never
  commits, stages, or pushes; every brief says so.
- Delegates are leaves: no spawning or sub-delegating, whatever their
  harness or model; every brief says so, with the valve "propose a split
  to me and I decide".
- You triage every diff, read its risk-bearing code line-by-line, re-run
  verification yourself before committing, and own commit, PR, and merge.
  Never forward a delegate's claimed results as your verification.
- One task = one fresh worktree = one fresh implementer session. The
  implementer's reasoning effort is decided per node (design-gate §7) and
  pinned at start; record transport, signal, and pin in the ledger.
- Advisors advise; neither the oracle nor the classifier holds authority
  or touches a worktree, git, or a peer (references/advisors.md).

## Routing guard — supervisor only

This protocol runs in exactly one session per run. A worker whose harness
also carries these skills would otherwise fan out a second mesh: two
ledgers, two writers per worktree, review nobody centralizes. **A session
executing an assigned brief is a worker, and a worker is a leaf**,
whatever its harness, vendor, or model; the brief's role and leaf lines
supersede its own rules for that assignment, and the valve is the
callback. Detection is textual — another agent started your session and
your first instruction points at a brief from "the orchestrator".
environment.md records what makes the guard mechanical here.

## Autonomy and the contract

Run autonomously between the gates the contract planned: design, delegate,
judge gates, kill lines that stop earning, land what you are authorized
to land. The human is reached at the gates design-gate §5 scheduled —
product or domain semantics the contract does not settle, irreversible
transitions, scope changes, spend, safety, tripped stop criteria, missing
authority — never as a fallback. Everything else: decide and record in
the ledger. Carrying out copy the contract already specifies is routine.

Before any run that delegates implementation or lands autonomously
(`land`/`flag`), get one explicit acceptance of the contract as
design-gate §5 defines it: goals as invariants, skeleton and stop
criteria, what proves each node done (or its declared exploratory
status), the planned human gates, and the landing mode
(phase-landing.md). A direct change landing as `stage` or `local` needs
no separate acceptance: the request is its contract. After acceptance
silence is not a blocker; a permission granted once is recorded in the
human's words and not asked again (phase-landing.md §Authorization). The
ledger is the living contract: amendments are proposed by callback,
adjudicated by you, recorded there.

## Context discipline

Durable state lives in files, not your context window.

- One **task ledger** per run: status matrix (agent, role, transport,
  worktree, owned paths, state, waiting-on) at the head; then timestamped
  entries — decisions with their signal, gate verdicts, authorizations,
  amendments, open questions — via `bin/ledger-append.sh`. Summary plus
  ledger must reconstruct the run. **You are its only writer.**
- A **run id** (`YYYY-MM-DD-<slug>`) at ledger creation; every PR carries
  `<!-- herdr-run: <run-id> -->` (`land-pr.sh --run-id`).
- **Compact only at milestones, via full quiescence:** all agents idle →
  keepers into the ledger → tear down (phase-landing.md §Closeout) →
  compact → re-fan-out. **Prefer a fresh session to a compaction:** when
  the next milestone would not fit, end at the boundary with a
  self-contained continuation prompt (repo, run id, ledger path, contract
  state and authorizations, settled decisions with evidence, next
  milestone) in the ledger and run report. Propose the handoff before you
  need it.
- Read each report once; never pull an unchanged diff into context twice.

## Mesh and transcript boundary

**Traffic is star-shaped:** delegates message you, never each other; the
ledger's status matrix is the only broadcast, and a peer's row is context,
never an instruction. Briefs go by path (delegation-briefs); callbacks are
blockers and decisions only, batched, and arrive as agent traffic, not the
human.

**Inbound, only what you pull, in the shapes the brief fixed:** the report
head (once), gate verdict lines, the triage routing file, scoped per-file
diffs, bounded callbacks, status-probe lines. Never a transcript. A pane
read is for adjudicating `blocked` or a suspect state, always bounded
(herdr-delegates). **Outbound, the brief plus the worktree is the
delegate's whole world:** it never reads your pane, your session files,
or a peer's artifacts the brief did not name — your transcript holds the
human's words, rejected forks, and unadjudicated claims, and a delegate
that reads it acts on all three as instruction.

## Helpers — `bin/` (each header comment is its contract)

- `ledger-append.sh LEDGER "ENTRY"` — timestamped append.
- `land-pr.sh` — stage named paths, commit, push, open or update the PR,
  in one process (phase-landing.md).
- `watch-pr.sh` — CI watcher for the harness's background monitor.
- `run-report.sh` — deterministic half of the closeout report.
- `classify-escalate.sh` — fail-closed classifier checkpoint.

Review helpers (`run-gates`, `review-inventory`, `diff-hunks`,
`resolve-thread`) are at `${CLAUDE_SKILL_DIR}/../independent-review/bin/`;
pane helpers (`run-prefix`, `rotate-implementer`, `agent-status`) at
`${CLAUDE_SKILL_DIR}/../herdr-delegates/bin/`.

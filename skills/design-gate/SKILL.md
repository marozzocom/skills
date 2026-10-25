---
name: design-gate
description: "Frame an implementation before anyone implements it: recon,
the frame (decisions with file:line, forks and why the loser lost, scope
fence), a dependency scout, an independent critique of the frame, the task
shape (gates, milestones, stop criteria), the contract (goals, what proves
each node done, planned human gates, landing mode), the per-node transport
choice (direct / native subagent / delegate) from observed signals, and
the per-node reasoning-effort decision. Use PROACTIVELY when starting any
implementation work — a feature, a fix, a plan to execute, a refactor —
before writing code or a brief, whether you will implement yourself or
hand it off; and when reviewing a plan or ADR before it is executed. Never
activate in a session executing an assigned brief from an orchestrator."
---

# Design gate

Nothing downstream corrects a wrong frame. The failure this gate exists
for: one agent pre-decides a fork, gets no critique, implements its own
answer faithfully, and every gate goes green. So the frame is written
down, cited, critiqued by someone who did not write it, and only then
built — whoever builds it.

Size the gate to the open questions. A direct change with no open fork
needs one frame line in the ledger or notes and no fan-out; a feature
with three forks needs the full pass. Never skip the gate because the
request sounds small: "quick fix", "hotfix", and "one file" describe the
request, not the work.

## 1. Recon before anything

Read the code the change touches and the code it depends on, in your own
context or via read-only scouts whose result is a summary. Every later
decision is made from what the recon showed, never from the request's
label or a pre-recon guess — a guess is a self-prediction at the moment
you know least.

**Point a scout at the dependency, not just your own code.** Someone
reads the source or typings of what you build on: what it guarantees, its
normalisation and removal semantics, what hooks it already exposes,
whether it solves this outright. A frame built on an assumed library
contract passes every gate; the hand-rolled substitute looks correct in
review because the reviewer shares the assumption. Search for the
underlying API, not only the framework hook that wraps it.

## 2. The frame

State, in the ledger or notes:

- what the task asks, in one or two sentences;
- each pre-decided decision **with its supporting `file:line`** — a
  decision without a citation is a question, and goes to a scout, a
  reviewer, or the human;
- the forks considered and why each loser lost;
- the scope fence: what is explicitly not touched, and why.

Decide where the better option is still available: recon before the
frame, the frame before any brief, cheap and reversible actions ahead of
expensive and irreversible ones, each alternative kept open until the
evidence that closes it is written down. A default is a considered
starting point, never the residue of exhaustion. If you later find the
only options are "stop" and "force it", the error was here; the run
report names where.

## 3. Critique the frame — by someone who did not write it

Hand the frame to a reviewer that has not seen your reasoning — a fresh
subagent, a pane-hosted reviewer, or on a trivial frame your own re-read
against the code — with one question: *"which of these decisions is
wrong or under-considered, and what did I not consider?"* One reviewer
per open question where there are several. If the repo ships a
plan-review skill, run it on the frame here too. Settle every hedge the
critique raises by evidence (read the installed source, or make it fail)
before the frame is final. Record the critique's findings and your
disposition of each.

## 4. Task shape — gates, milestones, stop criteria

Work runs as a layered graph: fan out a layer, collect at a **gate**,
judge, then brief the next layer — or stop.

- **Gates are where re-planning and killing happen.** A gate passed
  mechanically is not a gate. Briefs for the next layer are written after
  judging this one; briefs written earlier are fiction.
- **Each gate lands a reviewable artifact** (a merged PR or an
  integration-branch commit), never a pile of dirty worktrees. Each
  node's diff is reviewable in one sitting.
- **Depth over width.** Reviews serialize through you, so two or three
  concurrent writers is the practical ceiling; read-only fan-out (scouts
  early, reviewers late) is conflict-free and cheap. Concurrent writers
  need disjoint file sets.
- **Stop criteria are explicit and observable:** "if the migration
  touches more than N call sites, stop and report"; "if the dependency
  does not expose X, stop and re-frame".
- What cannot be a sequence of landable gates is a multi-session project.
  Plan it as one, with a continuation point at each milestone.

## 5. The contract — accepted once, then lived in the ledger

Before implementation that is delegated or lands autonomously, get one
explicit acceptance of:

- **Goals**, and acceptance criteria stated as **invariants**, not
  exhaustive specs: "no route reachable without an RBAC check", "module
  X's public surface unchanged", named gates green.
- **The graph skeleton** and stop criteria from §4.
- **What proves each node done.** A node is briefed only when the
  contract already names the checks whose green output settles its
  invariants, with their owners. If that cannot be written, the work is
  not ready: the next step is a scout or another design pass, not an
  implementer. The one exception is declared, never implied: an
  **exploratory node** aims at a "v0", says so, and states what it is
  meant to teach and how it will be judged (a demo, a measurement, a
  decision it unblocks). Exploratory work still gets independent review;
  what it skips is formal acceptance, not scrutiny.
- **Planned human gates.** Decide now where the operator will want a
  say, from what the work touches — user-facing product or domain
  semantics the contract does not settle, irreversible transitions,
  scope changes, spend — and schedule those as gates with the question
  framed and the options costed in advance. Reaching the human is then a
  step the run was built around, never an escape hatch. Between those
  gates you run autonomously; silence is not a blocker; a permission
  granted once is recorded and not asked again. A question that was not
  planned is itself a finding: record why the contract missed it.
- **Landing mode** and the authority it rests on (the landing skill or
  the repo's own rules say which modes exist and who may grant them).

Pin interface contracts only at seams where two parallel implementers
meet; everywhere else amendment is the normal path — the implementer
proposes, you adjudicate, the ledger records. A direct change that lands
as a staged PR or stays local needs no separate acceptance: the request
is its contract, but §2 and §3 still run.

## 6. Transport per node — from observed signals

Choose, per node, who implements, from what the recon showed. Record the
choice and the deciding signal as one ledger line per node, including
direct ones; the run report's per-node table is rendered from these.
An explicit request from the human ("do it yourself", "delegate this",
"no agents at all") wins and is recorded as the signal.

| Transport | Pick when | Not when |
|---|---|---|
| **Direct** — you type, in the repo's isolation (its worktree and branch convention, never the user's checkout unless the repo says so) | one app or package, single-digit files, nothing shardable, sequential and dependent, recon already loaded the code; or the deliverable is prose whose content is your own judgment (a policy, a design note, a review) | the surface to read exceeds what should stay resident in your context |
| **Native subagent** — your harness's own worker: fresh and worktree-isolated for writes, a fork for a context-dependent sequential step, a read-only explorer for reads | read-only fan-out (scouts, triage, repro hunts, checklist passes); a self-contained write whose brief fits one message and whose result is a summary; a critique or review that must be independent of the author and same-family is acceptable | a different model family is required; the human wants to watch and steer; the node must survive a session boundary |
| **Delegate** — an external agent in its own process (a terminal pane, another vendor's CLI), pinned model and effort | a different vendor is wanted for decorrelated review or for implementation on risk-bearing code; the billing path makes the implementer materially cheaper; the run spans sessions or needs the ledger-and-continuation machinery; the human asked to watch or to delegate | one-node tasks with no cross-family need: the overhead is measured and buys no design improvement |

Signals that favour fan-out, whatever the transport: two-plus disjoint
file sets that could run in parallel; more than one landable milestone; a
migration, sweep, or audit across many call sites; a plan or ADR that
already breaks the work into phases. Signals that favour direct: all of
the direct column at once. When signals conflict, prefer the transport
that keeps more options open and record the conflict. Urgency is not a
signal either way; an urgent fix gets the same recon, just a shorter one.

This choice gates *implementation* only. It never switches off §3 or the
independent review of the result: typing the code yourself changes who
implements the frame, not whether the frame is right or whether someone
else reads the diff.

## 7. Reasoning effort per node

Whoever implements, decide the node's reasoning effort here, where the
frame is known, and record it beside the transport. Use the default
effort for well-specified slices whose frame cites `file:line`,
mechanical sweeps, test-first briefs, docs, and fix rounds that name the
exact error. Escalate when the node carries any of:

- security or authorization semantics;
- concurrency, ordering, or cache-coherence invariants;
- data integrity and irreversible transitions — deletion, migration
  rollback, idempotent replay, deploy-ordering compatibility — even when
  the edit is mechanically uniform;
- a contract two parallel implementers must meet;
- a named ambiguity where the implementer must propose the shape first;
- a migration whose call sites are not mechanically identical;
- a second fix round on the same node after a red gate, once you have
  ruled out a wrong frame, stale evidence, and environment failures —
  diagnose first; escalate for unresolved reasoning only.

Never size effort by line count or repository size. The signal list is
reasoned, not measured: the run report records which escalations paid (a
fix round avoided) and which defaults failed (a second fix round on a
default node), and the list is pruned from that.

## Output of the gate

In the ledger or notes, before any implementation: the frame (§2), the
critique and its disposition (§3), the skeleton and stop criteria (§4),
the accepted contract or the line "request is the contract" (§5), and one
line per node with transport, signal, and effort (§6–7). If writing these
takes longer than the change itself, that is information: the change was
not as small as it looked.

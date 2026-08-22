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
escalation reviewers. Per-repo review checklists:
`references/review-checklists.md`. Per-agent trust calibration:
`references/agent-trust-profiles.md`. Porting to another machine or org
means adapting the references — never this file.

## Task fit — check the lower bound, after recon

§Task shape bounds the top ("too big for one run"). This bounds the bottom.
Delegation has a fixed overhead — a brief, report round-trips, a worktree, a
pane — and on a small, well-specified change that overhead is most of the cost,
with nothing to amortise it against.

**Do not try to answer this up front.** Sizing a task before reading the code
asks for a calibrated self-prediction at the moment you know least, from the
same judgment that writes the frame, under a standing instruction to prefer
delegating. That gets rationalised, not evaluated. Decide at the moment you
already stop to look around: the design gate's recon pass. By then the signals
are observable rather than guessed.

Delegate if **any** of these is true of what recon actually found:

- the work splits into two or more disjoint file sets that could run in parallel
- it needs more than one landable milestone
- it is a migration, sweep, or audit across many call sites
- the surface you would have to read to do it yourself is more than you want
  resident in your own context
- a written plan or ADR already breaks it into phases

Implement directly if **all** of these hold: one app or package, a single-digit
file count, nothing shardable, no migration character, and recon already put
the relevant code in front of you.

**Bias toward delegating when it is genuinely ambiguous.** The two errors are
not symmetric — delegating a small task wastes some latency and orchestration
tokens, while not delegating a large one risks a blown context and an abandoned
run. Decline only when the negative signals are clearly met.

**An "implement directly" verdict does not switch off the review half.** §Review
(tiered read, checklists on the fast reviewer), independent gate re-runs, and
git ownership all still apply — that half pays for itself either way, and
keeping it means a wrong verdict here costs almost nothing.

Record the verdict as one line in the ledger, naming the signal that decided
it. If it takes more than a line to settle, that is the signal: delegate and
move on.

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
  §Review), re-run the verification commands yourself before committing, and
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
graph skeleton (§Task shape), and the stop criteria. After that acceptance,
silence from the human is not a blocker.

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

## Task shape — graphs, milestones, gates

Beyond a single fan-out, work runs as a layered graph: fan out a layer,
collect at a **gate**, judge, then brief the next layer — or stop.

- **Decide up-front:** goals, a feasibility scout pass when there's real
  uncertainty, the layer skeleton ("scouts → design gate → 2 implementers →
  review gate → integration slice"), and explicit stop criteria ("if the
  scouts find the migration touches >N call sites, stop and report"). This
  is the contract the human accepts once.
- **The design gate is the default first gate.** Layer 1's brief carries
  essentially all the design content, so it is the one artifact nothing
  downstream can correct — an implementer faithfully implements a wrong
  frame. Before writing it: fan the fast reviewer out over the open
  questions, one agent per question ("where does this value come from and
  who consumes it", "what does the existing guard actually accept", "which
  tests cover this path"), read what comes back, then state the frame in the
  ledger — what the task asks, each decision you are pre-deciding **with the
  `file:line` that supports it**, the forks you chose between and why the
  loser lost, and the scope fence. A decision with no citation is not a
  decision, it is a question: send it to a scout, the reviewer, or the human.
  Then hand the frame itself to the fast reviewer — *"which of these
  decisions is wrong or under-considered, and what did I not consider?"* —
  before any implementation starts. Scouts and that critique are read-only
  and near-free next to the fix round a wrong frame costs.
- **Point at least one scout at the dependency, not just at your own code.**
  The failure this prevents is silent: a frame built on an *assumed* library
  contract, faithfully implemented, passing every gate. Send someone to read
  the source or typings of whatever you are building on and answer — what does
  it actually guarantee, what are its normalisation and removal semantics,
  what hooks does it already expose for the thing you were about to hand-roll,
  and does it solve this outright. A gate that only asks "what does our code
  do" cannot surface any of that, and the resulting hand-rolled substitute
  looks correct in review because the reviewer shares the assumption.
- **Write just-in-time:** the actual briefs for layer N+1, only after
  judging layer N at its gate. Briefs written before the previous layer ran
  are fiction. Gates are where re-planning and killing happen — a gate
  passed mechanically isn't a gate.
- **Results travel by file.** Briefs already go by path; reports do too —
  the brief names a `$REPORT_FILE`, the next layer's brief says "read
  `<report>` first". You judge reports; you don't ferry them through your
  context.
- **Sizing rule:** each node's diff must be reviewable in one sitting, and
  each gate should land as a reviewable artifact — a merged PR or a commit
  on an integration branch — not an accumulating pile of dirty worktrees.
  Width stays 2–3 implementers (reviews serialize through you, see §Parallel
  implementers); graphs extend depth, not width. A task that can't be
  expressed as a sequence of gates each producing a landable artifact is too
  big for one run — it's a multi-session project and gets planned as one.

## Context discipline — the ledger, and compacting at milestones

Durable state lives in files, not in your context window.

- Keep a **task ledger** file (scratchpad or repo, one per run): graph state,
  per-node status, decisions made, gate verdicts, contract amendments, open
  questions. Update it as you go. Once the ledger is authoritative, losing
  conversational context is survivable — summary plus ledger reconstructs
  the run.
- **Head the ledger with a status matrix** — one row per live agent: name,
  role, worktree, the paths it owns, current state, what it is waiting on.
  The multiplexer already exposes liveness to every pane (`herdr agent
  list`), so what the matrix adds is *semantics*: who owns which files and
  which decisions are settled. Name the ledger path in every brief as
  read-only shared context. **You are its only writer** — a delegate that
  writes it, or that acts on a peer's row instead of asking you, has become
  a second orchestrator.
- **Compact only at milestones, via full quiescence:** all agents idle →
  merge everything worth keeping into the ledger → tear down panes and
  worktrees (§Teardown order) → compact → re-fan-out from the next milestone
  with fresh sessions and worktrees. Never compact with agents in flight.
  Teardown-before-compaction also means a context loss can never orphan a
  live agent.
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
not progress narration."* Callbacks arrive in your session formatted like user
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

## Briefs

Use `references/brief-template.md`. The load-bearing parts, learned the hard
way:

- **Reading order for authoritative sources** (repo rules → plan/ADR → named
  key files), and an explicit scope fence ("do NOT touch X — that is a later
  slice").
- **Verification floor** including the repo's commit-free gate runner when one
  exists (listed per repo in `references/review-checklists.md`). Without it,
  gate failures surface at your commit step and cost a full round-trip each.
- **"Done means" clause**: the invariants that must hold plus the exact
  commands whose green output proves them. Acceptance is on evidence, never
  narrative — the report carries that output verbatim, and you re-run the
  gates yourself before committing.
- **Leaf rule** with the escalation valve (standard line in the template):
  no spawning or delegating; propose a split to the overseer instead.
- **Report format**: files changed, verification output verbatim, what cannot
  be verified in the sandbox (it must say so rather than approximate), and any
  plan/code drift. The implementer reports drift honestly when asked; it
  will not volunteer it unprompted (`references/agent-trust-profiles.md`).
- For decision-heavy work, instruct: *"if the contract/shape is ambiguous,
  propose it to me BEFORE implementing."* Implementers comply, and a
  two-minute design exchange beats a rewrite.
- **Evidence settles claims, not just gates.** The acceptance-on-evidence
  rule above covers gate output; extend it to every behavioural claim the
  work rests on — what a library does with an absent value, what a hook
  reports while loading, whether an identity is stable across renders.
  Whoever makes the claim settles it, by reading the installed source or
  making it fail; ask for a demonstration, not an opinion, and say so:
  *"if you think this instruction is wrong, answer with evidence rather than
  changing the code."* A hedge — "I'm not sure whether this always mounts
  after the cache is warm" — is an unsettled claim, not a weak finding. Those
  are the highest-yield things a reviewer says. Settle them.
- **Fix rounds and re-reviews are briefs**, bound by everything above. They
  are as capable of introducing a defect as the original brief — more so,
  because nothing reviews them — so they carry the settled decisions *and the
  evidence that settled them* forward, and they say plainly that a settled
  decision may be refuted with evidence but not merely re-raised.

## Waiting and lifecycle

- **`idle` is ambiguous on a fresh session** — it means both "finished" and
  "never started", so a prompt that landed in the composer unsubmitted looks
  exactly like a turn that completed instantly. Confirm the turn actually
  began (status `working`, or the CLI's turn counter advanced — per-CLI
  signal in environment.md) before you turn your attention elsewhere. An
  agent nobody confirmed can sit stalled for as long as your next deep read
  takes.
- Watch turns with `herdr agent wait <name> --timeout <ms>` in a background
  shell; it settles on `idle`/`done`/`blocked`. `blocked` means an approval or
  question UI — read the pane (`herdr agent read <name> --source visible`),
  adjudicate, `send-keys` the choice. After a dialog interaction, check the
  composer for stray characters before the next prompt (send-keys leftovers
  prepend to your next message).
- On macOS, long-running background watchers (`gh pr checks --watch`) get
  QoS-killed. Poll CI with a Monitor-style loop that emits each check result
  and exits when all settle, instead of one long-lived watch process.

## Verification ownership — the verdict decides the runner

Who runs a check is decided by where its verdict lives:

- **Deterministic checks** (tests, type-check, lint, format, gate runners) —
  the verdict is in the exit code, so the runner is interchangeable: run
  them twice. The implementer runs them in its own loop (feedback stays
  local; lint/type fixes are mechanical and stay with the implementer or the
  cheapest worker). You re-run at the gate — that re-run is the acceptance,
  the implementer's run just saves round-trips.
- **Judgment checks** (UI verification, visual/UX QA, semantic review,
  accessibility beyond automated scans) — split into three parts with
  different owners. The **standard** is centralized and written (repo
  guidelines/checklists — a quality bar that lives in one model's head isn't
  a standard; written, it constrains any agent, model, or human equally).
  The **evidence** is delegable: screenshots, preview URLs, recordings,
  structured observations. The **verdict** stays with you, or one named
  judge per domain — never with each implementer privately interpreting the
  standard, which yields a fragmented product where every diff individually
  "passed".
- Delegates produce evidence, never clearance: an implementer's "UI looks
  right" is a report of what it did, not a verification.
- The who-verifies-what matrix is per-environment: each repo's entry in
  `references/review-checklists.md` names the checks, runners, verdict
  owners, and evidence types. Record per-run deviations in the ledger so
  "who verified this?" is always answerable.

## Review — tiered: you keep judgment, delegate I/O

The review invariant, stated honestly: every diff is **triaged**,
risk-bearing code is read line-by-line by you, mechanical code is verified
by tooling plus a delegated sweep. For a 200-line auth change nothing
changes; for a 2,000-line rename it's the difference between a burned
context window and a ten-minute gate.

On a done-report, first send the fast reviewer a **triage pass**:
*"Classify this diff hunk-by-hunk — mechanical
(rename/generated/lockfile/snapshot), routine, or risk-bearing (auth, data,
contracts, concurrency) — with file:line. Do not edit anything."* Then:
deep-read the risk-bearing set yourself, spot-check the routine set, and
accept the mechanical set on gates green + type-check
green + a clean sweep. One asymmetry is non-negotiable: the triage may
*escalate* a hunk to risk-bearing but never demote one you'd call risky —
misclassification toward "mechanical" is the expensive failure, so when in
doubt you read it.

Order matters as much as the tiers. The triage lands **before** your deep
read — routing your attention is its whole purpose, and a triage that
arrives while you are already reading everything has bought nothing. Any
checklist or aspect pass runs on a **settled** tree: findings against a
half-applied fix round are noise, so park a reviewer rather than let it
review a tree that does not exist, and re-brief it with what changed when
you unpark it. Where the brief names several distinct risk surfaces, fan out
one reviewer per surface — contracts, async and loading states, tests, the
repo's own checklists — instead of asking one agent for all of it; the frame
already enumerated the surfaces. Reviewers are read-only, so this width is
free of conflicts.

Also delegable to the fast reviewer as mechanical I/O: recon before
briefing, repro hunts, collecting CI results, cross-file consistency sweeps.
What never leaves you: design conformance, security semantics, gate
verdicts, and adjudicating findings — yours, the reviewers', or the
implementer's own.

How far to trust each delegate's claims is recorded per agent kind in
`references/agent-trust-profiles.md` — consult it when deciding what to
independently verify. A new agent kind starts at zero trust (verify
everything) and earns a profile entry from verified behavior.

## Review checklists — centralized with you, run on the fast reviewer

If the repo ships review skills or checklists — guardian skills, review
sections inside a rules file, testing-review docs — implementers never run
them themselves; the brief says so explicitly, overriding any repo rules file
that tells agents to self-review. Centralizing the pass in your session is
what makes results consistent: one reviewer configuration gates every
implementer's work instead of each CLI's variable self-review, and parallel
implementers stop burning tokens duplicating the same checks.

`references/review-checklists.md` maps each repo on this machine to its
checklist sources, path→checklist mapping, and escalation rules. For an
unmapped repo, discover them (rules file, `.claude/skills/`) and add the
entry.

On a done-report, run the applicable checklists through the fast reviewer,
alongside your own tiered read (§Review):

- Map changed files to checklists per the repo's entry in the reference file.
- Brief the reviewer per checklist (batch small ones): *"Read `<doc path>` and
  apply it as a review checklist to the changes in `<worktree>`
  (`git -C <worktree> diff` — the tree is intentionally dirty). Report only
  actionable findings with file:line, or 'no findings'. Do NOT edit anything,
  even if the checklist tells its reader to auto-fix."*
- The reviewer is read-only in a worktree it does not own. Checklist fixes
  route to the implementer that owns the worktree as a normal fix round — never
  two
  writers in one tree.
- Re-run the affected checklist after each fix round.

For security/authorization checklists, and for "no findings" on any diff
touching auth or permissions, verify the semantics yourself or escalate that
one domain to the stronger reviewer the repo's entry names. That is the
model-routing lever: the fast model by default, a stronger model where a
confidently wrong "clean" verdict is the expensive failure.

## Fix rounds

Send failures back to the implementer with constraints, not just symptoms:
name the gate/error verbatim, state what must NOT change (don't weaken a
proof, don't touch baselines, no unsafe casts), and require the re-run output
verbatim.
When a quality gate flags something, first ask whether the flagged thing
should exist at all (an unconsumed preload, a test restating literals) —
"make the gate pass" is the wrong instruction when "delete the thing" is
available.

## Review threads — close the loop yourself

After a review comment is addressed (yours, a review bot's, or a human's), the
thread gets a reply naming the fix commit, then gets resolved — an addressed
finding left "unresolved" reads as unhandled and re-derails the next
reviewer. Only resolve what was actually fixed or was verified wrong (say
which); leave explicitly-deferred items open. The mechanics, since `gh` has
no native resolve:

```bash
# Reply in-thread (id = the finding comment's databaseId)
gh api repos/<owner>/<repo>/pulls/<num>/comments \
  -f body="Fixed in <sha>: <one line>." -F in_reply_to=<id>

# Thread ids, then resolve
gh api graphql -f query='query { repository(owner: "<owner>", name: "<repo>") {
  pullRequest(number: <num>) { reviewThreads(first: 50) { nodes {
    id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
gh api graphql -f query='mutation { resolveReviewThread(
  input: {threadId: "<PRRT_...>"}) { thread { isResolved } } }'
```

## Preview deployments — opt in when a live URL earns its keep

Some repos offer per-PR preview deployments; which ones, the opt-in
mechanism, and the budget are per repo in `references/environment.md`. Opt
in when a reviewer or verification step benefits from a live URL: UI-facing
changes, client+backend pairs whose integration is the point, anything you
would otherwise screenshot from a local run. Skip it for docs, tooling,
mechanical sweeps, and CI-only changes — previews spend a bounded budget.

## External review bot — final pass, sparingly

An external PR review bot (which one, its enablement, and its trigger/poll
commands: `references/environment.md`) can serve as a last outside pass.
Runs are typically usage-billed — treat it as an escalation spent on
residual risk, never a pipeline stage.

Trigger at most once per PR, after the checklist pass and your own tiered
review are clean and the PR is open, and only when at least one
condition holds:

- the diff touches auth/RBAC/permissions, payments/billing, data deletion or
  migration, or infra/deploy workflows;
- the change is cross-cutting enough that your review left residual
  uncertainty you can name;
- your review and the fast reviewer's second opinion disagree and reading
  the code did not settle it.

Routine UI/feature/docs/config PRs never qualify — the checklist pass is
their review.

Trigger it per environment.md, then poll for its review with short
foreground checks (macOS QoS kills long watchers).

Triage findings like checklist findings: verify each against the code before
acting — a bot's confidence is not evidence — route real fixes to the
implementer, then close each thread per §Review threads. Re-trigger only
when a fix round materially changed risk-bearing code; incremental-review
and effort-routing behavior is bot-specific (noted in environment.md).

## Fast reviewer / investigator / mechanical worker

Same protocol, different role. Start with the model pinned explicitly (exact
id, command, and the CLI's model-listing command in
`references/environment.md`) even when a config default exists; ids drift.
A freshly split pane may briefly reject the start with `agent_pane_busy` —
the shell isn't at its prompt yet; retry after ~3 s.

What the fast reviewer is for: independent second-opinion reviews, mechanical
refactors, sweep checks, and generic investigation tasks — codebase recon,
repro hunts, "which of these N files does X" questions — where its speed
beats waiting on a heavier model and a fresh set of eyes matters more than
deep design context. The current reviewer's verified strengths and failure
modes (empirical checking, over-investigation, and the like) are in
`references/agent-trust-profiles.md`. Scope review briefs tightly ("report
only actionable findings with file:line, or: no findings") and when it
drifts, `send-keys <name> esc` to skip the pending command, then prompt:
"stop investigating — write your final findings report now."

Approval behavior is CLI-specific; the current reviewer's recommended
settings and known-good configurations live in environment.md. The
invariants regardless of CLI: pre-allowlist recurring read-only tools so
reviews run without stalls; a blanket run-everything mode is acceptable only
for strictly read-only tasks, never for tasks that edit files; and keep
write-capable reviewer sessions on an approval mode that surfaces edits, and
adjudicate them like the implementer's.

The reviewer never touches git either — the role division and the fix-round
etiquette apply unchanged regardless of which CLI is in the pane.

## Parallel implementers

Multiple implementer agents work: unique names, one pane + worktree each,
disjoint file sets only (shared baselines/lockfiles conflict). Launch as many
sessions as the work shards into — implementer tokens are flat-rate, herdr
enforces name uniqueness (a collision fails loudly at `agent start`), and
the rotation helper is per-(name, pane) with no shared state, so
concurrent rotations don't interact.

Fan out early and late by preference, not in the middle. Scouts before the
frame and reviewers after a done-report are read-only, conflict-free, and
cheap, so that is where width buys the most; concurrent *writers* are the
expensive kind, paid for in merge conflicts and in confusion about which
tree a finding refers to.

The invariant that does not scale away: every diff is still triaged in your
session and its risk-bearing code read line-by-line before it lands (§Review).
Reviews serialize through you, so pipeline them — review each done-report as
it arrives while the other implementers keep working, and queue fix rounds per
worktree. In
practice that means 2–3 concurrent implementers, not a fleet; if review
throughput can't keep up, stagger task starts or shrink the pool — never
thin the review.

## Teardown — verified, in the right order

When the task's PRs are merged or abandoned, tear down in this order: close
agent panes FIRST (`herdr pane close <pane_id>` — positional ID, not a
`--pane` flag), remove worktrees SECOND. A surviving agent whose cwd was
deleted spins on "No such file or directory" errors until the user notices.

Verify teardown with a read, not the mutation: after closing, `herdr pane
list` must show only panes you did not create. Never suppress stderr in a
teardown chain and never emit your own success marker — `2>/dev/null` plus
an unconditional `echo CLOSED` once turned a wrong-syntax close into a
reported success and left three orphaned agents on screen. Gate any "cleaned
up" claim on exit status plus the post-state read.

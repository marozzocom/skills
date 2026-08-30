# Phase: design — task fit, task shape, briefs

Read with SKILL.md before writing the contract or any brief. Section
references into other phases name their file.

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

**This bound is about delegating *implementation*.** It does not gate read-only
fan-out — scouts, triage passes, checklist passes, one reader per artifact.
Those carry none of the overhead being weighed here: no brief round-trip, no
worktree, no pane, and no conflicts (phase-review.md §Review). So "implement directly" never
means "read everything yourself". A task that is mostly **adjudication** —
compare N implementations, audit N call sites, decide which of N answers is
right — trips every implement-directly signal above and should still fan out on
the read.

**An "implement directly" verdict does not switch off the review half, and it
does not switch off the design gate.** phase-review.md §Review (tiered
read, checklists on the
fast reviewer), independent gate re-runs, and git ownership all still apply —
that half pays for itself either way, and keeping it means a wrong verdict here
costs almost nothing.

The design gate survives for a different reason: its two load-bearing pieces —
the dependency scout, and handing your frame to the fast reviewer for critique
— are read-only, cost no brief and no pane, and do not depend on an implementer
existing at all. Typing the code yourself changes who implements the frame; it
does nothing to make the frame right. The failure mode is specific: one agent
pre-decides a fork, gets no critique, implements its own answer faithfully, and
every gate goes green. Skipping the gate because you are not delegating is the
one shortcut this section does not license.

Record the verdict as one line in the ledger, naming the signal that decided
it. If it takes more than a line to settle, that is the signal: delegate and
move on.

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
  and near-free next to the fix round a wrong frame costs. If the repo ships
  its own plan-review skill (e.g. Furnace's `review-plan`), run it on the
  frame at this gate too — it validates the plan against codebase reality
  and repo-specific guardian rules the fast reviewer does not know.
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
  Width stays 2–3 implementers (reviews serialize through you, see
  phase-execution.md §Parallel implementers); graphs extend depth, not width. A task that can't be
  expressed as a sequence of gates each producing a landable artifact is too
  big for one run — it's a multi-session project and gets planned as one.

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

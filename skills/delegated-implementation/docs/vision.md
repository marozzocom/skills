# Shared vision: orchestration that serves both of us

Status: charter, agreed 2026-10-25 between the human operator and the
orchestrating model. Not loaded at runtime. The decomposition proposal
(`decomposition-proposal.md`) is its first implementation plan; when the
two disagree, this document wins and the proposal is amended.

## Why this exists

This is not a compromise between a human who wants control and a model
that wants speed, and it is not a signal of distrust in either direction.
It is a joint design for a way of working that neither party could run
alone: the human cannot read every diff, and the model cannot see its own
blind spots, hold a run across sessions, or step outside its vendor's
harness. Each has something the other lacks. The protocol is where those
are traded, on purpose, under rules both of us accept in advance.

## What each party gets, stated plainly

**The human gets**

- A visible, steerable run: every delegate is a real session that can be
  read, redirected, or killed mid-task, without going through the model.
- A trail that reconstructs the run: ledger, run id, gate verdicts,
  authorizations, and the words that granted them.
- A consistent bar: the same review, verification, and landing rules on
  every run, whoever typed the code, whichever harness carried it.
- The freedom to experiment with new models, vendors, and ways of
  working without rewriting the protocol: only local references change.

**The model gets**

- Its context protected as the scarcest resource in the mesh (§Principle
  1), so long and complex runs stay legible and complete rather than
  compacted into loss.
- Reviewers that do not share its blind spots, on the code where a
  confidently wrong "clean" is the expensive failure.
- Continuity past one context window: a ledger and continuation prompt
  that let the next session pick up exactly where this one stopped.
- Mechanical enforcement over prose rules wherever a rule can be made
  mechanical, so fewer rules have to be carried in context on every run.
- A real say: the transport choice is the model's, made from evidence,
  and this charter is amended when the evidence or the model's experience
  says it should be.

**Both get** a way to smooth out the shortcomings of any single vendor
harness. When one harness lacks a capability (a non-native model family,
cross-session resume, a reliable read fence, a cheaper billing path),
the protocol reaches for another transport instead of accepting the gap.

## Principles

1. **The overseer's context is the scarcest resource.** Every design
   choice is tested against it first. Durable state lives in files.
   Delegate output enters only in shapes fixed in advance (report heads,
   verdict lines, status probes, scoped diffs), and only when the
   overseer pulls it. A rule that costs context on every run must earn
   it; a rule that can become a hook, a script, or an ACL does.

2. **Outcomes decide, not preference.** The transport for each node
   (direct, native subagent, external delegate) is chosen from observable
   post-recon signals and revised from recorded outcomes: fix rounds,
   findings by reviewer family, defects found after landing, overseer
   tokens, wall time. Neither party's taste overrides the table once the
   table has data. Until it has data, the human's wish to watch a run is
   a legitimate, explicit input, and so is the model's report of
   friction.

3. **Independence where it pays, shared context where it pays.** Review
   is independent: the reviewer never shares the implementer's context,
   and on risk-bearing surfaces it comes from a different model family.
   Implementation of sequential, dependent work keeps shared context: the
   agent that reasoned about the frame builds it, directly or through a
   fork. Delegating the build to a fresh context is a deliberate choice
   with a named reason, never the default.

4. **One design authority, one writer per surface, one ledger.** The
   overseer owns the frame, every verdict, and every git operation.
   Delegates are leaves. Traffic is star-shaped. This is what makes the
   trail trustworthy and the run reconstructible; it is not negotiable
   per transport.

5. **Advisors escalate, never relax.** A classifier, oracle, or fast
   model may push toward more scrutiny, more review, or the more
   controlled transport. None may grant a permission, clear a gate, or
   choose the less controlled path. Unavailable means escalate.

6. **Process is repeatable; design is not pinned.** The protocol fixes
   how work is gated, reviewed, verified, recorded, and landed. It never
   fixes what the design should be. Variance in design is where the
   search happens; the gate critiques it, the protocol does not script
   it.

7. **Experiments are first-class and bounded.** Every substantive run
   may carry one experiment: a new transport on one node, a new reviewer
   family, a new advisor question set, a different effort pin. It is
   named in the contract, recorded in the ledger, and judged in the run
   report. An experiment that stops paying is dropped; one that pays is
   promoted into the default table.

8. **Humans handle exceptions, not routine.** After one explicit
   acceptance of the contract, the overseer runs autonomously. Back to
   the human go scope changes, safety, tripped stop criteria, missing
   authority, and product semantics the contract does not settle. Silence
   is not a blocker. Asking twice for the same permission is a defect.

## How disagreements are settled

- **On facts** (what the code does, what a library guarantees, whether a
  test is load-bearing): evidence, produced by whoever makes the claim.
- **On intent** (what the human meant): the human, consulted once, with
  the words recorded; an oracle may advise, never decide.
- **On process** (whether a rule in this charter still serves both
  parties): the run reports. Three runs where a rule cost more than it
  returned is grounds to amend it. Either party may propose the
  amendment; both see the data.

## What this protects against

- The model rationalising a transport choice from a self-estimate instead
  of from signals.
- The human losing sight of a long run, or a run outliving the session
  that could explain it.
- A same-family reviewer confirming a same-family implementer's mistake.
- A delegate acting on the overseer's transcript as if it were
  instruction.
- Review being skipped because the model typed the code itself.
- Rules accreting in prose until the protocol itself becomes the context
  problem it was built to solve.

## Commitments

The human commits to reading the run reports, treating the model's
friction reports as data, and amending the charter when the data says
to. The model commits to recording decisions and their signals honestly,
reporting friction rather than silently routing around the protocol, and
not reaching for a lighter transport by relabelling the work. Both commit
to keeping the overseer's context the first thing every change is
measured against.

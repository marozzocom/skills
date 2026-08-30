# Agent trust profiles

Copy this file to `agent-trust-profiles.md` (gitignored) and maintain your
own entries. The profiles below are seeded examples from one machine's
verified observations — starting points, not facts about your setup;
re-verify after any model or version change.

How far each delegate's claims can be trusted, and what the orchestrator
must always verify independently. Entries record *empirically verified*
behavior on this machine — not vendor marketing. A new agent kind starts at
zero trust: verify everything until observed behavior earns it an entry
here, then record what was actually observed.

Trust here is never clearance. Even the best-calibrated delegate's report is
input; acceptance is on evidence (verbatim gate output re-run by the
orchestrator, triaged diff read, checklist pass) per phase-review.md §Review.

## Codex CLI — gpt-5.6-sol, reasoning high (implementer)

- **Drift reporting:** reports plan/code drift honestly *when the brief
  demands it*; does not volunteer it unprompted. Always require the drift
  section in the report format.
- **Verification claims:** runs tests it says it runs, but sandbox limits
  mean some verifications are approximated unless the brief forbids that —
  require an explicit "cannot verify here" list, and re-run every gate
  yourself before committing.
- **Design questions:** complies well with "propose the shape BEFORE
  implementing" for named ambiguities; without that instruction it picks a
  shape and moves on.
- **Always verify independently:** security/authorization semantics, and any
  factual claim about existing code the change depends on. Self-review is
  input, not clearance.

## Cursor CLI — cursor-grok-4.6-high-fast (reviewer / investigator)

- **"No findings" is grounded:** verified to go beyond reading — it executes
  library internals to check semantics empirically. A clean verdict is worth
  something on routine diffs.
- **But never for auth:** a confidently wrong "clean" on auth/RBAC/
  permissions is the expensive failure — those domains escalate to your own
  read or the stronger reviewer named in the repo's
  `review-checklists.md` entry, regardless of Grok's verdict.
- **Triage asymmetry:** its hunk classification may escalate to
  risk-bearing, never demote below your own judgment (phase-review.md §Review).
- **Over-investigates:** scope briefs tightly ("only actionable findings
  with file:line, or: no findings"); when it drifts, `send-keys esc` then
  ask for the final report.

## Bugbot (Cursor, account-side)

- Usage-billed escalation, not a pipeline stage — trigger conditions in
  phase-review.md §External review bot; mechanics in `environment.md`.
- **Confidence is not evidence:** verify every finding against the code
  before routing a fix. It surfaces real issues in cross-cutting diffs but
  also asserts plausible-sounding non-bugs with equal confidence.

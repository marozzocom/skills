# Phase: review — load the independent-review skill

Read at the first done-report, and before committing a direct
implementation past the light lane (SKILL.md §Routing). The review
half of this protocol lives in the **`independent-review`** skill, installed alongside this one: invoke it
(the Skill tool, or read `${CLAUDE_SKILL_DIR}/../independent-review/SKILL.md`)
and follow it in full. Its helpers are at
`${CLAUDE_SKILL_DIR}/../independent-review/bin/` — `run-gates.sh`,
`review-inventory.sh`, `diff-hunks.sh`, `resolve-thread.sh` — and its
local references hold this machine's per-repo review policy
(`review-checklists.md`: checklists, escalation domains, review
conventions, landing grants, safe sets, verification matrix) and
per-agent calibration (`agent-trust-profiles.md`).

What this protocol adds on top, for a delegated run:

- **The fast reviewer is a pane.** Start it with model and effort pinned
  (phase-execution.md §Fast reviewer); brief it by path with the read
  fence (brief-template.md); park it during fix rounds; it never touches
  git. Its verified strengths and failure modes are in
  agent-trust-profiles.md.
- **The implementer never reviews its own diff**, never runs the repo's
  checklists, and never receives the reviewer's brief — the implementer
  brief says so (phase-design.md §Briefs).
- **Verdict ownership is recorded in the ledger** per node: who reviewed,
  which vendor and model, what they were fenced to; deviations from the
  repo's verification matrix are ledger entries so "who verified this?"
  is always answerable.
- **The vendor lever is a routing decision you make here:** on
  risk-bearing surfaces, the reviewer pane preferably runs a different
  vendor than the implementer pane, pinned per environment.md; a
  same-vendor or same-model fallback keeps a fresh context and is
  recorded as such.
- **Report facts are checked by code, not by a classifier or a read**
  (SKILL.md §Transcript boundary); a configured classifier's triage
  cross-check (classifier.md) obeys the same escalate-only asymmetry.

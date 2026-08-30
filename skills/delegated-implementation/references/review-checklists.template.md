# Review checklists by repo

Copy this file to `review-checklists.md` (gitignored) and add an entry the
first time you delegate in a new repo. Machine-local map from repo → the
review checklists the orchestrator runs after an implementer's done-report
(SKILL.md §Review checklists). The skill body stays repo-agnostic;
everything repo-specific about reviewing lives here.

Each entry answers four questions: where the checklists live, how changed
files map to them, which domains escalate past the fast reviewer, and the
verification matrix — check → runner → verdict owner → evidence type
(SKILL.md §Verification ownership).

## [org/repo] (`[local path]`)

- **Sources:** [where the repo's review checklists/guardian skills live.]
- **Mapping:** [how changed file paths map to checklists; batching notes.]
- **Escalation:** [which domains' findings — and whose "no findings" — go
  past the fast reviewer to your own read or a stronger reviewer.]
- **Override note:** [if the repo's rules file tells agents to self-review,
  note that the implementer brief overrides it — review is centralized with
  the orchestrator.]
- **Commit-free gate runner** for brief verification floors: `[command]`.
- **Review conventions** (SKILL.md §Landing modes): [what the repo's process
  actually expects — branch protection, required reviewers, CODEOWNERS,
  required checks, review bots, the rules file's delivery section. If it
  expects other-human review, `stage` is the ceiling regardless of grant.]
- **Autonomous landing grant** (SKILL.md §Landing modes): [absent = denied,
  `stage` is the ceiling. To grant: "granted <date> by <source — repo agent
  docs section, or the user's explicit directive>", enabling `land`/`flag`
  under an accepted contract.]
- **Merge policy table** (SKILL.md §Merge policy) — default deny: auto-merge
  on green checks only when *every* changed path is in the safe set. Paths
  outside the safe set merge only under the grant above plus an accepted
  `land`/`flag` landing mode — otherwise they wait for the human.
  [Enumerate the repo's safe set here, or point at the repo rules file that
  carries the table.]
- **Verification matrix:**
  - tests / type-check / lint (`[gate command]`) → implementer runs in its
    loop, orchestrator re-runs at the gate (the acceptance) → verdict: the
    exit code.
  - [checklist kind] → fast reviewer runs → verdict: orchestrator
    adjudicates findings.
  - [high-risk domain] semantics → verdict: orchestrator's own read or the
    named stronger reviewer — never the fast reviewer alone.
  - UI verification → standard: [written guidelines doc]; evidence:
    [preview URL / screenshots]; verdict: orchestrator.

## Unmapped repos

Discover before reviewing: check the repo rules file (`AGENTS.md`,
`CLAUDE.md`) for review instructions or embedded checklists, then
`.claude/skills/` for guardian-style skills. If nothing exists, your tiered
read plus a tightly-scoped fast-reviewer second opinion is the whole pass.
Record what you find as a new entry above.

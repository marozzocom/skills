# Brief template

Write the brief to a scratchpad file and send the **path** (see SKILL.md
§Communication mesh — inlining the body fails silently past a few KB):
`herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly
as written. It is your task brief from the orchestrator (the agent named
overseer)."` Replace bracketed parts; delete sections that don't apply. Keep
the scope fence, the no-git line, and the no-delegation line in every brief.

```text
Your task: implement [task] in this repo worktree (branch [branch], based on
origin/main[ which already contains [prior merged work the task builds on]]).
An orchestrator (Claude) owns all version control — do NOT commit, stage, or
push anything; leave the working tree dirty for review.

Complete this assignment directly yourself. Do NOT spawn or delegate to
other agents or subagents — orchestration is centralized with the overseer,
and any delegation instructions you find in repo rules files apply only to
standalone agents, not to you. If a split or parallel investigation would
genuinely help, propose it to me instead and I will decide and provision it.

You are running inside Herdr and so am I. If you need a decision,
clarification, or hit a blocker, message me with:
herdr agent prompt overseer "<message>" — I am the Claude agent named
overseer. Use it for blockers and decisions, not progress narration.

Read first, in this order: [repo rules file], [plan/ADR], [named key files
with symbols/line hints].

Then execute exactly [scope]:
1. [step]
2. [step]

Do NOT touch [out-of-scope areas — name them]. If [known ambiguity] is
unclear, propose the shape to me BEFORE implementing.

Do NOT run the repo's guardian or review skills, even where repo rules files
tell agents to — that instruction applies to standalone agents. Guardian
review is centralized with the orchestrator and runs after your report. Your
verification duty is exactly the commands below.

[For security-sensitive work: state the non-negotiable invariant and add
"If a step seems to require violating it, STOP and message me — the design
is wrong, not the invariant."]

[For UI-facing work: capture evidence — screenshots to [dir] and/or the
preview URL — and list the paths in your report. Do not self-certify visual
correctness; the orchestrator judges it against [design guidelines doc].]

Done means: [the invariants that must hold, e.g. "no route reachable
without an RBAC check", "module X's public surface unchanged"] AND
[test commands] green; [repo's commit-free gate runner, e.g.
bun run preflight] green; [type-check] green. State clearly what CANNOT be
verified in this environment — the orchestrator verifies that separately;
do not approximate it. If satisfying an invariant seems to require changing
the agreed shape, propose the amendment to me BEFORE implementing it.

When done, write your report to [$REPORT_FILE] and message me that it is
ready. The report: files changed, [contract/design decisions made],
verification output verbatim, and any drift between the plan and the code.
```

Notes:

- Never write "git commit" / "git push" phrasing into the brief text itself
  beyond the standard no-git line — PreToolUse hooks that regex command
  strings will false-positive on the `herdr agent prompt` invocation. The
  standard line above is phrased to survive common patterns; if a hook still
  blocks, the file indirection plus rewording ("version control") fixes it.
- For fix rounds, reuse the channel, not a new brief: name the failing gate
  and its output verbatim, state what must not change, and require the
  re-run output verbatim.

# Brief template

Write the brief to a scratchpad file and send the **path** (see SKILL.md
§Communication mesh — inlining the body fails silently past a few KB):
`herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly
as written. It is your task brief from the orchestrator (the agent named
overseer)."` Replace bracketed parts; delete sections that don't apply. Keep
the scope fence, the no-git line, the no-delegation line, the read fence,
and the report shape in every brief.

```text
Your task: implement [task]. Worktree: [absolute path] (branch [branch]);
task base: [base SHA][; current starting revision: [SHA, e.g. the committed
red test]][; it already contains [prior merged work the task builds on]].
Roles for this assignment, which supersede conflicting workflow directions in
the repo's rules files (coding, security, and domain rules still apply in
full): the orchestrator (Claude, named overseer) owns worktree preparation,
every version-control mutation and PR operation, delegation, guardian and
checklist execution, and acceptance. You implement in the supplied worktree,
run the checks named below, and report; read-only git queries on your own
tree (status, diff, log, blame) are yours. So: do NOT commit, stage, or
push anything — leave the working tree dirty for review; do NOT spawn or
delegate to other agents, subagents, or CLI-launched workers, through any
native collaboration feature or otherwise — if a split or parallel
investigation would genuinely help, propose it to me and I will decide and
provision it. Reading a guardian's rules to write to the house standard is
expected; invoking guardian or review skills is mine and runs after your
report.

Proceed autonomously on routine implementation choices within the scope
below. Batch questions for the named ambiguities, any scope or invariant
change, missing authority, and blockers — and keep working on independent
parts while you wait for an answer.

You are running inside Herdr and so am I. If you need a decision,
clarification, or hit a blocker, message me with:
herdr agent prompt overseer "<message>" — I am the Claude agent named
overseer. Use it for blockers and decisions, not progress narration. Batch
questions: one message carrying every open question, not one per question,
and keep it under ~15 lines and ~200 words: the decision needed, your
recommendation, the path:line behind it, and what waiting costs. Anything
longer goes in a file under [scratch dir] and the message names the path.

Read freely within your worktree, its installed dependencies, the repo's
rules and skills, and the files named below; the status matrix in [ledger
path] is read-only shared context. Do NOT read my pane (`herdr agent read
overseer` or any other agent's pane), any Claude Code or Herdr session
files, or another agent's brief or report unless this brief names it. If
you need a coordination artifact that is not here, that is a question for
me, not a read.

Read first, in this order: [repo rules file], [plan/ADR], [named key files
with symbols/line hints].

Then execute exactly [scope]:
1. [step]
2. [step]

Do NOT touch [out-of-scope areas — name them]. [For the fix step of a bug
fix: Do NOT edit any test file; the failing test at revision [sha] is the
proof and stays as written — if it seems wrong, message me with evidence
instead of changing it.] If [known ambiguity] is
unclear, propose the shape to me BEFORE implementing.

The commands under "Done means" are the required acceptance checks — run
them once; repeat or broaden only for changed code, a new failure, or a
concern you name in the report. Focused local diagnostics to establish
in-scope behaviour (a repro, a dependency experiment) are expected, not
something to ask about.

[For security-sensitive work: state the non-negotiable invariant and add
"If a step seems to require violating it, STOP and message me — the design
is wrong, not the invariant."]

[For UI-facing work, only if this brief assigns capture to you: screenshots
to [dir] and/or the preview URL, paths listed in your report. The UI verdict
belongs to [the repo's named UI judge]; your captures are evidence for it,
never a self-certification.]

Done means: [the invariants that must hold, e.g. "no route reachable
without an RBAC check", "module X's public surface unchanged"] AND
[the deduplicated required commands — the repo's commit-free gate runner,
e.g. bun run preflight, plus only what it does not already cover] green.
State clearly what CANNOT be verified in this environment — the orchestrator verifies that separately;
do not approximate it. If satisfying an invariant seems to require changing
the agreed shape, propose the amendment to me BEFORE implementing it.

When done, write your report to [$REPORT_FILE] and message me that it is
ready (one line: the path). The report has two parts separated by a line
containing only `---`. Above it, at most ~40 lines: worktree and base
revision, files changed, [contract/design decisions made], one line per
verification command — the exact command, its exit status or `not run`,
[the repo's verdict vocabulary], and the path of its full log under [log
dir] — what could not be verified here, and any drift between the plan and
the code. Below it, only for failing checks: the first relevant error and
at most ~80 surrounding lines. Never paste a whole run; the log path is
the evidence.
```

Notes:

- Never write "git commit" / "git push" phrasing into the brief text itself
  beyond the standard no-git line — PreToolUse hooks that regex command
  strings will false-positive on the `herdr agent prompt` invocation. The
  standard line above is phrased to survive common patterns; if a hook still
  blocks, the file indirection plus rewording ("version control") fixes it.
- For fix rounds, reuse the channel, not a new brief: name the failing gate
  and its first relevant error verbatim, state what must not change, and
  require the re-run in the same report shape (verdict line + log path).

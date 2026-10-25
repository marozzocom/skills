# Briefs in a delegated run

The brief itself — load-bearing parts, template, report shape, two-brief
bug fixes, fix rounds — is the **`delegation-briefs`** skill. This file
holds only what a Herdr-pane delegate needs on top, and the oracle
consult.

## Delivery and callback lines for a pane

Write the brief to a scratchpad file and send the path
(herdr-delegates §Delivering briefs):

```bash
herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly
as written. It is your task brief from the orchestrator (the agent named
$PREFIX-overseer)."
```

Fill the template's `[overseer name]` with `$PREFIX-overseer` and its
`[callback channel]` with:

```text
You are running inside Herdr and so am I. Message me with:
herdr agent prompt [prefix]-overseer "<message>" — I am the orchestrator
agent named [prefix]-overseer.
```

The read fence additionally names the pane mechanics: "Do NOT read my pane
(`herdr agent read [prefix]-overseer` or any other agent's pane), any
agent harness's session files (mine or another agent's), or Herdr session
files." Never write commit or push phrasing into the brief text beyond
the standard no-git line — PreToolUse hooks that regex command strings
false-positive on the `herdr agent prompt` invocation; the file
indirection plus "version control" wording survives common patterns.

## Oracle consult

For the oracle pane (SKILL.md §Advisors). Same path delivery; the first
consult of a run carries the role paragraph, later ones only the
question block — the pane keeps its context for the run.

```text
You are the oracle for this run: an advisor to the orchestrator (the agent
named [prefix]-overseer) on what the human means and what they would want. You
advise; [prefix]-overseer decides. Read-only: do NOT edit files other than your
answer file, run version-control commands, start or message other agents,
or activate any delegation, orchestration, or review skill or protocol —
you are a leaf. Do NOT read any agent's pane, any agent harness's session
files, or Herdr session files; what the human said is quoted below.

Question: [the decision, one sentence].
Options: [A — …; B — …]. My current lean: [option] because [reason].
The human's words, verbatim: "[quote]" ([when/context]) …
Context: [ledger excerpt path(s), contract path, the one or two files that
matter].

Answer in [answer file], at most ~40 lines: your recommendation; your
confidence (high/medium/low) and what it rests on; what the human would
most likely object to in each option; what evidence would change your
answer. If the question itself is the wrong question, say so first. Then
message me one line: herdr agent prompt [prefix]-overseer "oracle: [answer file]".
```

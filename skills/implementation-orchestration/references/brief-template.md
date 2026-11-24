# Briefs in a delegated run

The brief itself — load-bearing parts, template, report shape, two-brief
bug fixes, fix rounds — is the **`delegation-briefs`** skill. This file
holds only what a Herdr-pane delegate needs on top, and the oracle
consult.

## Delivery and callback lines for a pane

Write the brief to a file in the run folder and send the path
(herdr-delegates §Delivering briefs; `hb` is its `herdr-backend.sh` helper,
which speaks whichever Herdr flavor the run is in):

```bash
hb tell <name> "Read $BRIEF_FILE in full and execute it exactly
as written. It is your task brief from the orchestrator (the agent named
$PREFIX-overseer)."
```

Fill the template's `[overseer name]` with `$PREFIX-overseer` and its
`[callback channel]` from `hb callback-line $PREFIX <agent-name>`, pasted
verbatim. In the TUI it tells the delegate to write a message file into
the run inbox (herdr-delegates §The run inbox); add:

```text
This is the only way to reach me, for every message including questions
and the answer to a later fix round: do not use Herdr commands, and a
reply typed into your own pane does not reach me.
```

Send the brief pointer, every fix round and every follow-up with `hb tell
<name> '...'`, never `hb prompt`: it appends the same instruction and stamps the time, so a
fix round cannot be answered in the delegate's own pane, and an
unanswered one shows up as a stall line.

In the desktop app it is the pull wording — write the report or questions
file the brief names, then end your turn — because some CLIs' tool shells
cannot reach the app's core. Name a questions file next to the report
file, and replace every "message me one line" step in the brief with
"end your turn"; you are watching the turn (herdr-delegates §Two flavors).

The read fence additionally names the pane mechanics: "Do NOT read my pane
(no pane read of [prefix]-overseer or of any other agent), any
agent harness's session files (mine or another agent's), or Herdr session
files." Never write commit or push phrasing into the brief text beyond
the standard no-git line — PreToolUse hooks that regex command strings
false-positive on the prompt invocation; the file
indirection plus "version control" wording survives common patterns.

## Oracle consult

For the oracle pane (references/advisors.md). Same path delivery; the first
consult of a run carries the role paragraph, later ones only the
question block — the pane keeps its context for the run.

```text
You are the oracle for this run: an advisor to the orchestrator (the agent
named [prefix]-overseer) on what the human means and what they would want. You
advise; [prefix]-overseer decides. Read-only: do NOT edit files other than your
answer file and your inbox message, run version-control commands, start or message other agents,
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
[TUI: message me one line, "oracle: [answer file]", as follows: [callback channel from `hb callback-line $PREFIX [prefix]-oracle`, verbatim].
App: end your turn.]
```

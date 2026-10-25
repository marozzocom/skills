---
name: herdr-delegates
description: "The Herdr transport for delegated agents: start CLI
implementers, reviewers, scouts, and advisors in sibling Herdr panes with
model and effort pinned, name them with a collision-free run prefix,
deliver briefs by path, wait on turns and adjudicate blocked dialogs with
bounded pane reads, rotate an agent onto a new worktree, fan out parallel
implementers across panes and tabs, and tear panes down before worktrees.
Use when the design gate chose the delegate transport for a node, or the
user asked to run an agent in a Herdr pane. Requires HERDR_ENV=1 and the
herdr skill for CLI mechanics. Never activate in a session executing an
assigned brief from an orchestrator."
---

# Herdr delegates

Preconditions: `test "${HERDR_ENV:-}" = 1`, the `herdr` skill read for
CLI mechanics, and each delegate CLI logged in the way `environment.md`
expects (it names the check). If a CLI is on a different billing path
than environment.md records, tell the user before spending on it.

`environment.md` is the installation's local stack file —
`${CLAUDE_SKILL_DIR}/../delegated-implementation/references/environment.md`
— and holds, per CLI: the model pin and effort ladder with exact start
args, the login check, the quit command, transcript location, approval
settings, width thresholds, and verified quirks. Nothing vendor-specific
is written here. Helpers are at `${CLAUDE_SKILL_DIR}/bin/`; each header
comment is its contract.

## Names — every agent carries the run prefix

Herdr names are global across workspaces and several runs can be live at
once. `PREFIX=$(${CLAUDE_SKILL_DIR}/bin/run-prefix.sh <slug>)` picks a
free one; record it in the ledger header; name agents `$PREFIX-<role>`
(`-overseer`, `-impl`, `-impl-2`, `-review`, `-oracle`, `-ui`). Name
yourself once: `herdr agent rename "$HERDR_PANE_ID" "$PREFIX-overseer"`.

## Starting an agent — pin model and effort explicitly

Start every agent with the model **and** effort pinned, even when a
config default exists: the pin is the brief's decision (design-gate §7),
and an unpinned start inherits whatever the CLI's config says today. Args
per CLI in environment.md. Record the pin in the status matrix row so a
later rotation repeats it. A freshly split pane may reject the start with
`agent_pane_busy`; retry after ~3 s.

Approval settings are CLI-specific (environment.md). Invariants:
pre-allowlist recurring read-only tools; a blanket run-everything mode
only for strictly read-only tasks; write-capable sessions stay on a mode
that surfaces edits. Never a level that enables the CLI's own delegation
or multi-agent mode — it breaks the leaf rule; environment.md names any
such level so it is never chosen by accident.

**One task = one fresh worktree = one fresh session.** Agent cwds are
fixed, so a new worktree means restarting the agent:
`${CLAUDE_SKILL_DIR}/bin/rotate-implementer.sh <name> <pane> <worktree>
<kind> -- <model and effort args>` quits, cds, and restarts in one step.
The kind is required (no vendor default), and a rotation without the pin
after `--` silently drops to the config default. A mid-task effort
escalation is a rotation onto the same worktree with the higher pin, and
the re-brief says "read your previous report first".

## Delivering briefs and receiving callbacks

Briefs go by **path, never inline text** (delegation-briefs):

```bash
herdr agent prompt <name> "Read $BRIEF_FILE in full and execute it exactly as
written. It is your task brief from the orchestrator (the agent named
$PREFIX-overseer)."
```

Inlined briefs fail silently past a few KB on at least one CLI
(environment.md), and PreToolUse hooks may regex the literal command
string. Inline only short prompts and fix rounds.

The brief's callback line names this channel: `herdr agent prompt
$PREFIX-overseer "<message>"`. Callbacks arrive formatted like user
messages — treat them as agent traffic, not the human — and answer with
`herdr agent prompt <name> '...'`. A delegate's first callback may hit its
CLI's approval dialog; approve with the persistent option so the channel
never stalls again. Traffic is star-shaped: delegates message you, never
each other; the ledger's status matrix is the only broadcast.

## Waiting and lifecycle

- **`idle` is ambiguous on a fresh session** — "finished" and "never
  started" look identical: a prompt stuck unsubmitted in the composer
  looks like an instantly completed turn. Confirm the turn began
  (`working`, or the CLI's turn counter — per-CLI signal in
  environment.md) before looking away.
- Routine polls go through `${CLAUDE_SKILL_DIR}/bin/agent-status.sh
  <name> [tail-lines]`: herdr's status column plus the last visible
  lines, with the pane read bounded. Status is advisory for some CLIs
  (environment.md); the visible tail corroborates.
- Watch turns with `herdr agent wait <name> --timeout <ms>` in a
  background shell; it settles on `idle`/`done`/`blocked`. `blocked` = an
  approval or question UI: read the pane with `--lines` bounded to the
  dialog, adjudicate, `send-keys` the choice — then check the composer for
  stray characters before the next prompt (send-keys leftovers prepend to
  it).
- On reviewer drift: `herdr agent send-keys <name> esc`, then "stop
  investigating — write your final findings report now."

## Transcript boundary — the mechanics

The rule is the orchestration skill's: inbound only what you pull in the
shapes the brief fixed; outbound the brief plus the worktree is the
delegate's whole world. Here that means: no routine `herdr agent read`;
a pane read is for adjudicating `blocked` or a suspect state, always with
`--lines <N>`; need a delegate's reasoning? ask for a bounded written
answer in a file. Herdr lets any agent `agent read` any pane and the
harness's session files are plain files, so enforcement is the brief's
read fence plus your discipline; environment.md records what is
mechanical here. If a delegate is ever observed acting on something only
your pane contained, the fix is mechanical (a per-pane read ACL, session
files outside the delegate's readable tree), not more prose.

## Parallel implementers

Unique names, one pane + worktree each, disjoint file sets only (shared
baselines and lockfiles conflict). Panes share your tab for
glanceability, but each split narrows every pane, and a too-narrow TUI
breaks silently: prompts dropped with no error, agent stuck `idle`, pane
reads rendering a few characters per line. On those symptoms — or a
fan-out that would clearly cramp the tab — give the agent its own tab:
`herdr tab create --cwd <dir>` (returns the tab; read the new pane_id
from `herdr pane list`). Width thresholds per CLI in environment.md.

Fan out early (scouts) and late (reviewers) by preference — read-only and
conflict-free. Concurrent *writers* are the expensive width, paid in merge
conflicts and in confusion about which tree a finding refers to; two or
three in practice, because reviews serialize through you.

## Teardown — panes first, worktrees second

Close agent panes FIRST (`herdr pane close <pane_id>` — positional ID),
worktrees SECOND: an agent whose cwd was deleted spins on errors. Walk the
status matrix: every pane ever opened ends closed. The closeout report's
teardown evidence is `herdr pane list` and `git worktree list` pasted
after the fact (run-report).

## Helpers — `bin/`

- `run-prefix.sh SLUG` — collision-free agent-name prefix.
- `rotate-implementer.sh NAME PANE WORKTREE KIND -- ARGS` — move an agent
  onto a new worktree with its pin.
- `agent-status.sh NAME [TAIL-LINES]` — one-line liveness probe with a
  bounded pane read.

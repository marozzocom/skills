---
name: herdr-delegates
description: "The Herdr transport for delegated agents: start CLI
implementers, reviewers, scouts, and advisors in sibling Herdr panes with
model and effort pinned, name them with a collision-free run prefix,
deliver briefs by path, wait on turns and adjudicate blocked dialogs with
bounded pane reads, rotate an agent onto a new worktree, lay agents out in
tabs by node within a measured pane budget, run the board pane that shows
the human the run's state, and tear panes down before worktrees.
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
`${CLAUDE_SKILL_DIR}/../implementation-orchestration/references/environment.md`
— and holds, per CLI: the model pin and effort ladder with exact start
args, the login check, the quit command, transcript location, approval
settings, width thresholds, and verified quirks. Nothing vendor-specific
is written here. Helpers are at `${CLAUDE_SKILL_DIR}/bin/`; each header
comment is its contract.

## Names and the run's workspace — everything carries the run prefix

One Herdr server holds every workspace, and several runs can be live at
once, so agent names and tab labels are namespaced and the run stays in
one workspace.

- `PREFIX=$(${CLAUDE_SKILL_DIR}/bin/run-prefix.sh <slug>)` picks a prefix
  no live agent name, tab label, or workspace label uses. Record it in the
  ledger header and `status-set.sh RUN_DIR init RUN_ID "$PREFIX" "GOAL"`.
- **The run's workspace is the overseer's** (`HERDR_WORKSPACE_ID`). Open
  the cockpit once, right after `init`:
  `${CLAUDE_SKILL_DIR}/bin/run-cockpit.sh RUN_DIR`. It names you
  `$PREFIX-overseer`, registers you as the run's first agent row (so the
  board can see you blocked), names your tab `$PREFIX·cockpit`; renames the
  workspace to `$PREFIX` only when it holds nothing but this run; opens
  the board pane; and records the workspace, cockpit tab, and pane ids in
  status.json. Re-running it changes nothing.
- Agents are `$PREFIX-<role>` (`-impl`, `-impl-2`, `-review`, `-oracle`,
  `-ui`; per node `-n1-impl`, `-n1-review`). Tabs are `$PREFIX·<group>`
  (`·cockpit`, `·recon`, `·N1`) and are created only through
  `${CLAUDE_SKILL_DIR}/bin/run-tab.sh RUN_DIR <group> <cwd>`, which pins
  the recorded workspace and refuses a label that already exists anywhere
  on the server. A bare `herdr tab create` without `--workspace` lands in
  the UI-focused workspace — another run's, as often as not.
- The board flags any run agent whose pane sits outside the run's
  workspace; move it (`herdr pane move`) or close and restart it there.

## Starting an agent — pin model and effort explicitly

Start every agent with the model **and** effort pinned, even when a
config default exists: the pin is the brief's decision (design-gate §7),
and an unpinned start inherits whatever the CLI's config says today. Args
per CLI in environment.md. Record the pin, pane, and tab on the agent's status row
(`status-set.sh RUN_DIR agent NAME pin=… pane=… tab=… state=open`) so a
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

## Layout — tabs by node, panes within a measured budget

A tab holds what the human would watch together; a pane is added only if
it stays readable. A too-narrow TUI breaks silently — prompts dropped
with no error, agent stuck `idle`, pane reads a few characters per line
— so the budget is measured, never guessed.

- **Budget.** `bin/pane-budget.sh [--pane ID] [--reserve-rows N]` reads
  the pane's rect from `herdr pane layout` and prints how many agent
  panes it holds at ≥100 columns × ≥30 rows each (`PANE_MIN_COLS`,
  `PANE_MIN_ROWS`; environment.md may record a CLI that needs more),
  capped at 4. It never reports below 1, so also read its `width=` and
  `height=`: a pane under the minimum in either is too small for an
  agent at all — use a new tab instead. Run it on the cockpit before the first split and on each
  new tab before its second pane.
- **Cockpit tab:** you, with the board strip along the bottom
  (`--reserve-rows` for it). One agent pane joins only when the budget
  left is ≥2 — the one that matters most now, usually the active
  reviewer.
- **One tab per node,** labelled `<prefix>·<node>`: its implementer, then
  its reviewer and UI verifier, so a node's story reads in one place.
  Parallel nodes share a tab only while the budget allows. Open it with
  `bin/run-tab.sh RUN_DIR <node> <worktree>` (§Names), which prints
  `tab=<id> pane=<root pane id>` for the agent start.
- **Read-only scouts and critics share one `<prefix>·recon` tab,** side
  by side for comparison; each pane closes when its report lands (herdr
  closes a tab with its last pane). More scouts than the budget run in
  waves, not in a second recon tab.
- **At most four live tabs besides the cockpit.** Needing more means too
  many concurrent writers — two or three in practice, since reviews
  serialize through you; stagger starts or shrink the pool instead.
- Writers need disjoint file sets (shared baselines and lockfiles
  conflict). Fan out early (scouts) and late (reviewers) by preference —
  read-only and conflict-free.

## The board pane — the human's view of the run

`bin/run-board.sh RUN_DIR` redraws every 15 s from status.json, the
ledger, and `herdr agent list`: a **WAITING ON YOU** banner (every
`status-set.sh human add` item, and any run agent — you included —
showing `blocked`); the milestone and node checklist with PR and CI; each
open agent with herdr's status, time in state, tab, and live title; a
STALE line when the ledger has been silent while agents work; and the
last ledger entries. It never reads a pane or calls the network, so it
costs no tokens and stays outside the transcript boundary. It shows only
what you wrote: an unrecorded transition is invisible on it.

`run-cockpit.sh` opens it below you (§Names). `--board-ratio` (default
0.65) is the share your pane keeps: on a 71-row tab that leaves the board
~25 rows; on a shorter strip the board drops the oldest ledger lines
first. The board is not an agent and has no status row; its pane id is
in status.json. `run-board.sh RUN_DIR --once --width N` prints one frame
for a check from your own shell.

## Teardown — panes first, worktrees second

Close agent panes FIRST (`herdr pane close <pane_id>` — positional ID),
worktrees SECOND: an agent whose cwd was deleted spins on errors. Walk
status.json's agents: every pane ever opened ends closed, its row set to
`state=closed`. The board pane closes last, after the run report. The closeout report's
teardown evidence is `herdr pane list` and `git worktree list` pasted
after the fact (run-report).

## Helpers — `bin/`

- `run-prefix.sh SLUG` — prefix free across agent names, tab labels,
  and workspace labels.
- `run-cockpit.sh RUN_DIR [--board-ratio R] [--no-board]` — name the
  overseer, its tab, and (when it holds only this run) the workspace;
  open the board; record the ids. Idempotent.
- `run-tab.sh RUN_DIR GROUP CWD` — a `$PREFIX·<group>` tab in the run's
  workspace; refuses duplicates server-wide.
- `rotate-implementer.sh NAME PANE WORKTREE KIND -- ARGS` — move an agent
  onto a new worktree with its pin.
- `agent-status.sh NAME [TAIL-LINES]` — one-line liveness probe with a
  bounded pane read.
- `pane-budget.sh [--pane ID] [--reserve-rows N]` — how many readable
  agent panes a pane's area holds.
- `run-board.sh RUN_DIR [--once] [--interval S] [--stale-minutes M]
  [--width N] [--height N]` — the board pane.

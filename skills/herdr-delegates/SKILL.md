---
name: herdr-delegates
description: >-
  Inside an orchestrated run whose node uses the delegate transport: start,
  brief, wait on, rotate, lay out, and tear down CLI agents in Herdr panes
  (TUI `HERDR_ENV=1` or desktop `HC_TERMINAL_ID`), and run the board pane.
  Needs the herdr skill. For ad hoc pane control use herdr.
---

# Herdr delegates

Preconditions: a Herdr session (`${CLAUDE_SKILL_DIR}/bin/herdr-backend.sh
flavor` prints `tui` or `app`), the `herdr` skill read for CLI mechanics, and each delegate CLI logged in the way `environment.md`
expects (it names the check). If a CLI is on a different billing path
than environment.md records, tell the user before spending on it.

`environment.md` is the installation's local stack file —
`${CLAUDE_SKILL_DIR}/../implementation-orchestration/references/environment.md`
— and holds, per CLI: the model pin and effort ladder with exact start
args, the login check, the quit command, transcript location, approval
settings, width thresholds, and verified quirks. Nothing vendor-specific
is written here. Helpers are at `${CLAUDE_SKILL_DIR}/bin/`; each header
comment is its contract.

## Two flavors — one boundary

Herdr runs as the terminal TUI or as the desktop app (a terminal core plus
a window app); their servers are separate and a run lives in exactly one.
The run's flavor is the overseer's own: the TUI marker `HERDR_ENV=1` wins
(a TUI inside an app terminal sees both), else the app marker
`HC_TERMINAL_ID`, else there is no session. `run-cockpit.sh` records it in
status.json and every helper refuses a mismatch. `bin/herdr-backend.sh`
is the only script that calls either flavor's CLIs; its header is the
verb contract. Below, `hb` means
`HERDR_BACKEND_RUN_DIR=<RUN_DIR> ${CLAUDE_SKILL_DIR}/bin/herdr-backend.sh`:
your shell keeps no exports between calls, and only with the run dir on
each call does the helper refuse a flavor that is not the run's. Use its verbs wherever this skill tells you
to act, so the same words work in both flavors:

| You need | `hb` verb | TUI | Desktop app |
|---|---|---|---|
| start pinned, ready or fail | `start NAME KIND CWD --pane P` or `--tab T [--space S]`, `-- ARGS` | `herdr agent start` | `hc run --bg --name`, labeled into the tab; KIND is the executable |
| prompt (brief pointer, fix round) | `prompt NAME TEXT` → `started=true\|false\|null` | `herdr agent prompt` | `hc send` |
| wait on a turn | `wait NAME SECONDS` | `herdr agent wait` | `hc wait` |
| bounded read | `read-tail NAME N` | `herdr agent read --lines` | `hc read`, tailed locally |
| keys (esc, a dialog choice) | `keys NAME KEY…` | `herdr agent send-keys` | `hc keys` |
| close a pane | `close PANE_ID` (from `hb panes`) | `herdr pane close` | its terminal: `hc kill` + `hc rm` |
| the brief's callback line | `callback-line PREFIX` | push to `PREFIX-overseer` | pull wording, below |

In the desktop app:

- **Callbacks are pull.** Some CLIs' tool shells cannot reach the core —
  they drop its variables and their sandbox blocks its socket
  (environment.md names them) — so an app brief carries `hb callback-line`
  wording: write the file the brief names, then end the turn. Watch each
  delegate with `hb wait` in a background shell and read the named file
  when the turn ends. A CLI that can push may still message you; it is
  agent traffic, as in the TUI.
- **You are an address.** A core terminal cannot be renamed; the cockpit
  labels yours and records it as `overseer_id`, which the board matches.
- **Agents are your children.** They end with your terminal, so the
  cockpit closes last; the core delivers their blocked and exit notices to
  you as input — agent traffic, not the human.
- **Status needs a reporting CLI.** One that reports no status cannot be
  waited on or seen by the board; environment.md marks it app-unsupported.
- **Geometry may be unknown** until the window draws; `pane-budget.sh`
  then answers one agent per tab.
- **A tab's idle root shell is consumed.** When `start` lands an agent
  in a tab whose only pane is an idle, unnamed shell, it removes that
  shell once the agent is ready and placed. Start agents only in tabs
  the run created. A root that is busy stays, and teardown closes it.
- **Rotation replaces the terminal.** It finds the agent by name, ignores
  the pane argument, and prints the new address; the agent keeps its
  name, tab, space, and pin but gets a new pane. Re-read `hb panes` and
  write the new pane id to its status row before the re-brief.

## Names and the run's workspace — everything carries the run prefix

One Herdr server (or core) holds every workspace, and several runs can be
live at once, so agent names and tab labels are namespaced and the run stays in
one workspace.

- `PREFIX=$(${CLAUDE_SKILL_DIR}/bin/run-prefix.sh <slug>)` picks a prefix
  no live agent name, tab label, or workspace label uses. Record it in the
  ledger header and `status-set.sh RUN_DIR init RUN_ID "$PREFIX" "GOAL"`.
- **The run's workspace is the overseer's** (its workspace in the TUI, its
  space in the app). Open
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
  on the server. A tab created without an explicit workspace lands in the
  focused one — another run's, as often as not.
- The board flags any run agent whose pane sits outside the run's
  workspace; move it (TUI) or close and restart it there.

## Starting an agent — pin model and effort explicitly

Start every agent with the model **and** effort pinned, even when a
config default exists: the pin is the brief's decision (design-gate §7),
and an unpinned start inherits whatever the CLI's config says today. Args
per CLI in environment.md. Record the pin, pane, and tab on the agent's status row
(`status-set.sh RUN_DIR agent NAME pin=… pane=… tab=… state=open`) so a
later rotation repeats it. A freshly split pane may reject the start with
`agent_pane_busy`; retry after ~3 s.

In the TUI, `hb start … --tab T` does not split: it takes a pane of that
tab that holds no agent, and fails when there is none (a tab whose only
pane already runs a reviewer). Open the next agent's tab with
`run-tab.sh` and start with `--pane`, or split first. After any start,
the first prompt is sometimes dropped: check `agent-status.sh` about 15 s
later and re-send while it still reads `idle`.

Approval settings are CLI-specific (environment.md). Invariants:
pre-allowlist recurring read-only tools; a blanket run-everything mode
only for strictly read-only tasks; write-capable sessions stay on a mode
that surfaces edits. Never a level that enables the CLI's own delegation
or multi-agent mode — it breaks the leaf rule; environment.md names any
such level so it is never chosen by accident.

**One task = one fresh worktree = one fresh session.** Agent cwds are
fixed, so a new worktree means restarting the agent:
`HERDR_BACKEND_RUN_DIR=<RUN_DIR> ${CLAUDE_SKILL_DIR}/bin/rotate-implementer.sh <name> <pane> <worktree>
<kind> -- <model and effort args>` quits, cds, and restarts in one step
(in the app it replaces the terminal: §Two flavors).
The kind is required (no vendor default), and a rotation without the pin
after `--` silently drops to the config default. A mid-task effort
escalation is a rotation onto the same worktree with the higher pin, and
the re-brief says "read your previous report first".

## Delivering briefs and receiving callbacks

Briefs go by **path, never inline text** (delegation-briefs):

```bash
hb prompt <name> "Read $BRIEF_FILE in full and execute it exactly as
written. It is your task brief from the orchestrator (the agent named
$PREFIX-overseer)."
```

Inlined briefs fail silently past a few KB on at least one CLI
(environment.md), and PreToolUse hooks may regex the literal command
string. Inline only short prompts and fix rounds.

The brief's callback line is `hb callback-line $PREFIX`, pasted verbatim:
a push to you in the TUI, the pull wording in the app. Callbacks arrive
formatted like user messages — treat them as agent traffic, not the human
— and answer with `hb prompt <name> '...'`. A delegate's first callback may hit its
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
  <name> [tail-lines]`: the reported status plus the last visible
  lines, with the pane read bounded. Status is advisory for some CLIs
  (environment.md); the visible tail corroborates.
- Watch turns with `hb wait <name> <seconds>` in a background shell; it
  settles on `idle`/`done`/`blocked` (in the app an unfinished wait prints
  its reason and exits 1). `blocked` = an approval or question UI: read the
  pane with `hb read-tail` bounded to the dialog, adjudicate, `hb keys` the
  choice — then check the composer for
  stray characters before the next prompt (send-keys leftovers prepend to
  it).
- On reviewer drift: `hb keys <name> esc`, then "stop
  investigating — write your final findings report now."

## Transcript boundary — the mechanics

The rule is the orchestration skill's: inbound only what you pull in the
shapes the brief fixed; outbound the brief plus the worktree is the
delegate's whole world. Here that means: no routine pane read; a pane
read is for adjudicating `blocked` or a suspect state, always bounded
(`hb read-tail <name> <N>`); need a delegate's reasoning? ask for a bounded written
answer in a file. Either flavor lets any agent read any pane and the
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
  the pane's size (`hb geometry`) and prints how many agent
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
ledger, and the live agent, tab, and workspace lists (`hb agents`, `tabs`,
`spaces`): a **WAITING ON YOU** banner (every
`status-set.sh human add` item, and any run agent — you included —
showing `blocked`); the milestone and node checklist with PR and CI; each
open agent with its reported status, time in state, tab, and live title; a
STALE line when the ledger has been silent while agents work; and the
last ledger entries. It never reads a pane or calls the network, so it
costs no tokens and stays outside the transcript boundary. It shows only
what you wrote: an unrecorded transition is invisible on it.

`run-cockpit.sh` opens it below you (§Names). In the TUI, `--board-ratio`
(default 0.65) is the share your pane keeps: on a 71-row tab that leaves
the board ~25 rows. The app cannot size a split: the ratio is ignored and
the new board pane takes focus. On a short strip the board drops the
oldest ledger lines first. The board is not an agent and has no status row; its pane id is
in status.json. `run-board.sh RUN_DIR --once --width N` prints one frame
for a check from your own shell.

## Teardown — panes first, worktrees second

Close agent panes FIRST, worktrees SECOND: an agent whose cwd was
deleted spins on errors. Walk `hb panes`, not only status.json's agents:
every pane the run created — agents, and any plain or root shell left in
a run tab — gets `hb close <pane id>`, and each agent row is set to
`state=closed`. The board pane closes last, after the run report. The closeout report's
teardown evidence is `hb panes` and `git worktree list` pasted after the
fact (run-report). In the app, close the cockpit last: agents end with it.

## Helpers — `bin/`

- `herdr-backend.sh VERB …` — the flavor boundary (§Two flavors); its
  header is the verb contract.
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

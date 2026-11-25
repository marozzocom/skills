# herdr-delegates — orientation

For humans and skill-editing sessions; nothing here loads at runtime. The
agent entrypoint is [SKILL.md](SKILL.md).

## What it is

The [Herdr](https://herdr.dev/) transport for delegated agents: the one
skill in the set that needs a Herdr session — the terminal TUI
(`HERDR_ENV=1`) or the desktop app (`HC_TERMINAL_ID`). It carries everything that
is true because the delegate is a CLI in a sibling pane — naming, pinned
starts, brief delivery by path, waiting and blocked dialogs, rotation,
parallel panes and tabs, teardown order, startup dialogs (exit 4, the
folder-trust allowlist) — and nothing about *what* to
delegate (`design-gate`), *how to brief* (`delegation-briefs`), or *how
to review the result* (`independent-review`). Extracted from
`implementation-orchestration` (migration step 4 of its
[decomposition proposal](../implementation-orchestration/docs/decomposition-proposal.md)).

Everything vendor-specific — which CLIs fill which roles, model pins and
effort ladders, start args, quit commands, approval settings, quirks —
stays in the installation's local `environment.md`, which lives with the
orchestration skill and is read from here by path. The CLI quirk material
was learned from real failures, which is why this skill keeps it verbatim.

## Where things live

| File | Holds |
|---|---|
| [SKILL.md](SKILL.md) | names, starting with pins, brief delivery and callbacks, lifecycle, transcript-boundary mechanics, parallel panes, teardown |
| `bin/herdr-backend.sh` | the only script that calls Herdr's CLIs; one verb set for both flavors |
| `bin/run-prefix.sh` | collision-free agent-name prefix against live agents |
| `bin/rotate-implementer.sh` | quit → cd → restart an agent on a new worktree with its pin (app: a new terminal, same name) |
| `bin/rotate-cockpit.sh` | hand the overseer role to a fresh session: successor in its own tab, takes the name, closes the old cockpit (TUI) |
| `bin/agent-status.sh` | one-line liveness probe with a bounded pane read |
| `bin/inbox-watch.sh` | the run inbox's only reader: delivers messages and stall lines, writes the `inbox/.watch` heartbeat |
| `bin/inbox-send.sh` | writes an inbox message from a shell, to this run's `RUN_DIR` or (with `--from-run`) another run's |
| `bin/inbox-resolve.sh` | resolves a run_id, prefix or `<prefix>-overseer` to a run with a live inbox watcher |
| `trust-roots` (not in the repo) | `${XDG_CONFIG_HOME:-~/.config}/implementation-orchestration/trust-roots`: the human-owned allowlist of directories whose folder-trust dialog `start` may confirm; SKILL.md §Starting an agent has the rules |
| `tests/` | offline tests against mock `herdr`, `hc`, and `herdr-app`; `validate-skill.sh` |

## Install

```bash
ln -s "$(pwd)/skills/skills/herdr-delegates" ~/.claude/skills/
/bin/bash tests/validate-skill.sh
/bin/bash tests/run.sh
```

Requires Herdr (TUI, or the desktop app's `hc` and `herdr-app`), the companion `herdr` skill for CLI mechanics, `jq`, and
the system `bash` (3.2 on macOS). The orchestration skill's
`environment.md` must exist (see its SETUP.md).

## Anti-goals

- **Do not put vendor facts here.** A CLI's model id, start flags, or
  quirks belong in `environment.md`; this skill names the slot, not the
  value.
- **Do not grow prose rules where a mechanism would do.** The transcript
  boundary is enforced by the brief's read fence and the orchestrator's
  discipline; the day a delegate is observed reading a pane it should
  not, the fix is a Herdr read ACL, not another paragraph.

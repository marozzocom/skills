# Plan: inter-agent messaging and run memory

Status: draft plan, 2026-11-24, revised the same day after the Phase 0
evidence pass. Not loaded at runtime.

## Evidence (Phase 0, done)

A read-only pass over 73 run folders (2026-11-04 to 2026-11-24) produced a
deduplicated friction list with citations. The findings that shape this
plan:

- **Lost callbacks are the top messaging problem, not collisions.** In 14
  runs a delegate's report never reached the overseer, or arrived only when
  the human asked for status. Three causes: the delegate's tool shell lacked
  `HERDR_ENV`; the overseer was busy and no wait was armed; the delegate
  replied in its own pane because a fix-round message said "reply" without
  the callback command.
- **Callbacks are indistinguishable from human input.** They arrive as
  pasted text, so the overseer re-attributes by hand (6+ runs). Twice a note
  from a retired session, or relayed human words, was taken as a live
  instruction.
- **Collisions with human typing are real** (native test runs, audio
  captures, an overseer turn, keystrokes landing in a login field when the
  screen locked), but they are less frequent than lost callbacks.
- **Stalled delegates go unnoticed** (6 runs): sleep, API errors, usage
  limits or full context, found only when the human asks.
- **Pane-name addressing breaks**: names lost after `/clear`, retired panes
  still targeted (`agent_not_found`).
- **Overlong agent messages are not a problem.** Briefs already travel by
  path. The long-text failures were inline briefs and human-facing
  contract text.
- **Delegate questions**: about 113 recorded (lower bound), roughly a
  quarter caused by gaps in the brief, often a claim about code the
  orchestrator had not read.
- **Closeout is skipped**: 35 of 73 runs have no run report.

## Phase 1: durable message delivery (built 2026-11-24)

As built (run `2026-11-24-durable-agent-inbox`; herdr-delegates §The run
inbox). The inbox is the record of truth and nothing is pasted into the
overseer's pane.

- Delegates write a message file into `RUN_DIR/inbox/new/` with their own
  file-writing tool. No shell or Herdr command is involved, so a sandboxed
  tool shell cannot block it (Antigravity's shell sandbox denies writes
  under `RUN_DIR` and the `herdr` CLI; its file-writing tool does not).
- `inbox-watch.sh` runs under the overseer harness's event monitor (or
  `--once` in a background shell) and turns each message into one
  notification line, outside the pane's input. It is the only mover and
  log writer, delivers the backlog after a restart, checks the sender
  against the open agent rows, and stops itself in a retiring overseer
  during a cockpit handover.
- `hb tell` sends every fix round and follow-up with the reply
  instruction appended and stamps the time; `callback-line` takes the
  agent name.
- The watcher flags stalls (advisory): an agent that was told something
  and has not answered sits idle past 10 minutes, is blocked for 2, works
  for 45, or is gone.
- Changed from the earlier draft: no paste-when-safe heuristic and no
  `UserPromptSubmit` hook. Monitor delivery made both unnecessary.
- Checks: zero callbacks found by status probe and zero mid-sentence
  collisions over the next ~5 runs; `inbox/log.jsonl` shows delivery
  counts and stall lines.
- Still open: whether a monitor notification arriving while the human is
  mid-prompt behaves well in every harness (observed only in Claude Code).
  Messages between runs' overseers no longer use `herdr agent prompt`:
  Phase 2 built cross-run inbox delivery (`inbox-resolve.sh`,
  `inbox-send.sh --from-run`, the `inbox/.watch` heartbeat, and
  `[peer:<run-id>]` attribution).

## Phase 2: fix recurring friction

One small PR per item, highest recurrence first:

- Agent start dialogs (hooks review, update, folder trust) time out
  `agent start` and leave the pane unnamed (15 runs). Depends on whether
  Codex is still in the stack.
- Native verification blocked by a locked or sleeping screen, or by live
  typing (18 runs): ask for the desktop at contract time; check lock and
  idle input before native gates.
- Heavy-lock queue: 376 minutes waited across 24 gated runs; one hung
  holder blocked for 4h25m. Add a staleness signal.
- Load-sensitive tests flake gates (10 runs): record load per gate row and
  rerun the failing test alone before calling it load.
- The global Stop hook runs the full suite in shared worktrees and races
  implementers (5 runs).
- Landing slips: missing run marker, PR body not updated on push, the
  6,000-character body cut, rebase replays (9 runs).

Most are light-lane; any that touch agent instructions or hooks wait for
review. Check: each item stops appearing in later run reports.

## Phase 3: run memory

- Teardown refuses to finish until the run report exists.
- An index script derives `runs.jsonl` from run folders and inbox events:
  duration, nodes, transport and model per node, review rounds, gate
  failures and time, PR outcomes, time waiting on the human, handovers,
  delegate questions and their causes. Run folders stay the source of
  truth; the index is rebuildable.
- At run start, the design gate pulls lessons from earlier runs in the same
  repository into its frame.
- Check: every new run has a report; frames cite earlier lessons when they
  exist.

## Phase 4: feedback loop

Every ~10 runs, a retro pass reads new reports, finds recurring patterns,
and proposes skill or template changes as PRs, with model and transport
statistics for the model catalog.

- Check: proposals merge and their target friction stops recurring.
- Caveat: with tens of runs, statistics prompt a closer look; they do not
  decide.

## Deferred or dropped

- **Model rewriting or shortening messages: dropped.** The evidence shows
  no overlong-message problem.
- **Cheap-model check on briefs: deferred.** Brief-gap questions are mostly
  claims about unread code, which a cheap model cannot check. Revisit if
  the inbox data shows a pattern it could catch.
- **Upstream Herdr request** for input-aware delivery. Needs the operator's
  OK.
- **Dashboards**, until the index exists.

## Order

Phase 1 first: it fixes the largest measured problem and produces the
inbox data Phase 3 needs. Phase 2 items alongside, one PR each. Then Phase
3, then Phase 4. Phases 1 and 3 change delegate instructions and add hooks,
so they run orchestrated and wait for review.

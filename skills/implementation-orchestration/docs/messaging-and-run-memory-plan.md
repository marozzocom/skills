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

## Phase 1: durable message delivery

The inbox is the record of truth; pasting into a pane is only a
notification.

- Delegates send through a wrapper instead of `herdr agent prompt`. The
  wrapper appends each message to `RUN_DIR/inbox/` with a header it stamps
  itself: from, to, run, node, kind (report, question, blocker), thread,
  time. Senders cannot omit or forge attribution, and a message is never
  lost because a pane was busy, renamed or gone.
- Addressing is by run and role, resolved to a pane at send time, so a lost
  or changed agent name no longer drops messages.
- The wrapper works without `HERDR_ENV` (it writes a file; notification is
  best-effort), which removes the tool-shell failure.
- Notification pastes only when the overseer is idle and its input line
  reads empty on two reads about a second apart. Otherwise the message
  waits; a `UserPromptSubmit` hook attaches pending messages, separately
  tagged, when the human submits.
- The overseer's waits watch the inbox, not pane output, so a callback
  cannot arrive unseen while it is busy.
- Every message to a delegate, including fix rounds, ends with the
  wrapper's send command (the backend appends it), so replies cannot stay
  in the delegate's pane.
- An idle watchdog flags a delegate that has been idle or errored with no
  inbox message for N minutes.
- Checks: zero callbacks found by status probe over the next ~5 runs; zero
  mid-sentence collisions; the inbox log shows pasted versus queued counts.
- Tentative: reading the input box from screen text depends on each CLI's
  rendering. When unsure, queue; never paste.

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

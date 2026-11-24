# Plan: inter-agent messaging and run memory

Status: draft plan, 2026-11-24. Not loaded at runtime. Phase 0 results may
reorder or replace anything below; revise this document when they land.

## Problems

1. **Messages collide with human typing.** Delegates report with
   `herdr agent prompt <run>-overseer "<message>"`
   (`herdr-delegates/bin/herdr-backend.sh`, `callback-line`). Herdr pastes
   the message into the overseer's input box and presses Enter. It checks
   the agent's lifecycle state, not whether a human is mid-prompt, so a
   half-written human prompt is submitted with the message appended.
2. **Run data is written but never used.** Every run leaves a ledger,
   status file, review rounds, gate timings and (sometimes) a run report
   with "what to do differently". Nothing reads across runs, so the same
   friction recurs and is worked around again each time.
3. **Closeout is skippable.** At the time of writing, roughly half of the
   run folders have no run report.

## Phases

### Phase 0: evidence (read-only)

Mine every run folder into a deduplicated friction list: occurrences, runs,
cost, whether already fixed, proposed fix, and a dedicated section on
messaging problems.

- Why first: the rest of this plan rests on a few sampled lessons. The full
  data may reorder it.
- Check: every item cites runs; the operator agrees the top items match
  experience.

### Phase 1: message delivery

- Delegates call a wrapper instead of `herdr agent prompt`. The wrapper
  writes each message to `RUN_DIR/inbox/` with a header it stamps itself:
  from, to, run, node, kind (task, report, question), thread, time. Senders
  cannot omit or forge attribution.
- It pastes only when the overseer is idle and its input line reads empty
  on two reads about a second apart. Otherwise the message stays queued.
- A Claude Code `UserPromptSubmit` hook on the overseer attaches queued
  messages, each separately tagged, when the human submits. The human's
  sentence stays intact.
- Deterministic checks: required fields per kind; a length cap that bounces
  long messages with "write a file and send its path". At most one bounce
  per message.
- Check: no mid-sentence collisions over the next ~5 runs; the inbox log
  shows pasted versus queued counts.
- Tentative: reading the input box from screen text depends on how each
  agent CLI renders it. When unsure, queue; never paste.

### Phase 2: fix recurring friction

One small PR per top Phase 0 item. Most are light-lane; any that touch
agent instructions wait for review.

- Check: the item stops appearing in later run reports.

### Phase 3: run memory

- Teardown refuses to finish until the run report exists.
- An index script derives `runs.jsonl` from run folders and inbox events:
  duration, nodes, transport and model per node, review rounds, gate
  failures and time, PR outcomes, time waiting on the human, handovers.
  Run folders stay the source of truth; the index is rebuildable.
- At run start, the design gate pulls lessons from earlier runs in the same
  repository into its frame.
- Check: every new run has a report; frames cite earlier lessons when they
  exist.

### Phase 4: feedback loop

Every ~10 runs, a retro pass reads new reports, finds recurring patterns,
and proposes skill or template changes as PRs. It also reports model and
transport statistics to inform the model catalog.

- Check: proposals merge and their target friction stops recurring.
- Caveat: with tens of runs, statistics prompt a closer look; they do not
  decide.

## Deferred

- **Cheap-model check on task briefs** (scope, done criterion, report
  target present). Only if Phase 1's deterministic checks do not reduce
  delegates' clarifying questions, as measured by the inbox. Advisory only;
  never rewrite or shorten messages, since the sender usually included
  details on purpose.
- **Upstream Herdr request** for input-aware or queued delivery, which
  would remove the screen-reading heuristic. Needs the operator's OK.
- **Dashboards**, until the index exists and the recurring questions are
  known.

## Order

Phase 0, then Phase 1, with Phase 2 alongside. Phase 3 after Phase 1 so the
index includes inbox events. Phase 4 last. Phases 1 and 3 change delegate
instructions and add hooks, so they run orchestrated and wait for review.

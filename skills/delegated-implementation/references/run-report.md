# Run report template (§Closeout)

One report per run, rendered at closeout from the timestamped ledger.
`bin/run-report.sh <run-id> <owner/repo> [ledger]` prints the skeleton with
the deterministic parts filled (PR list + diff stats via the run marker,
teardown post-state reads); the orchestrator completes the judgment
sections. The report is the closeout forcing function: it is not complete
without the teardown evidence, and the run is not closed without the report.

## Sections

- **Header** — run id, dates, ledger path, contract one-liner (goal + stop
  criteria as accepted).
- **PRs** — number, title, state, merged time, +/− lines. From the run
  marker; cross-check against the ledger's PR list (a PR in the ledger but
  missing the marker is a process slip worth noting).
- **Timeline** — from ledger timestamps: agent spawns/rotations/teardowns,
  gates with verdicts, fix rounds, kills. One line per event; this is where
  "what actually happened" survives context loss.
- **Stats** — fix rounds per implementer, review escalations (external bot,
  stronger reviewer), gates passed/failed, wall time. **Only measured
  values**: turns, rounds, diff sizes, wall time. Delegate-side token spend
  is not reliably observable from the CLIs — say "not measured", never
  estimate it into a number.
- **Who did what** — one line per role: what the orchestrator did inline vs
  what was delegated. This is the take-over drift detector: orchestrator
  time spent on recon, CI collection, or mechanical I/O that a delegate or
  cheaper subagent could have done is a finding, not a neutral fact.
- **Teardown evidence** — pasted post-state reads (`herdr pane list`,
  `git worktree list`), per §Closeout. Absence of this section = the run is
  not closed.
- **Highlights and next-run changes** — what worked, what cost a
  round-trip, contract amendments worth keeping. Anything durable graduates
  into `environment.md`, `agent-trust-profiles.md`, or the repo's
  checklists — the report is where those files get their updates from.

Keep it one screen where possible; the ledger holds the detail.

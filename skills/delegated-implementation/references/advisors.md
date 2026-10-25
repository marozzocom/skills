# Advisors — oracle and classifier (optional)

Read when environment.md pins either. Both advise; neither holds
authority, and neither touches a worktree, git, or a peer. The ledger
records the advice beside your decision ("oracle: X; decided Y because
Z"). Both are built and unmeasured (README §Roadmap): the run report
records which consults changed a decision, and either role is dropped if
it stops paying.

## Oracle

A model stronger than you at reading intent, one long-lived read-only
pane per run (herdr-delegates), consulted only at decision points where
the risk is misreading *what the human meant*: contract acceptance,
whether a callback is a scope change, intent-or-taste adjudications,
killing work the human started. Never for code facts or a second review.
Consult by path (brief-template.md §Oracle consult), quoting the human
verbatim. If it disagrees on intent and the call is hard to reverse, ask
the human — at a gate the contract planned, or as a recorded unplanned
question (design-gate §5).

## Classifier

A typed-judgment service behind `bin/classify-escalate.sh`, for narrow
repeated questions: the callback screen, effort signals, the triage
cross-check, known-flake CI failures. It may only **escalate** scrutiny:
it never grants a permission, never relaxes a control, never replaces a
gate, security, or merge verdict, and never answers a question code can
decide (exit codes, `not run` lines, whether a file exists). An
unavailable or invalid answer is an escalation; the helper enforces that
mechanically. Checkpoints, thresholds, recording, and the one bounded
experiment per run: `references/classifier.md`.

The same asymmetry governs any fast model used for routing in future: it
may push toward the more controlled transport or more review, never
toward less (docs/vision.md principle 5).

# Classifier — policy, checkpoints, experimentation

Read when environment.md pins a classifier. This is the one place for
classifier policy; environment.md holds only the local facts (service,
model pin, transport command, credential, data rules, local question
sets).

## What it is for — and what it never does

A classifier answers narrow, repeated questions with typed judgments: a
yes/no probability (`noul`), one option out of a fixed set (`choice`), or
a graded level (`score`). Its one job in this protocol is to raise
scrutiny where your own pass might have missed something.

- **Escalate only.** An ESCALATE line means you perform that
  checkpoint's escalation action — the extra scrutiny named in
  §Checkpoints — yourself. It is not itself a verdict and not
  automatically a question for the human: the scrutiny decides that.
  Below threshold it removes nothing: every control you would apply
  without it still applies.
- **Never a permission.** "Not a scope change" authorizes nothing; it
  only means this check found no reason for more scrutiny.
- **Never a verdict.** Gates, security semantics, merges, and acceptance
  keep their owners (phase-review.md §Verification ownership).
- **Never for exact facts.** Exit codes, `not run` lines, whether a log
  file exists, whether a path is in a set, counts, fix-round numbers —
  check those with code or a direct read. Ask a classifier only what code
  cannot decide.
- **Fail closed.** No answer, a partial answer, or a malformed one is an
  escalation, never a no-signal; `bin/classify-escalate.sh` enforces
  that mechanically.

## Checkpoints — when configured and available

Run these whenever environment.md pins a classifier and its transport
works. Each uses a versioned question set under
`references/classifier/` (or a local set environment.md names):

| Checkpoint | When | Set | State to send | Escalation action |
|---|---|---|---|---|
| Callback screen | each callback that asks for or reports a decision | `callback-screen.json` | the callback text plus the contract excerpt it touches (goal, scope fence, invariants, any copy the contract specifies) | read the callback's evidence against the contract yourself before replying; a human exception (SKILL.md §Autonomy) goes to the human |
| Effort signals | before pinning a brief's effort | `effort-signals.json` | the brief's scope and frame text | re-read the frame for that signal; pin the escalation effort if it holds |
| Triage cross-check | hunks triage labelled mechanical or routine — all of them, or a sample chosen before looking on a large diff | `triage-risk.json` | the file path and the hunk | deep-read the hunk |
| CI failure | a red CI job you would otherwise treat as a known flake | local set (environment.md) | the failing job name and the first relevant error | investigate the failure instead of re-running it |

The fix-round effort signal (phase-design.md §Reasoning effort) is a
count, not a question — it has no classifier entry.

A fail-closed result (exit 3: unavailable, timed out, invalid) escalates
every question in the set, so you perform the escalation action for each
— never treat it as a no-signal. If the classifier stays unavailable,
record that in the ledger once and keep performing the escalation
actions at every checkpoint the run reaches.

## The helper

```bash
bin/classify-escalate.sh [--raw-out FILE] [--diag-dir DIR] SET STATE -- TRANSPORT [ARGS...]
bin/classify-escalate.sh --check SET...
```

`STATE` is a file holding one JSON value (build it with `jq -n`).
`TRANSPORT` is the local command environment.md names; it receives the
request file's path and prints the service's raw response. The helper
validates the response — exactly one JSON object, an answer for every
question and no others, each answer's type and fields, `noul` in [0,1] —
then prints one line per question, `ESCALATE` or `NO-SIGNAL`, and a
trailer with the set revision, model, and diagnostics directory.

Exit 0: valid, all `NO-SIGNAL`. 1: valid, at least one `ESCALATE`. 2:
usage, bad set, or bad state. 3: fail-closed (transport failure, invalid
response, missing dependency) — every question is printed `ESCALATE`.
Only exit 0 is a no-signal. The diagnostics directory (private, kept)
holds the exact request, raw response, and transport stderr; `--raw-out`
copies the raw response somewhere you choose without a second call.

## Writing questions

- **Atomic and typed.** One judgment per question. Several risks are
  several Nouls, not one Score: a three-level "risk" Score rated an RBAC
  frame routine where per-signal Nouls would not have averaged it away.
- **Named for what they ask.** The id states the judgment
  (`unauthorized_product_semantics`, not `vocab`), so a ledger line reads
  correctly without the set open.
- **Relevant evidence only.** State carries what the question needs — the
  callback and the contract excerpt, the hunk and its path — never a
  transcript, never secrets, and only the data environment.md allows.
- **Aligned with the brief.** A question screens for what the brief
  actually forbids. Briefs authorize routine copy and label changes they
  specify and reserve new user-facing product or domain semantics for the
  human (SKILL.md §Autonomy), so the callback screen asks about
  *unauthorized* semantic decisions — a routine authorized copy edit is a
  "no".
- **Probability is not confidence.** A Noul's value is the probability
  the answer is yes; Choice and Score `confidence` is the service's
  certainty in its own pick. They are different quantities and get
  different keys in a set (`at_or_above` versus `below_confidence`) —
  never threshold one as if it were the other.

## Thresholds — uncalibrated until measured

Every threshold in a set is policy, not a measured operating point,
until runs have recorded enough outcomes to say otherwise; the set's
`calibration` field says which. Change question text or a threshold only
together with a `revision` bump, so ledger lines stay comparable. Re-check
after the model pin changes. Never claim a classifier is accurate, or
that it improved a run, without counted outcomes.

## Recording — one ledger line per call

```text
classifier <checkpoint> set=<set>@<revision> model=<pin> baseline=<your call before running it>
  result=<ESCALATE/NO-SIGNAL per question, values> action=<what you did> outcome=<pending>
```

Write `baseline` before you run the helper — your own escalate/no-escalate
call on the same evidence — so agreement and disagreement are measurable.
Fill `outcome` when it is known, from evidence independent of the
classifier: what your read of the hunk found, what the human said about
the callback, whether the CI failure was a flake. At closeout,
independently re-check a sample of `NO-SIGNAL` results — all of them if
there are three or fewer, otherwise at least three chosen before looking
— and record each as a miss or a correct no-signal. Misses are the
number that matters for an escalate-only tool.

## Experimentation — one bounded experiment per substantive run

A run is substantive when it briefs at least one implementer. In each
such run, pick one additional experiment when suitable real inputs exist,
or record a concrete reason for skipping ("no callbacks reached a
decision point", "classifier unavailable: exit 3 at 14:02").

- **Real inputs, shadow mode.** Run a candidate — a new question, a
  reworded one, a different threshold, a Choice instead of Nouls —
  beside the configured checkpoint, on this run's real artifacts. It
  may raise scrutiny like any checkpoint; it never removes any.
- **Bounded.** One candidate set, written down before the first call,
  with a cap on calls (a dozen is plenty) and no new authority.
- **Recorded like a checkpoint** — baseline, result, action, outcome —
  plus a one-line verdict in the run report: keep, revise, or drop, and
  the counts behind it.
- **Graduation.** A candidate becomes a configured checkpoint, or a
  threshold moves, only on recorded outcomes across runs, through a
  normal reviewed change to the set file.

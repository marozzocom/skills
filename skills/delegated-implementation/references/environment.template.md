# Environment — machine/org-local configuration

Copy this file to `environment.md` (gitignored) and fill it in for your
machine, org, and agent stack. Everything the protocol in SKILL.md
parameterizes over lives here: which CLIs fill the implementer and
fast-reviewer roles, their pinned models and commands, CLI-specific quirks,
and org/repo integrations. Herdr can host many agent kinds (claude, codex,
cursor, opencode, copilot, droid, grok, …) — porting the skill to another
machine, org, or stack means rewriting this file (plus
`review-checklists.md` and `agent-trust-profiles.md`, which are local by
nature), never the skill body. Keep company data, repo names, model ids,
and infra details here and out of SKILL.md.

## Implementer — [CLI name]

- **Model:** `[model id]`. **Effort ladder** (phase-design.md §Reasoning
  effort): default pin `[level]`, escalation pin `[level]`; levels the
  skill never uses: `[anything that enables the CLI's own delegation or
  multi-agent mode — it breaks the leaf rule]`. [Where the default is
  configured.] Always pass the pin at start:

  ```bash
  # default pin
  herdr agent start <name> --kind [kind] --pane <id> \
    -- [model args] [default effort args]
  # escalation pin
  herdr agent start <name> --kind [kind] --pane <id> \
    -- [model args] [escalated effort args]
  ```

- **Subscription check** (SKILL.md precondition): `[login status command]`
  must report a subscription login, not an API key — flat-rate implementer
  tokens are part of the cost model.
- **Worktree rotation helper:** `bin/rotate-implementer.sh <name> <pane>
  <worktree> <kind> -- [model args]` — quit → cd pane → start in one step,
  per (name, pane). The kind is required (no vendor default); pass the pin
  after `--` — a rotation without it drops to the config default; the same
  helper on the same worktree is how an effort escalation happens. Record
  the exact invocation here.
- **Quit command:** [which of `/quit` / `/exit` this CLI exits on, verified
  by probe on date — the rotation helper tries both.]
- **Transcript access:** [where this CLI keeps session logs, so the
  orchestrator knows what "never read it" covers; whether `herdr agent read`
  on this pane returns the alternate screen or scrollback].
- **Known quirks:** [empirically verified failure modes and their
  workarounds — e.g. silent large-paste drops, approval dialog behavior.]

## Fast reviewer — [CLI name]

- **Model:** `[model id]`; always pin at start:

  ```bash
  herdr agent start <name> --kind [kind] --pane <id> -- [model args]
  ```

- **Model listing:** `[command]` (ids drift).
- **Approval settings (verified known-good):** [the CLI's approval mode and
  allowlist configuration that lets read-only work run without stalls, and
  the stricter-settings fallback.]

## External review bot — [bot name, or delete this section]

- **Enablement:** [which repos, manual/auto, billing model.]
- **Trigger:** [command.]
- **Poll:** [command.]
- **Behavior notes:** [incremental review, effort routing, and anything else
  configured account-side.]

## Cost table — marginal cost per role, and the routing rule

The orchestrator deliberately runs the best available model (judge/overseer
quality is where model strength pays); its context window and its usage
allowance are the scarcest resources in the mesh. State how each role is
actually billed here — a subscription window is a quota, not a price, and
API list prices are reference only unless a role really runs on the API.
Date every number; ratios move:

| Runner | Model | Billing here | API list (in/out) | Relative |
|---|---|---|---|---|
| Orchestrator | [model] | [subscription/API] | [$ / $ per MTok] | 1× |
| Implementer | [model] | [flat-rate?] | [$ / $ per MTok] | [≈0 if flat] |
| Fast reviewer | [model] | [flat-rate?] | [$ / $ per MTok] | [≈0 if flat] |

Routing rule: work that needs neither the orchestrator's accumulated
context nor its authority (git, gate verdicts, adjudication) never runs on
the orchestrator's model. State whether the orchestrator's harness
subagents are used at all: the default here is no — every delegate is a
pane, so the fan-out stays visible and nothing inherits the session model
unseen. If you do allow them, note how their model is pinned — some
harnesses' subagents inherit the session model unless pinned explicitly.

## Routing guard — how this installation keeps workers leaves

SKILL.md §Routing guard is the portable rule: a session executing an
assigned brief never activates this skill or its harness's delegation
features. Record here what makes that mechanical on this machine, and
what still rests on the brief text alone:

- **Same harness in both roles?** [yes/no — which role(s) share the
  orchestrator's CLI. If yes, the worker session has this skill installed
  too, so the guard is load-bearing.]
- **Worker-side signal:** [an environment variable, harness setting, or
  rule the orchestrator sets when starting a worker pane, e.g. a
  variable the harness's rules check before delegating; or "brief text
  only".]
- **Verified:** [date and how — e.g. a worker started on a brief with a
  multi-file scope was observed to implement inline and not fan out.]

## Workflow scripts (`bin/`)

Deterministic steps run as scripts, not re-derived prose. Ship with the
skill:

- `bin/watch-pr.sh` — CI poll loop for a background monitor: reads
  `gh pr view --json statusCheckRollup` (never `gh pr checks`, whose
  non-zero exit on failed *and* pending checks hides failures), normalizes
  CheckRun and StatusContext records, emits every terminal state, treats
  an empty check list as pending, retries transport failures visibly.
- `bin/run-report.sh` — deterministic half of the closeout report.
- `bin/rotate-implementer.sh` — worktree rotation; agent kind required.
- `bin/run-gates.sh` — acceptance gate runner: one verdict line per gate,
  failure tails only.
- `bin/agent-status.sh` — one-line agent liveness probe; the pane read is
  bounded with `--lines`.
- `bin/resolve-thread.sh` — review-thread reply + resolve in one call.
- `bin/ledger-append.sh` — timestamped ledger append.
- `bin/review-inventory.sh` — every changed path since the task base,
  untracked included.
- `bin/diff-hunks.sh` — only the hunks of a file overlapping a routing
  entry's line range, against the task base.
- `bin/land-pr.sh` — stage the `--stage` paths only → commit (hooks on)
  → push → `gh pr create --body-file` → optional auto-merge → run marker,
  as one process so a slow commit hook cannot be orphaned by an agent turn
  ending. Refuses pre-existing staged changes and stops before mutation
  when dirty paths are not named (`--allow-unlanded` prints them instead).
  `--attribution "<line>"` keeps a harness-required final line last.
- `bin/gh-json.sh` — sourced helper: accepts inline JSON from the native
  `gh` or a JSON-file path from a wrapper.

Add machine-local ones under `scripts/` (gitignored) and note them here.

### `gh` and CI watcher notes

- **`gh` flavour:** [native CLI, or a wrapper — if a wrapper, does it
  print JSON inline or write a file and print its path; does it suppress
  stdout on non-zero exits. `bin/gh-json.sh` handles both shapes; note
  anything else.]
- **Long-lived watchers:** [whether this platform tolerates a long
  `gh pr checks --watch` or a foreground poll loop — e.g. one desktop OS
  throttles background shells so long watchers die silently; there, run
  `bin/watch-pr.sh` under the harness's background monitor and poll
  external bots with short foreground checks.]
- **PR attribution:** [the final line the harness requires in every PR
  body, if any, passed to `land-pr.sh --attribution`; and the commit
  trailer, passed with `--trailer`.]

## Media upload — [integration, or delete this section]

How visual evidence gets inline into a PR body (phase-landing.md §Landing
modes, `stage`): [the skill, command, or API that uploads a screenshot or
recording to a host the PR renderer can fetch, its size limits, and how
you confirm the rendered body shows the image or video]. Never hot-link
media from a host the renderer cannot authenticate against.

## Run marker — pinning PRs to runs

Every PR a run opens carries `<!-- herdr-run: <run-id> -->` in its body
(invisible when rendered). Lookup:

```bash
gh pr list --repo [owner/repo] --state all --limit 100 \
  --search "herdr-run: <run-id> in:body" --json number,title \
  --jq '.[] | "#\(.number) \(.title)"'
```

## Org and repos

Primary org: `[org]`.

### [org/repo] (`[local path]`)

- **High-risk domains** for the external-bot trigger criteria: [e.g.
  auth/RBAC, payments, data deletion/migration, infra/deploy].
- **Preview deployments:** [opt-in mechanism, URL scheme, budget, docs
  pointer — or delete if the repo has none.]
- **Feature flags** (phase-landing.md §Landing modes, `flag` mode): [how a
  flag is created, read, enabled/disabled, and cleaned up; where the repo's
  gating-layer rules live (flag vs RBAC vs entitlement); the exact
  enable/disable commands a `flag` closeout report must quote — or delete
  if the repo has no flag system.]
- Review checklists, escalation reviewers, and the commit-free gate runner:
  see this repo's entry in `review-checklists.md`.

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

- **Login check** (SKILL.md precondition): `[login status command]` and
  the billing path it should report (subscription or API key).
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

## Oracle — [CLI and model, or delete this section]

SKILL.md §Advisors. One long-lived read-only pane per run.

- **Model and start:** `[model id]`, started with whatever the CLI offers
  to remove its edit, delegation, and skill tools (the routing guard made
  mechanical — record what was verified):

  ```bash
  herdr agent start oracle --kind [kind] --pane <id> -- [model args] [tool restrictions]
  ```

- **Billing:** [which allowance it draws on — often the orchestrator's
  own, at a heavier weight — and the per-run consult budget that follows.]

## Classifier — [service, or delete this section]

Policy, checkpoints, thresholds, and experimentation live in
`references/classifier.md`; record only local facts here.

- **Service and model pin:** [service, `[model id]`, pinned so recorded
  outcomes stay comparable; re-check thresholds after a re-pin.]
- **Transport** for `bin/classify-escalate.sh … -- TRANSPORT`: `[command]`
  — receives the request file's path, prints the raw response JSON, exits
  non-zero on any failure (HTTP error, timeout, missing credential).
- **Credential:** [where the key comes from; never in argv, never logged.]
- **Local question sets:** [paths of any repo-specific sets, e.g. a CI
  known-flake Choice; the generic sets ship in `references/classifier/`.]
- **Data rules:** [what may be sent (callbacks, frame text, paths, diff
  hunks, CI log excerpts) and what never is (secrets, credentials,
  customer data).]

## External review bot — [bot name, or delete this section]

- **Enablement:** [which repos, manual/auto, billing model.]
- **Trigger:** [command.]
- **Poll:** [command.]
- **Behavior notes:** [incremental review, effort routing, and anything else
  configured account-side.]

## Billing and the routing rule

State how each role is actually billed here — a subscription window is a
quota, not a price, and API list prices are reference only unless a role
really runs on the API. Date every number and record only what you have
checked; leave a cell "not checked" rather than estimate it:

| Runner | Model | Billing here | API list (in/out), date |
|---|---|---|---|
| Orchestrator | [model] | [subscription/API] | [$ / $ per MTok] |
| Implementer | [model] | [subscription/API] | [$ / $ per MTok] |
| Fast reviewer | [model] | [subscription/API] | [$ / $ per MTok] |
| Oracle | [model] | [whose allowance?] | [$ / $ per MTok] |
| Classifier | [model] | [API, per token?] | [$ per MTok] |

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

The generic helpers ship with the skill and are described once, in
README.md §Layout. Record here only machine-local helpers (under
`scripts/`, gitignored) and the notes below.

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

## Dependent PRs — [stacking tool, or delete this section]

phase-landing.md §Merge policy, *Dependent PRs*, is the protocol. Record the tool, its
install check, its docs link, and the commands for create / update after
a lower layer merges / merge — plus anything it cannot do yet (e.g.
auto-merge on a stacked PR).

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

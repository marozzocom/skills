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

- **Model:** `[model id]` at `[reasoning/effort setting]`. [Where the
  default is configured; pin per session if the config drifts:]

  ```bash
  herdr agent start <name> --kind [kind] --pane <id> -- [model/effort args]
  ```

- **Subscription check** (SKILL.md precondition): `[login status command]`
  must report a subscription login, not an API key — flat-rate implementer
  tokens are part of the cost model.
- **Worktree rotation helper:** [script or procedure that does
  quit → cd pane → start in one step, per (name, pane)].
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
quality is where model strength pays), which makes its tokens the most
expensive in the mesh and its context the scarcest resource. Fill in API
list prices as relative weights, dated — ratios move:

| Runner | Model | Billing here | API list (in/out per MTok) | Relative |
|---|---|---|---|---|
| Orchestrator | [model] | [subscription/API] | [$ / $] | 1× (the ceiling) |
| Orchestrator's subagents | [pinned cheaper model] | [same pool] | [$ / $] | [ratio] |
| Implementer | [model] | [subscription flat-rate?] | [$ / $] | [marginal ≈ 0 if flat] |
| Fast reviewer | [model] | [subscription flat-rate?] | [$ / $] | [marginal ≈ 0 if flat] |

Routing rule: work that needs neither the orchestrator's accumulated
context nor its authority (git, gate verdicts, adjudication) never runs on
the orchestrator's model. Note here how the orchestrator's harness pins
subagent models — including whether unpinned subagents silently inherit the
expensive session model (Claude Code's do: pass `model` explicitly on every
search/mechanical spawn).

## Workflow scripts (`bin/`)

Deterministic steps run as scripts, not re-derived prose. Ship with the
skill: `bin/watch-pr.sh` (CI poll loop for a background monitor — emits
every terminal state, treats an empty check list as pending),
`bin/run-report.sh` (deterministic half of the closeout report),
`bin/rotate-implementer.sh` (worktree rotation), `bin/run-gates.sh`
(acceptance gate runner — one verdict line per gate, failure tails only),
`bin/agent-status.sh` (one-line agent liveness probe),
`bin/resolve-thread.sh` (review-thread reply + resolve in one call), and
`bin/ledger-append.sh` (timestamped ledger append). Add machine-local ones
under `scripts/` (gitignored) and note them here.

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
- **Feature flags** (phase-landing.md §Landing modes, `flag` mode): [how a flag is
  created, read, enabled/disabled, and cleaned up; where the repo's
  gating-layer rules live (flag vs RBAC vs entitlement); the exact
  enable/disable commands a `flag` closeout report must quote — or delete
  if the repo has no flag system.]
- Review checklists, escalation reviewers, and the commit-free gate runner:
  see this repo's entry in `review-checklists.md`.

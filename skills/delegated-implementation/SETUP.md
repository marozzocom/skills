# delegated-implementation — setup

The single source for installing and adapting this skill. Orientation:
[README.md](README.md).

## Requirements

- [Herdr](https://herdr.dev/), with the orchestrator running inside a
  Herdr pane (`HERDR_ENV=1`), plus a companion `herdr` skill covering its
  CLI mechanics — this skill adds only the orchestration protocol.
- `git`, `jq`, and `gh` (authenticated for the repos you land in);
  `bash` — the scripts target the system bash, which is 3.2 on macOS.
- At least one implementer CLI and one fast-reviewer CLI that Herdr can
  host. An oracle and a classifier are optional.

## Install

Symlink (or copy) the skill directory into your harness's skills
directory, then create the three local references from their templates:

```bash
git clone https://github.com/marozzocom/skills.git
ln -s "$(pwd)/skills/skills/delegated-implementation" ~/.claude/skills/
cd skills/skills/delegated-implementation/references
cp environment.template.md environment.md
cp review-checklists.template.md review-checklists.md
cp agent-trust-profiles.template.md agent-trust-profiles.md
```

Fill them in: `environment.md` pins the stack (CLIs, models, start
commands, quirks, billing, routing-guard enforcement, repos);
`review-checklists.md` holds per-repo checklists, review conventions,
autonomous-landing grants, and safe-set tables; `agent-trust-profiles.md`
records verified per-agent behavior. All three are gitignored, as is a
`scripts/` directory where an installer may overlay machine-local helpers
(a classifier transport, for example).

## Optional: a classifier

Set the `Classifier` section of `environment.md`: the service and model
pin, a **transport** command for `bin/classify-escalate.sh` (it receives a
request file's path and prints the raw response JSON, exiting non-zero on
failure), where the credential comes from, any local question sets, and
the data rules. Check the shipped and local question sets offline:

```bash
bin/classify-escalate.sh --check references/classifier/*.json
```

Policy and use: [references/classifier.md](references/classifier.md).

## Validate

Run both under the system bash; neither touches a remote or calls a
model:

```bash
/bin/bash tests/validate-skill.sh   # frontmatter, references, links, question sets, script syntax, no vendor names in portable files
/bin/bash tests/run.sh              # script tests: mock gh/herdr/transports, throwaway repos with a local bare origin
```

## Per-repo adaptation (once per repository)

Before the first brief in a repo, record an entry in
`references/review-checklists.md` (the template lists the fields):

1. **Rules file** the implementer reads first — `AGENTS.md`, `CLAUDE.md`,
   `CONTRIBUTING`.
2. **Commit-free gate runner** — one command running lint, type-check,
   and tests without committing. If none exists, list the individual
   commands in every brief.
3. **Worktree convention** — where task worktrees live and how branches
   are named. One task = one worktree = one implementer session, and
   direct implementation follows the same convention.
4. **Review conventions and authority** — branch protection, required
   reviewers, CODEOWNERS, required checks; whether an autonomous-landing
   grant exists (absent means `stage` is the ceiling); the safe-set path
   table, which restricts that grant and never stands in for one.

## Porting

The protocol files — SKILL.md, the phase references, the brief and
run-report templates, classifier.md, the question sets, and `bin/` — are
generic. Porting to another machine, org, or agent stack means rewriting
the three local references (and providing a transport, if you use a
classifier), never the protocol files. The protocol is
multiplexer-agnostic in principle, but its mechanics are written for
Herdr.

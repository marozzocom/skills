# skills

Open-source [Claude Code skills](https://code.claude.com/docs/en/skills).
Each skill is a directory under `skills/` with a `SKILL.md` (the
instructions loaded when the skill triggers) and optional `references/`
loaded on demand.

The skills are written to be stack-, org-, and machine-agnostic: anything
local — model ids, repo names, org integrations — lives in gitignored
reference files you create from the provided `*.template.md` files. See
each skill's `README.md` for setup.

## Skills

| Skill | What it does |
|---|---|
| [`delegated-implementation`](skills/delegated-implementation/) | Orchestrate CLI coding agents (via [Herdr](https://herdr.dev/)) as workers while Claude oversees, reviews, verifies, and owns all git operations. Layered task graphs with gates, a file-based ledger, tiered review, and explicit verification ownership. |

## Install

Symlink (or copy) a skill into your skills directory and create its local
reference files from the templates:

```bash
git clone https://github.com/marozzocom/skills.git
ln -s "$(pwd)/skills/skills/delegated-implementation" ~/.claude/skills/
cd skills/skills/delegated-implementation/references
cp environment.template.md environment.md          # then fill these in
cp review-checklists.template.md review-checklists.md
cp agent-trust-profiles.template.md agent-trust-profiles.md
```

## License

[MIT](LICENSE)

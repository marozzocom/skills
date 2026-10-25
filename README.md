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
| [`annotate`](skills/annotate/) | Inject a click-to-annotate overlay into a page open in a browser tab, so a reviewer can pin notes to elements; then collect the notes and implement them. No build step, no dependencies — one idempotent IIFE, notes in `localStorage` per origin. |
| [`image-gen`](skills/image-gen/) | Generate or edit images via the OpenAI Images API — text-to-image and image+prompt editing, with size/quality/transparency flags. Reads `$OPENAI_API_KEY`, or optionally a secret manager when `$GENIMAGE_PASS_VAULT`/`$GENIMAGE_PASS_ITEM` are set. |
| [`gh-media`](skills/gh-media/) | Attach screenshots, screen recordings, and videos inline to GitHub PRs, issues, and comments — including private repos — via GitHub's own user-attachments CDN (headless token auth through the [`gh-image`](https://github.com/drogers0/gh-image) extension). Capture → fit to size limits → upload → embed → verify rendering. |
| [`design-gate`](skills/design-gate/) | Frame an implementation before anyone implements it: recon, a cited frame, an independent critique, task shape and stop criteria, a contract with verifiability and planned human gates, and the per-node transport (direct / native subagent / delegate) and effort decisions from observed signals. |
| [`delegation-briefs`](skills/delegation-briefs/) | Write the brief that hands work to an agent that did not share your conversation, on any transport: roles, read fence, scope fence, initiative line, verification floor, "done means", leaf rule, the ~40-line report head, two-brief bug fixes, fix rounds; with a per-transport annex. |
| [`herdr-delegates`](skills/herdr-delegates/) | The Herdr transport for delegated agents: run-prefixed names, pinned starts, briefs by path, waiting and blocked dialogs, rotation onto a new worktree, parallel panes and tabs, teardown order. The one skill in the set that requires `HERDR_ENV=1`. |
| [`independent-review`](skills/independent-review/) | Independent verification and tiered review of a diff before commit, whoever wrote it: acceptance re-run of gates, inventory → triage → risk-range deep read, mutation checks on new tests, centralized checklists, fix rounds, review threads. The author never reviews; risk-bearing code gets a different model family. |
| [`delegated-implementation`](skills/delegated-implementation/) | The spine of an implementation run and home of the shared charter: routing, roles, contract, ledger, mesh and transcript rules, landing and report helpers. Loads the four companions above by phase; implementation runs direct, on a native subagent, or on a delegated CLI agent (via [Herdr](https://herdr.dev/)) per node, while Claude keeps review, verification, and all git operations. |

## Install

Symlink (or copy) a skill's directory into your skills directory, then
follow that skill's own setup — its `README.md`, or for
`delegated-implementation` its [SETUP.md](skills/delegated-implementation/SETUP.md),
which is the single source for that skill's installation.

## License

[MIT](LICENSE)

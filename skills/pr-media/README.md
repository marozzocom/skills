# pr-media

Attach screenshots, screen recordings, videos, and GIFs **inline** to GitHub
PRs, issues, and comments from the CLI or an agent session — including on
private repositories.

## The problem

GitHub has no public API for comment attachments: the web UI's drag-drop uses
an undocumented endpoint, and `gh` has no stable equivalent yet
([cli/cli#13256](https://github.com/cli/cli/issues/13256)). The common
workaround — commit images to an assets repo and hot-link raw URLs — silently
breaks on private repos, because GitHub rewrites markdown images through the
anonymous [camo proxy](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-anonymized-urls),
which cannot authenticate. External video URLs never get the inline player at
all.

## The mechanism

Upload to GitHub's own **user-attachments CDN** — the same store the web UI
uses — via the [`gh-image`](https://github.com/drogers0/gh-image) extension.
For repos you can push to, this authenticates headlessly with your existing
`gh` token. Results render exactly like drag-dropped files: inline images and
a real video player, with visibility inherited from the repo you upload
against (private repo ⇒ signed URLs, repo members only).

The skill wraps that in a full pipeline: capture (Playwright, OS tools,
harness browsers) → fit to GitHub's size limits → upload → embed with
rendering-correct markdown → **verify** against GitHub's rendered HTML that
the media actually displays.

## Setup

```bash
gh extension install drogers0/gh-image

ln -s "$(pwd)/skills/pr-media" ~/.claude/skills/
cp skills/pr-media/references/environment.template.md \
   skills/pr-media/references/environment.md   # then fill it in
```

`environment.md` is gitignored — it holds your default upload repo, plan tier
(video size limit), and which capture tools your machine has.

## Caveats

- The upload flow rides an undocumented internal API; it can break without
  notice. First response to 4xx failures: `gh extension upgrade gh-image`.
- The cookie fallback (`GH_SESSION_TOKEN`) is a full-account credential —
  treat it like a password. The token path needs no cookie for repos you can
  push to.
- Alternatives if `gh-image` dies: [`Addono/gh-attach`](https://github.com/Addono/gh-attach)
  (same CDN, more strategies), or — public repos only — orphan-branch /
  release-asset hosting.

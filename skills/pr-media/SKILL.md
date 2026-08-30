---
name: pr-media
description: Attach screenshots, screen recordings, videos, GIFs, and other files inline to GitHub PRs, issues, and comments from the CLI — capture, fit to size limits, upload to GitHub's user-attachments CDN, embed with rendering-correct markdown, and verify the result actually renders. Use when asked to add an image or video to a PR or issue, post visual evidence or before/after screenshots, record a demo for review, or whenever a UI-facing PR would be clearer with a picture. Works for private repositories.
---

# PR media

Pipeline: **capture → fit → upload → embed → verify**. Local defaults (upload repo, plan limits, capture tooling) live in `references/environment.md`; read it first if it exists.

## Why this mechanism — do not substitute another

GitHub has no public API for comment attachments, and markdown images are rewritten through the anonymous camo proxy, which cannot authenticate. Consequences you must not re-litigate per task:

- Hosting media in a **private** repo (raw URLs, release assets, private Pages) renders as a broken image for everyone. Never build or suggest a private assets repo.
- The only private-safe inline mechanism is GitHub's own **user-attachments CDN** — the same store the web UI drag-drop uses. Attachments inherit the visibility of the repo they are uploaded against; on private repos they are served as short-lived signed URLs to people with repo access only.
- Therefore: **always upload against the repo whose PR/issue you are embedding into** (or one at least as restricted), never a more public repo.

## Upload

Uses the `gh-image` extension (one-time setup: `gh extension install drogers0/gh-image`; see `README.md`).

```bash
gh image <file>... --repo <owner/repo>   # --repo optional; inferred from cwd git remote
```

Prints ready-to-paste markdown: `![name](url)` for images, a bare URL for videos, `[name](url)` for other files. For repos you can push to, the upload authenticates headlessly with the gh CLI token — no browser or cookies. For other repos it falls back to a browser session cookie (see Fallbacks).

This rides an undocumented internal GitHub flow. If uploads start failing with 4xx, run `gh extension upgrade gh-image` before debugging anything else.

## Fit — check sizes before uploading

| Type | Limit |
|---|---|
| Images and GIFs | 10 MB |
| Videos (org/user on a paid plan) | 100 MB |
| Videos (free plan) | 10 MB |
| Everything else | 25 MB |

Accepted media formats: png, jpg, gif, svg, webp; mp4, mov, webm. Compression and conversion recipes: `references/capture-recipes.md`. An oversized file fails the upload — shrink it first, don't retry.

## Embed

- **Image:** `![alt](url)` with meaningful alt text.
- **Video:** the bare URL **alone on its own line**. Wrapping it in `![...]()` or `[...]()` breaks the inline player.
- Post via `gh pr comment <n> --body-file`, `gh pr edit <n> --body-file`, `gh issue comment`, or include in `gh pr create --body-file`. Prefer `--body-file` over inline `--body` to avoid shell-quoting damage to URLs.

## Verify — mandatory, not optional

An upload that succeeded can still embed wrong. Fetch GitHub's rendered HTML and confirm:

```bash
gh api repos/<owner>/<repo>/issues/<n> -H "Accept: application/vnd.github.html+json" --jq .body_html
# comments: .../issues/<n>/comments  → .[].body_html
```

- Image rendered ⇢ an `<img src="https://camo...">` (public) or `<img src="https://private-user-images...jwt=...">` (private).
- Video rendered ⇢ a `<video src=...>` element.
- Your URL appearing only inside a bare `<a>` ⇢ **not rendering** — almost always a video URL that isn't alone on its line, or media hosted somewhere camo can't reach.

Report the attachment as VERIFIED only after seeing the `<img>`/`<video>` element.

## Capture

Prefer evidence the task already produced (test-harness screenshots, CI artifacts) over capturing fresh. When capturing fresh, use what the machine has — Playwright page screenshots and `recordVideo` (webm), macOS `screencapture` for stills and `-v` for screen video, browser-automation screenshots, GIF assembly. Concrete commands: `references/capture-recipes.md`. What this machine has: `references/environment.md`.

## Fallbacks, in order

1. Token path refused (repo you can't push to): use a browser session cookie — `gh image extract-token`, pass via `GH_SESSION_TOKEN`. It is a full-account credential, not a scoped token: never print, log, or commit it.
2. `gh-image` broken or uninstallable: `Addono/gh-attach` (npm or gh extension) targets the same CDN with additional strategies.
3. **Public repos only:** commit assets to an orphan branch or a release and hot-link — renders via camo. Never do this for private repos.
4. Last resort: upload as a plain file attachment link with no inline render, and say so explicitly in the PR comment and your report.

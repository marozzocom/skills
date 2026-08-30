# gh-media — local environment

Copy to `environment.md` (gitignored) and fill in. The skill reads this for machine- and org-specific defaults; everything here is a default, not a limit — per-task instructions win.

## Upload defaults

- **Default upload repo:** `<owner/repo>` — used when the task doesn't imply one. Must be at least as restricted as the most private repo you attach media into (attachments inherit the upload repo's visibility).
- **GitHub plan:** `paid | free` — sets the video limit (100 MB paid, 10 MB free).

## Capture tooling on this machine

- **Playwright:** `<available? where? which browser versions are installed>`
- **ffmpeg:** `<full install | playwright-bundled minimal build only | none>`
- **OS capture:** `<e.g. macOS screencapture | grim | none>`
- **Harness browser tools:** `<e.g. Claude in Chrome MCP, Playwright MCP — and where they save screenshots>`

## Session-token policy

If the token path can't cover a repo you need, note here where a `GH_SESSION_TOKEN` may come from (browser profile, secret manager item) — or state that cookie fallback is not allowed on this machine.

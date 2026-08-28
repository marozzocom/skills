---
name: annotate
description: Inject a click-to-annotate overlay into a website open in a browser tab so the user can pin improvement notes to elements, then collect the notes and implement them. Use when the user asks to annotate a site/page, "let me leave notes on the site", re-add the annotation tool, or collect/clear previously left annotations.
---

# Website annotation overlay

Inject `annotator.js` (in this skill's directory) into the page, let the user click elements and leave notes, then collect the notes from `localStorage` and implement them.

## Inject

Read `annotator.js` from this skill's directory and execute it verbatim in the target tab:

- **In-app browser** (default): `mcp__Claude_Browser__javascript_tool` with `action: "javascript_exec"` on the tab showing the site. If no tab is open, `preview_start`/`navigate` first.
- **User's real Chrome**: `mcp__claude-in-chrome__javascript_tool` — only when the user wants to annotate in their own logged-in browser.

The IIFE returns `"already installed"` or `"installed, existing notes: N"`. It is idempotent per page load (guards on `window.__skillAnnotator`) but does NOT survive a reload or hard navigation — re-inject after those. Notes persist in `localStorage` per origin regardless, and pins for the current path redraw on re-inject. SPA route changes keep the overlay alive.

Tell the user: click any element to leave a note; the bottom-right toolbar toggles annotating OFF to browse/navigate normally (clicks are intercepted while ON).

## Collect

```js
localStorage.getItem('__skill_annotations')
```

Each note: `{ n, note, url (pathname), pageX, pageY, selector, tag, text, ts }` — `selector` + `text` identify the element, `url` the page. Enumerate the notes back to the user, map each to code/content, and implement.

## Clear

Only when the user asks to start fresh (it deletes their notes, and the permission classifier may block it unless the user's request is explicit):

```js
localStorage.removeItem('__skill_annotations')
document.querySelectorAll('.__fa_pin').forEach(p => p.remove())
```

Alternatively leave old notes in place and filter collected notes by `n` or `ts` — numbering continues from the stored count.

## Gotchas

- The in-app browser pane never fires IntersectionObserver callbacks — scroll-triggered page behavior (reveal-on-view etc.) will look broken there. Verify such behavior with Playwright against localhost instead of trusting the pane.
- `pageX/pageY` are document coordinates at the user's viewport size; prefer `selector`/`text` over coordinates when locating what they meant.

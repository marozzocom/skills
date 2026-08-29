---
name: annotate
description: Inject a click-to-annotate overlay into a website open in a browser tab, then collect the pinned feedback and implement it. Use when the user says "annotate this page," "let me mark up the site," "I want to leave notes on elements," "collect my annotations," "clear the feedback pins," or asks to reinstall the annotation overlay after a reload.
---

# Website annotation overlay

Use `annotator.js` from this skill's directory to collect element-specific feedback on a live page.

## Inject

Execute the complete contents of `annotator.js` as JavaScript in the target browser tab. Use the in-app browser by default; use the user's browser only when they need its existing login or explicitly ask for it. Navigate to the target page first if necessary.

The script returns `already installed` or `installed, existing notes: N`; the latter adds `skipped invalid: M` when individual stored records are malformed. Relay that warning so the user can inspect or clear the bad records. The overlay is idempotent for the current page load. A reload or full navigation removes it, so inject it again. On a client-side route change, run `window.__skillAnnotator.refresh()` to redraw the pins for the new pathname.

Tell the user:

- With **Annotating: ON**, click an element, enter a note, then choose **Save**. **Cancel**, Escape, and Ctrl/Command+Enter are keyboard-accessible alternatives.
- Turn annotating **OFF** in the bottom-right toolbar before using page links or controls normally; page clicks are intentionally intercepted while it is on.

If injection fails because storage is unavailable or corrupt, relay the script's recovery message instead of claiming the overlay was installed.

## Collect and act

Read:

```js
localStorage.getItem('__skill_annotations')
```

Parse the JSON array and skip records that do not match the overlay's note shape. Each valid note contains `{ n, note, url, pageX, pageY, selector, tag, text, ts }`; `url` is the pathname. Enumerate the valid notes for the user, use `selector` and `text` to find the intended element, then make the requested changes. Coordinates depend on the viewport and are only a fallback.

## Clear

Clear notes only after an explicit user request because this deletes their feedback:

```js
window.__skillAnnotator.clear()
```

To remove the overlay without deleting notes, run `window.__skillAnnotator.destroy()`.

## Browser limitation

Some in-app browser environments do not fire `IntersectionObserver` callbacks. When scroll-triggered page behavior appears broken, verify it in a normal browser or with the project's browser test tooling before changing the site.

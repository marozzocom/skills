# annotate — maintainer notes

This skill injects a temporary review layer into an existing page. A reviewer can pin comments to elements without the target application adopting an annotation dependency or build step.

## Setup and prerequisites

Install or symlink this directory into the host agent's skills directory. The host needs a browser tool that can execute JavaScript in the target tab. The page must permit `localStorage`; notes are stored under `__skill_annotations` for that origin.

There is no package install or build. Run the JavaScript syntax check after changes:

```bash
node --check annotator.js
```

## Design rationale

- One idempotent IIFE makes injection practical in browser automation tools and leaves the target repository untouched.
- A shadow root isolates the toolbar, dialog, and pins from page CSS. All overlay event handling is scoped to those controls except the intentional capture of page clicks while annotation mode is on.
- Notes use plain JSON in origin-scoped `localStorage`, so they survive reloads without a service or account. The selector and text snapshot carry intent; coordinates mainly place the visual pin.
- The public `window.__skillAnnotator` handle is deliberately small: `refresh`, `clear`, and `destroy` cover client-side navigation, explicit deletion, and teardown.

The script should remain dependency-free and safe to inject into pages it does not own. New keyboard shortcuts belong inside the overlay dialog; avoid document-wide key handlers.

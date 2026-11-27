# macos-ui-study

Use native macOS SwiftUI prototypes as a high-craft forcing function for web UI design.

## Requirements

- macOS with Xcode / Swift 6 toolchain (`swift --version`)

## Install

Symlink or copy `skills/macos-ui-study` into your skills directory:

```sh
ln -s "$(pwd)/skills/macos-ui-study" ~/.claude/skills/macos-ui-study
```

## How it works

1. Reimagine an ambiguous or flat web component as a native SwiftUI view following Apple's HIG.
2. Render Dark and Light `@2x` Retina PNGs headlessly via `NSHostingView` (zero focus steal), or launch the live window to feel hover states and transitions.
3. Translate the resulting hierarchy, proportions, and affordances — not Apple's visual skin — back into your web design system, fixing any system-level primitive gaps the comparison surfaces.

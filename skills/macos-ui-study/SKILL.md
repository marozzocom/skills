---
name: macos-ui-study
description: Resolve ambiguous or flat web UI by building a fast, native macOS SwiftUI prototype first, rendering Dark/Light Retina snapshots headlessly, and translating the resulting hierarchy, proportions, and affordances back into the target web design system. Use for flagship surfaces, spotlight cards, toolbars, inspectors, settings screens, empty states, or new design-system components where layout and craft feel uncertain. Not for routine CRUD forms, minor spacing tweaks, or settled design-system patterns.
---

# macOS UI Study

Web CSS has too many degrees of freedom. When a surface feels flat or ambiguous, asking for "better polish" usually produces timid tweaks or generic card tropes. Building the same concept as a **native macOS SwiftUI prototype** acts as a craft forcing function: Apple's HIG and SwiftUI's built-in controls force crisp decisions about hierarchy, surface depth, typography, and interactive affordances. You then port those **structural decisions** — never Apple's blue/grey skin — back into the target web design system, and surface any missing design-system primitives along the way.

Pipeline: **Frame → Build native study → Headless `@2x` render & self-critique → Live review (optional) → Translate to web & verify.**

---

## 1. Frame (before writing Swift)

Treat the existing web UI (or screenshot/spec) as a **content inventory**, not a pixel layout to copy:
- List the semantic elements: eyebrow/category, title, status/version metadata, supporting prose, actions (primary vs. secondary), and whether the subject itself can be demonstrated live.
- Name the concrete problems in the current web version (e.g., stacked metadata interrupting title → description flow, competing accent colors, floating text links without button affordances, unused horizontal space).
- Decide if **two variants** help the comparison:
  - **Editorial:** Same content inventory, pure native typography, spacing, and control hierarchy (1:1 comparison for narrow or multi-column web slots).
  - **Spotlight / Interactive:** Adds a recessed live preview well or native interactive affordance when horizontal room allows.

---

## 2. Build the native SwiftUI study

Create a small standalone SwiftPM executable (zero third-party dependencies, `swift-tools-version: 6.0`, `.macOS(.v15)`). Copy the dual-mode `Package.swift` and `main.swift` harness from [references/harness-template.md](references/harness-template.md).

Apply Apple HIG discipline ruthlessly:
- **Separate metadata from reading flow:** Put category/eyebrow (left) and timestamp/version (right, monospaced digits) in a top rail above a 1pt hairline divider so the title and description lock together immediately below.
- **One focal accent:** Reserve `.tint` / accent color for the primary interactive CTA (and at most a tiny leading icon). Keep status/version badges calm and neutral or low-chroma so nothing fights the primary button.
- **Unmistakable action hierarchy:** Primary action uses `.borderedProminent`; secondary action uses a quiet `.plain` / `.bordered` control with a directional chevron (`chevron.right`). On narrow or 2-column cards, consider stacking actions vertically on a single left axis instead of pinning controls to opposite corners with a hollow gap between them.
- **Optical alignment & continuous corners:** Use `.rect(cornerRadius: …, style: .continuous)` and visually check badge/icon alignment against the title's cap height.
- **Layered elevation:** Distinct canvas → elevated card surface (with subtle top-edge highlight in Dark Mode) → recessed inset well (if interactive).
- **Respect accessibility:** Support Light & Dark mode via semantic colors (`Color(nsColor: .controlBackgroundColor)`, `.primary`, `.secondary`, `.tertiary`) and honor `@Environment(\.accessibilityReduceMotion)`.

---

## 3. Build & capture headless `@2x` Retina snapshots

Build inside the sandbox by redirecting Swift/Clang module caches to `/tmp`:

```sh
mkdir -p /tmp/swift-module-cache /tmp/swiftpm-cache
CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swift-module-cache \
  swift build --disable-sandbox --cache-path /tmp/swiftpm-cache
```

Render Dark and Light `@2x` PNGs headlessly (no window, no focus steal — `NSApplication.shared.setActivationPolicy(.prohibited)` + `NSHostingView` with explicit `.darkAqua` / `.aqua` appearance):

```sh
.build/debug/<AppName> --render <output-dir>
```

**Self-critique the PNGs before showing the user.** Open every rendered PNG and check:
1. Does the primary CTA clearly own the focal accent?
2. Are dividers, metadata dots, and secondary labels legible in *both* Dark and Light mode?
3. Are pills/badges optically centered on the title and balanced in padding?
4. Do columns, baselines, and edges lock onto a clean grid?

Fix any flaw, rebuild (incremental builds take ~1–2s), and re-render.

---

## 4. Live interactive window (when the user wants to feel it)

The dual-mode harness in [references/harness-template.md](references/harness-template.md) also runs as a real macOS app (`NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)`).

- **Sandbox note:** Bare SwiftPM GUI executables cannot connect to WindowServer / `com.apple.hiservices-xpcservice` inside a restricted sandbox — the process runs but the window stays invisible. Launch the live app outside the sandbox when the user asks to run it.
- If opening a visible window unprompted while the user is working, follow `desktop-control` first.

---

## 5. Translate back to the web design system

When porting the study into the web app, **port structure, hierarchy, rhythm, and affordances — never macOS chrome or Apple blue.**

1. **Map every decision onto the target design system's own primitives and tokens:**
   - Card surface, hairline separator, spacing scale, type ramp, monospace font for versions/codes, primary button, quiet/ghost secondary trigger.
   - Never hardcode raw hex/px values where design-system tokens exist.
2. **Watch for design-system gaps exposed by the comparison:**
   - Side-by-side comparison often reveals system-level rough edges (e.g., badges rendered as squircles instead of true pills, cards lacking an edge-to-edge `<Separator />`, missing mono version styling).
   - Fix reusable gaps in the design system itself rather than hacking around them in app CSS.
3. **Visually verify the web result in a real browser:**
   - Capture Dark, Light, and narrow/phone (~390px) screenshots of the real rendered web component.
   - Inspect every pixel — visual inspection catches CSS specificity and negative-margin bleed bugs that type-checks and linters miss.
   - Present a side-by-side **Before → Native macOS Study → Final Web** comparison (and embed the web captures in the PR body via `gh-media`).

# Capture and fit recipes

Generic commands for producing and shrinking PR media. Check `environment.md` for which tools this machine actually has before picking one.

## Screenshots

```bash
# Playwright (any OS, needs a browser install matching the playwright version)
bunx playwright screenshot --viewport-size=1280,800 "http://localhost:3000/page" out.png
bunx playwright screenshot --full-page "http://localhost:3000/page" out-full.png

# macOS — whole screen, region, or window (silent, no UI sound)
screencapture -x out.png
screencapture -x -R0,0,1280,800 out.png
screencapture -x -l "$(osascript -e 'tell app "Google Chrome" to id of window 1')" out.png
```

In-harness browser tools (Claude in Chrome, Playwright MCP) already save screenshots to disk — reuse those files instead of re-capturing.

## Screen recordings / videos

```bash
# macOS built-in: record N seconds of a region to .mov (renders inline on GitHub)
screencapture -v -V 8 -R0,0,1280,800 demo.mov
```

Playwright records webm per browser context — drive the flow, then close the context to flush the file:

```ts
const ctx = await browser.newContext({
  recordVideo: { dir: "media/", size: { width: 1280, height: 800 } },
});
const page = await ctx.newPage();
// ... drive the UI ...
const path = await page.video()!.path();
await ctx.close(); // video is finalized only on close
```

mp4, mov, and webm all get the inline player; no conversion needed for format alone.

## GIFs

Prefer real video over GIF — smaller, scrubbable, better quality. Use GIF only when an auto-playing loop genuinely reads better (tiny interaction loops), and mind the 10 MB image limit.

```bash
ffmpeg -i demo.mov -vf "fps=10,scale=800:-1:flags=lanczos" -loop 0 demo.gif
```

## Fitting oversized files

```bash
ls -la file            # check against limits before uploading

# Video: re-encode smaller (raise crf / lower scale until it fits)
ffmpeg -i big.mov -vf "scale=1280:-2" -c:v libx264 -crf 28 -preset slow -an small.mp4

# PNG resize without ffmpeg (macOS built-in)
sips -Z 1600 big.png --out smaller.png
```

No ffmpeg? Playwright's browser cache ships one at `~/Library/Caches/ms-playwright/ffmpeg-*/ffmpeg-mac` (Linux: `~/.cache/ms-playwright/`), but it is a minimal build: fine for re-encoding and scaling, **no `lavfi`/filter-source support**.

## Generated images

Diagrams, annotated screenshots, and illustrations are ordinary image files — produce them with whatever the session has (an image-generation skill, Mermaid/SVG rendered to PNG, annotation tooling) and feed them through the same fit → upload → embed → verify pipeline.

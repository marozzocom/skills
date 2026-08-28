---
name: image-gen
description: Generate or edit images (illustrations, logos, diagrams, infographics, textures, placeholder art, photo edits) via the OpenAI Images API. Use whenever the user asks for an image to be created, or a task needs visual assets — hero images, icons, social cards, mockup imagery. Supports text-to-image and image+prompt editing.
---

# Image generation

A bash-callable CLI lives next to this file. It bills the user's OpenAI API account (roughly $0.04–$0.25/image depending on quality/size), so don't generate large batches without being asked.

## Commands

```bash
# Text → image (writes PNG, prints the path)
bun ~/.claude/skills/image-gen/genimage.ts generate "prompt" out.png \
  [--size 1024x1024|1536x1024|1024x1536|auto] [--quality low|medium|high|auto] \
  [--model gpt-image-1.5] [--transparent] [--n 2]

# Edit / iterate: input image(s) + prompt → new image
bun ~/.claude/skills/image-gen/genimage.ts edit input.png "make the background dusk" out.png

# List image models this key can use
bun ~/.claude/skills/image-gen/genimage.ts models
```

## The loop that matters

After every generation, **Read the output PNG to look at it**. Judge it against the request; if it misses, either regenerate with a sharper prompt or use `edit` with the current output as input for targeted fixes. Editing preserves composition; regenerating rerolls everything. Show the user the final path.

## Practical notes

- Default model is `gpt-image-1.5` (override with `--model` or `GENIMAGE_MODEL` env). If a model errors as unknown, run the `models` subcommand and pick from what the key actually has.
- This model family is unusually good at **legible text in images** (labels, diagrams, infographics) and instruction-following. For diagrams, consider whether SVG/Mermaid written by hand beats a raster image first.
- `--transparent` gives a transparent background (logos, sprites, cut-outs).
- `--quality low` is cheap and fast — good for drafts; re-run the winner at `high`.
- Auth: uses `$OPENAI_API_KEY` if set. Otherwise, if both `$GENIMAGE_PASS_VAULT` and `$GENIMAGE_PASS_ITEM` are set, it reads the key from Proton Pass via `pass-cli`. If pass-cli says no session, ask the user to run `! pass-cli login`. With neither configured it fails with that instruction rather than guessing.
- To publish a result to Furnace media storage, use the `media_upload_image` MCP tool with the generated file.

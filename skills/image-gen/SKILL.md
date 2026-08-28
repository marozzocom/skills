---
name: image-gen
description: Generate or edit raster images with the OpenAI Images API. Use when the user says "generate an image," "make a hero image," "create an illustration/logo/icon/social card," "edit this photo," "remove or replace the background," "make this image transparent," or asks for raster mockup imagery, textures, sprites, or visual variants. Do not use when hand-authored SVG, HTML/CSS, Mermaid, or another code-native format better fits the requested artifact.
---

# Image generation

Use the Bun CLI in this skill's directory for text-to-image generation and prompt-based edits. Requests bill the user's OpenAI API account; confirm scope before generating a large batch.

## Run

Resolve `genimage.ts` relative to this `SKILL.md`, then run:

```bash
# Text to image
bun <skill-directory>/genimage.ts generate "prompt" [output.png] [options]

# Edit one or more images
bun <skill-directory>/genimage.ts edit input.png [input2.png ...] "describe the intended result" [output.png] [options]

# Options: --size SIZE --quality low|medium|high|auto --model MODEL --transparent --n COUNT

# List image models available to the configured key
bun <skill-directory>/genimage.ts models
```

The default model is `gpt-image-2`; `--model` overrides `$GENIMAGE_MODEL`, which overrides the default. The output path must end in `.png`. Multiple results are written as `name-1.png`, `name-2.png`, and so on.

Authentication uses `$OPENAI_API_KEY`. As an optional fallback, set both `$GENIMAGE_PASS_VAULT` and `$GENIMAGE_PASS_ITEM` to read the key from Proton Pass with `pass-cli`. If that command reports an expired session, ask the user to run `pass-cli login`; do not print or echo a key.

## Iterate

After every generation, inspect the actual output image. Compare composition, dimensions, text, transparency, and requested details against the user's intent. Use `edit` for a targeted correction that should preserve the composition; generate again when the concept itself needs a new attempt. Use low quality for drafts and a higher quality only for the selected result.

Return the final image path and mention any requested property you could not verify. For diagrams or layout-sensitive graphics, prefer SVG, Mermaid, or HTML/CSS when those formats offer more reliable geometry and text.

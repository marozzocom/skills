#!/usr/bin/env bun
/**
 * genimage — generate or edit images via the OpenAI Images API.
 *
 * Usage:
 *   bun genimage.ts generate "prompt" [outfile.png] [--model M] [--size S] [--quality Q] [--transparent] [--n N]
 *   bun genimage.ts edit input.png [input2.png ...] "prompt" [outfile.png] [--model M] [--size S] [--quality Q]
 *   bun genimage.ts models
 *
 * Sizes: 1024x1024 (default), 1536x1024 (landscape), 1024x1536 (portrait), auto
 * Quality: low | medium | high | auto (default)
 *
 * API key resolution order:
 *   1. $OPENAI_API_KEY
 *   2. Proton Pass CLI, when $GENIMAGE_PASS_VAULT and $GENIMAGE_PASS_ITEM are set
 */

// Optional secret-manager fallback. Both are opt-in via env so the skill ships
// with no org-specific configuration baked in; without them the key must come
// from $OPENAI_API_KEY.
const PASS_VAULT = process.env.GENIMAGE_PASS_VAULT;
const PASS_ITEM = process.env.GENIMAGE_PASS_ITEM;
const DEFAULT_MODEL = process.env.GENIMAGE_MODEL ?? "gpt-image-1.5";

async function getApiKey(): Promise<string> {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY;
  if (!PASS_VAULT || !PASS_ITEM)
    throw new Error(
      "No OpenAI key. Set $OPENAI_API_KEY, or set $GENIMAGE_PASS_VAULT and $GENIMAGE_PASS_ITEM to read it from Proton Pass via pass-cli.",
    );
  const proc = Bun.spawn(
    ["pass-cli", "item", "view", "--vault-name", PASS_VAULT, "--item-title", PASS_ITEM, "--output", "json"],
    { stdout: "pipe", stderr: "pipe" },
  );
  const out = await new Response(proc.stdout).text();
  const err = await new Response(proc.stderr).text();
  if ((await proc.exited) !== 0) {
    throw new Error(
      `pass-cli failed (is it logged in? run: pass-cli login):\n${err.trim()}`,
    );
  }
  // Find any field value that looks like an OpenAI key, regardless of item schema.
  const match = out.match(/sk-[A-Za-z0-9_-]{20,}/);
  if (!match) throw new Error(`No OpenAI key (sk-...) found in Proton Pass item "${PASS_ITEM}"`);
  return match[0];
}

type Flags = { model: string; size: string; quality: string; n: number; transparent: boolean };

function parseFlags(args: string[]): { positional: string[]; flags: Flags } {
  const flags: Flags = { model: DEFAULT_MODEL, size: "1024x1024", quality: "auto", n: 1, transparent: false };
  const positional: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--model") flags.model = args[++i];
    else if (a === "--size") flags.size = args[++i];
    else if (a === "--quality") flags.quality = args[++i];
    else if (a === "--n") flags.n = parseInt(args[++i], 10);
    else if (a === "--transparent") flags.transparent = true;
    else positional.push(a);
  }
  return { positional, flags };
}

async function writeImages(data: any, outfile: string): Promise<string[]> {
  const written: string[] = [];
  const images = data.data ?? [];
  for (let i = 0; i < images.length; i++) {
    const path = images.length === 1 ? outfile : outfile.replace(/\.png$/, `-${i + 1}.png`);
    if (images[i].b64_json) {
      await Bun.write(path, Buffer.from(images[i].b64_json, "base64"));
    } else if (images[i].url) {
      const res = await fetch(images[i].url);
      await Bun.write(path, await res.arrayBuffer());
    } else {
      throw new Error(`Image ${i} has neither b64_json nor url`);
    }
    written.push(path);
  }
  return written;
}

async function apiError(res: Response): Promise<never> {
  const body = await res.text();
  throw new Error(`API error ${res.status}: ${body}`);
}

const [cmd, ...rest] = process.argv.slice(2);

if (!cmd || !["generate", "edit", "models"].includes(cmd)) {
  console.error("Usage: genimage.ts generate|edit|models ... (see header comment)");
  process.exit(1);
}

const key = await getApiKey();

if (cmd === "models") {
  const res = await fetch("https://api.openai.com/v1/models", {
    headers: { Authorization: `Bearer ${key}` },
  });
  if (!res.ok) await apiError(res);
  const data = await res.json();
  const imageModels = data.data
    .map((m: any) => m.id)
    .filter((id: string) => /image|dall/i.test(id))
    .sort();
  console.log(imageModels.join("\n") || "(no image models visible to this key)");
  process.exit(0);
}

const { positional, flags } = parseFlags(rest);

if (cmd === "generate") {
  const [prompt, outfile = "image.png"] = positional;
  if (!prompt) throw new Error("generate requires a prompt");
  const body: Record<string, unknown> = {
    model: flags.model,
    prompt,
    size: flags.size,
    quality: flags.quality,
    n: flags.n,
  };
  if (flags.transparent) body.background = "transparent";
  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
  if (!res.ok) await apiError(res);
  const written = await writeImages(await res.json(), outfile);
  console.log(written.join("\n"));
} else if (cmd === "edit") {
  // positional: one or more input images, then prompt, then optional outfile
  const inputs: string[] = [];
  let i = 0;
  while (i < positional.length && (await Bun.file(positional[i]).exists())) {
    inputs.push(positional[i++]);
  }
  const prompt = positional[i++];
  const outfile = positional[i] ?? "edited.png";
  if (inputs.length === 0) throw new Error("edit requires at least one existing input image");
  if (!prompt) throw new Error("edit requires a prompt after the input image(s)");

  const form = new FormData();
  form.append("model", flags.model);
  form.append("prompt", prompt);
  form.append("size", flags.size);
  form.append("quality", flags.quality);
  for (const input of inputs) {
    const file = Bun.file(input);
    form.append("image[]", new File([await file.arrayBuffer()], input.split("/").pop()!, { type: file.type || "image/png" }));
  }
  const res = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}` },
    body: form,
  });
  if (!res.ok) await apiError(res);
  const written = await writeImages(await res.json(), outfile);
  console.log(written.join("\n"));
}

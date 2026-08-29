#!/usr/bin/env bun
/**
 * Generate or edit PNG images with the OpenAI Images API.
 *
 * Usage:
 *   bun genimage.ts generate "prompt" [outfile.png] [options]
 *   bun genimage.ts edit input.png [input2.png ...] "prompt" [outfile.png] [options]
 *   bun genimage.ts models
 */

import { stat } from "node:fs/promises";
import { resolve } from "node:path";

const DEFAULT_MODEL = process.env.GENIMAGE_MODEL?.trim() || "gpt-image-2";
const PASS_VAULT = process.env.GENIMAGE_PASS_VAULT?.trim();
const PASS_ITEM = process.env.GENIMAGE_PASS_ITEM?.trim();
const API_BASE = "https://api.openai.com/v1";
const QUALITIES = new Set(["low", "medium", "high", "auto"]);
const INPUT_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp"]);

const USAGE = `Usage:
  bun genimage.ts generate "prompt" [outfile.png] [options]
  bun genimage.ts edit input.png [input2.png ...] "prompt" [outfile.png] [options]
  bun genimage.ts models

Options:
  --model MODEL       Default: $GENIMAGE_MODEL or ${DEFAULT_MODEL}
  --size SIZE         auto or WIDTHxHEIGHT (default: 1024x1024)
  --quality QUALITY   low, medium, high, or auto (default: auto)
  --n COUNT           Integer 1-10 (default: 1)
  --transparent       Request a transparent PNG background
  -h, --help          Show this help

Use -- before a prompt that begins with --.`;

class UsageError extends Error {}

type Flags = {
  model: string;
  size: string;
  quality: string;
  n: number;
  transparent: boolean;
};

type ParsedArgs = { positional: string[]; flags: Flags; literalStart: number | null };

type ApiImage = { b64_json?: unknown; url?: unknown };
type ImageResponse = { data?: unknown };

function requireFlagValue(args: string[], index: number, flag: string): string {
  const value = args[index + 1];
  if (value === undefined || value.startsWith("--"))
    throw new UsageError(`${flag} requires a value.`);
  return value;
}

function parseFlags(args: string[]): ParsedArgs {
  const flags: Flags = {
    model: DEFAULT_MODEL,
    size: "1024x1024",
    quality: "auto",
    n: 1,
    transparent: false,
  };
  const positional: string[] = [];
  const seen = new Set<string>();
  let literalStart: number | null = null;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--") {
      literalStart = positional.length;
      positional.push(...args.slice(i + 1));
      break;
    }
    if (!arg.startsWith("-")) {
      positional.push(arg);
      continue;
    }
    if (arg === "-h" || arg === "--help") throw new UsageError(USAGE);
    if (!["--model", "--size", "--quality", "--n", "--transparent"].includes(arg))
      throw new UsageError(`Unknown option: ${arg}`);
    if (seen.has(arg)) throw new UsageError(`Option may only be specified once: ${arg}`);
    seen.add(arg);

    if (arg === "--transparent") {
      flags.transparent = true;
      continue;
    }
    const value = requireFlagValue(args, i, arg);
    i++;
    if (arg === "--model") flags.model = value.trim();
    else if (arg === "--size") flags.size = value.toLowerCase();
    else if (arg === "--quality") flags.quality = value.toLowerCase();
    else if (arg === "--n") flags.n = Number(value);
  }

  if (!flags.model) throw new UsageError("--model cannot be empty.");
  if (flags.size !== "auto" && !/^[1-9]\d*x[1-9]\d*$/.test(flags.size))
    throw new UsageError("--size must be auto or WIDTHxHEIGHT, for example 1024x1024.");
  if (!QUALITIES.has(flags.quality))
    throw new UsageError("--quality must be low, medium, high, or auto.");
  if (!Number.isSafeInteger(flags.n) || flags.n < 1 || flags.n > 10)
    throw new UsageError("--n must be an integer from 1 to 10.");

  return { positional, flags, literalStart };
}

function inputExtension(path: string): string {
  const dot = path.lastIndexOf(".");
  return dot >= 0 ? path.slice(dot).toLowerCase() : "";
}

function validateOutputPath(outfile: string): void {
  if (!outfile.toLowerCase().endsWith(".png"))
    throw new UsageError(`Output path must end in .png: ${outfile}`);
}

function outputPath(outfile: string, index: number, total: number): string {
  return total === 1 ? outfile : `${outfile.slice(0, -4)}-${index + 1}.png`;
}

async function getApiKey(): Promise<string> {
  const environmentKey = process.env.OPENAI_API_KEY?.trim();
  if (environmentKey) return environmentKey;

  if (Boolean(PASS_VAULT) !== Boolean(PASS_ITEM)) {
    const missing = PASS_VAULT ? "$GENIMAGE_PASS_ITEM" : "$GENIMAGE_PASS_VAULT";
    throw new Error(
      `Secret-manager fallback is incomplete: set ${missing}, or unset both fallback variables and set $OPENAI_API_KEY.`,
    );
  }
  if (!PASS_VAULT || !PASS_ITEM) {
    throw new Error(
      "No OpenAI API key configured. Set $OPENAI_API_KEY, or set both $GENIMAGE_PASS_VAULT and $GENIMAGE_PASS_ITEM to use Proton Pass via pass-cli.",
    );
  }

  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(
      [
        "pass-cli",
        "item",
        "view",
        "--vault-name",
        PASS_VAULT,
        "--item-title",
        PASS_ITEM,
        "--output",
        "json",
      ],
      { stdout: "pipe", stderr: "pipe" },
    );
  } catch (error) {
    throw new Error(
      `Could not start pass-cli: ${error instanceof Error ? error.message : String(error)}. Install pass-cli or set $OPENAI_API_KEY.`,
    );
  }

  const [status, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (status !== 0) {
    const detail = stderr.trim() || `exit code ${status}`;
    throw new Error(`pass-cli could not read the configured item: ${detail}. Log in with "pass-cli login" and try again.`);
  }
  const match = stdout.match(/sk-[A-Za-z0-9_-]{20,}/);
  if (!match) {
    throw new Error(
      "The configured Proton Pass item did not contain a recognizable OpenAI API key. Update the item or set $OPENAI_API_KEY.",
    );
  }
  return match[0];
}

async function request(url: string, init: RequestInit, action: string): Promise<Response> {
  let response: Response;
  try {
    response = await fetch(url, init);
  } catch (error) {
    throw new Error(
      `${action} could not reach the OpenAI API: ${error instanceof Error ? error.message : String(error)}. Check the network connection and try again.`,
    );
  }
  if (!response.ok) await apiError(response, action);
  return response;
}

async function apiError(response: Response, action: string): Promise<never> {
  const raw = await response.text();
  let detail = raw.trim();
  try {
    const parsed = JSON.parse(raw);
    detail = parsed?.error?.message || parsed?.error?.code || detail;
  } catch {
    // The response was not JSON; its text is still useful diagnostics.
  }
  if (detail.length > 800) detail = `${detail.slice(0, 800)}…`;
  const requestId = response.headers.get("x-request-id");
  const recovery =
    response.status === 401
      ? " Check $OPENAI_API_KEY or the configured secret-manager item."
      : response.status === 429
        ? " Check account quota and rate limits, then retry."
        : response.status >= 500
          ? " This is usually transient; retry the request."
          : "";
  throw new Error(
    `${action} failed with OpenAI API HTTP ${response.status}${detail ? `: ${detail}` : "."}${recovery}${requestId ? ` Request ID: ${requestId}.` : ""}`,
  );
}

function responseImages(data: ImageResponse): ApiImage[] {
  if (!Array.isArray(data?.data) || data.data.length === 0)
    throw new Error("The OpenAI API returned no images. Retry once; if it persists, inspect the API response and account access.");
  return data.data as ApiImage[];
}

async function writeImages(
  data: ImageResponse,
  outfile: string,
  protectedPaths: ReadonlySet<string> = new Set(),
): Promise<string[]> {
  const images = responseImages(data);
  const paths = images.map((_, index) => outputPath(outfile, index, images.length));
  const collision = paths.find((path) => protectedPaths.has(resolve(path)));
  if (collision)
    throw new Error(`The API response would write over an input image: ${collision}. Choose another output path.`);
  const written: string[] = [];
  for (let i = 0; i < images.length; i++) {
    const path = paths[i];
    let bytes: Uint8Array | ArrayBuffer;
    const encoded = images[i].b64_json;
    const remoteUrl = images[i].url;
    if (typeof encoded === "string" && encoded.length > 0) {
      bytes = Buffer.from(encoded, "base64");
      if (bytes.byteLength === 0) throw new Error(`Image ${i + 1} contained empty base64 data.`);
    } else if (typeof remoteUrl === "string" && remoteUrl.length > 0) {
      const download = await request(remoteUrl, {}, `Downloading image ${i + 1}`);
      bytes = await download.arrayBuffer();
      if (bytes.byteLength === 0) throw new Error(`Downloaded image ${i + 1} was empty.`);
    } else {
      throw new Error(`Image ${i + 1} had neither base64 data nor a download URL.`);
    }
    try {
      await Bun.write(path, bytes);
    } catch (error) {
      throw new Error(
        `Could not write image ${i + 1} to "${path}": ${error instanceof Error ? error.message : String(error)}. Check that the parent directory exists and is writable.`,
      );
    }
    written.push(path);
  }
  return written;
}

async function validateInputs(paths: string[], outfile: string, outputCount: number): Promise<void> {
  const outputs = new Set(
    Array.from({ length: outputCount }, (_, index) => resolve(outputPath(outfile, index, outputCount))),
  );
  for (const path of paths) {
    const extension = inputExtension(path);
    if (!INPUT_EXTENSIONS.has(extension))
      throw new UsageError(`Unsupported input type for "${path}". Use PNG, JPEG, or WebP.`);
    let inputStat;
    try {
      inputStat = await stat(path);
    } catch (error) {
      if (typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT")
        throw new UsageError(`Input image does not exist: ${path}`);
      throw new Error(`Could not inspect input image "${path}": ${error instanceof Error ? error.message : String(error)}`);
    }
    if (!inputStat.isFile()) throw new UsageError(`Input image is not a regular file: ${path}`);
    if (inputStat.size === 0) throw new UsageError(`Input image is empty: ${path}`);
    if (inputStat.size >= 50 * 1024 * 1024) throw new UsageError(`Input image must be smaller than 50 MB: ${path}`);
    if (outputs.has(resolve(path)))
      throw new UsageError(`Output path must differ from every input image: ${outfile}`);
  }
}

async function runGenerate(args: string[]): Promise<void> {
  const { positional, flags } = parseFlags(args);
  if (positional.length < 1 || positional.length > 2)
    throw new UsageError("generate requires a prompt and accepts one optional output path.");
  const [prompt, outfile = "image.png"] = positional;
  if (!prompt.trim()) throw new UsageError("generate requires a non-empty prompt.");
  validateOutputPath(outfile);

  const key = await getApiKey();
  const body: Record<string, unknown> = {
    model: flags.model,
    prompt,
    size: flags.size,
    quality: flags.quality,
    n: flags.n,
  };
  if (flags.transparent) body.background = "transparent";
  const response = await request(
    `${API_BASE}/images/generations`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify(body),
    },
    "Image generation",
  );
  console.log((await writeImages(await response.json(), outfile)).join("\n"));
}

async function runEdit(args: string[]): Promise<void> {
  const { positional, flags, literalStart } = parseFlags(args);
  const inputs: string[] = [];
  let index = 0;
  const inputLimit = literalStart ?? positional.length;
  while (index < inputLimit && INPUT_EXTENSIONS.has(inputExtension(positional[index]))) {
    inputs.push(positional[index++]);
  }
  const remaining = positional.slice(index);
  if (inputs.length === 0)
    throw new UsageError("edit requires at least one PNG, JPEG, or WebP input before the prompt.");
  if (remaining.length < 1 || remaining.length > 2)
    throw new UsageError("edit requires a prompt and accepts one optional output path after it.");
  const [prompt, outfile = "edited.png"] = remaining;
  if (!prompt.trim()) throw new UsageError("edit requires a non-empty prompt after the input image(s).");
  validateOutputPath(outfile);
  await validateInputs(inputs, outfile, flags.n);

  const key = await getApiKey();
  const form = new FormData();
  form.append("model", flags.model);
  form.append("prompt", prompt);
  form.append("size", flags.size);
  form.append("quality", flags.quality);
  form.append("n", String(flags.n));
  if (flags.transparent) form.append("background", "transparent");
  for (const input of inputs) {
    const file = Bun.file(input);
    const name = input.split(/[\\/]/).pop() || "image.png";
    form.append("image[]", new File([await file.arrayBuffer()], name, { type: file.type || "application/octet-stream" }));
  }
  const response = await request(
    `${API_BASE}/images/edits`,
    { method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form },
    "Image edit",
  );
  console.log(
    (
      await writeImages(
        await response.json(),
        outfile,
        new Set(inputs.map((input) => resolve(input))),
      )
    ).join("\n"),
  );
}

async function runModels(args: string[]): Promise<void> {
  if (args.length > 0) throw new UsageError("models does not accept arguments.");
  const key = await getApiKey();
  const response = await request(
    `${API_BASE}/models`,
    { headers: { Authorization: `Bearer ${key}` } },
    "Model listing",
  );
  const data = await response.json();
  if (!Array.isArray(data?.data)) throw new Error("The model-list response did not contain a data array.");
  const models = data.data
    .map((model: unknown) =>
      typeof model === "object" && model !== null && "id" in model ? String(model.id) : "",
    )
    .filter((id: string) => /image|dall/i.test(id))
    .sort();
  console.log(models.join("\n") || "(no image models visible to this key)");
}

async function main(): Promise<void> {
  const [command, ...args] = process.argv.slice(2);
  if (command === "-h" || command === "--help" || (args.length === 1 && ["-h", "--help"].includes(args[0]))) {
    console.log(USAGE);
    return;
  }
  if (!command) throw new UsageError(USAGE);
  if (command === "generate") return runGenerate(args);
  if (command === "edit") return runEdit(args);
  if (command === "models") return runModels(args);
  throw new UsageError(`Unknown command: ${command}`);
}

main().catch((error: unknown) => {
  if (error instanceof UsageError) {
    console.error(error.message);
    if (error.message !== USAGE) console.error("\nRun with --help for usage.");
    process.exitCode = 2;
    return;
  }
  console.error(`genimage: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});

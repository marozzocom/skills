# image-gen — maintainer notes

This skill provides a small command-line bridge to the OpenAI Images API. It handles text-to-image generation, one-or-many-image edits, authentication, and writing API results to predictable PNG paths.

## Setup and prerequisites

Install or symlink this directory into the host agent's skills directory. Runtime requirements:

- [Bun](https://bun.sh/)
- an OpenAI API key in `OPENAI_API_KEY`
- network access to `api.openai.com`

The optional Proton Pass fallback additionally requires `pass-cli`, a logged-in session, and both `GENIMAGE_PASS_VAULT` and `GENIMAGE_PASS_ITEM`. This fallback is opt-in so the tracked skill contains no machine or account configuration.

There is no package install. Verify changes with:

```bash
bun build genimage.ts --target=bun --outfile=/dev/null
```

## Design rationale

- A single Bun script keeps installation and invocation simple while using only built-in web APIs and Bun primitives.
- Direct HTTP requests avoid an SDK dependency for three stable endpoints: generations, edits, and model listing.
- Parsing and local validation happen before authentication or network work. Usage errors exit with status 2; authentication, API, download, and filesystem failures exit with status 1 and include a recovery hint.
- Output is deliberately PNG-only. That keeps transparent output and multi-image filename expansion deterministic.
- `GENIMAGE_MODEL` and `--model` keep model choice portable. Update the default and documented common sizes only after checking current official API documentation.

Keep account-specific secret-manager coordinates outside the repository, and never add examples that display a key.

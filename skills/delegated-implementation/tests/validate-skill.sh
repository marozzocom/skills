#!/usr/bin/env bash
# tests/validate-skill.sh — structural validation of the skill directory:
# frontmatter shape, name/directory agreement, description bounds, every
# file SKILL.md and the phase files point at exists, every bin script is
# executable and parses under the system bash, and the portable protocol
# files name no agent harness, vendor, or model.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here" || exit 2
errors=0
err() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

# --- frontmatter -----------------------------------------------------------
head -n1 SKILL.md | grep -qx -- '---' || err "SKILL.md must start with a --- frontmatter fence"
fm=$(awk 'NR==1{next} /^---$/{exit} {print}' SKILL.md)
name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')
[ "$name" = "$(basename "$here")" ] || err "frontmatter name '$name' != directory '$(basename "$here")'"
desc=$(printf '%s\n' "$fm" | awk '/^description:/{flag=1} flag{print}' | sed '1s/^description:[[:space:]]*//' | tr '\n' ' ' | sed 's/^"//; s/"[[:space:]]*$//')
[ -n "$desc" ] || err "frontmatter description missing"
[ "${#desc}" -le 1024 ] || err "description is ${#desc} chars (>1024)"
printf '%s\n' "$fm" | grep -q '^[a-z][a-z_-]*:' || err "frontmatter has no keys"

# --- referenced files exist ------------------------------------------------
for f in SKILL.md references/phase-*.md references/brief-template.md references/run-report.md; do
  for ref in $(grep -o -E '(references/[a-z-]+\.(template\.)?md|bin/[a-z-]+\.sh|phase-[a-z]+\.md|brief-template\.md|run-report\.md)' "$f" | sort -u); do
    case $ref in
      references/*|bin/*) [ -e "$ref" ] || err "$f references missing $ref" ;;
      *) [ -e "references/$ref" ] || err "$f references missing references/$ref" ;;
    esac
  done
done
# local-by-nature references have templates
for local in environment review-checklists agent-trust-profiles; do
  [ -e "references/$local.template.md" ] || err "missing references/$local.template.md"
done

# --- scripts ---------------------------------------------------------------
for s in bin/*.sh; do
  [ -x "$s" ] || err "$s is not executable"
  /bin/bash -n "$s" || err "$s fails bash -n under $(/bin/bash --version | head -n1)"
  head -n1 "$s" | grep -q 'bash' || err "$s lacks a bash shebang"
done

# --- portability: no harness, vendor, or model names in protocol files -----
portable="SKILL.md references/phase-design.md references/phase-execution.md references/phase-review.md references/phase-landing.md references/brief-template.md references/run-report.md"
pattern='claude|anthropic|codex|openai|gpt-|cursor|grok|gemini|copilot|sonnet|opus|bugbot|gh-media|macos|darwin'
hits=$(grep -n -i -E "$pattern" $portable || true)
[ -z "$hits" ] || err "vendor/harness names in portable files:
$hits"

if [ "$errors" = 0 ]; then echo "skill validation ok ($name)"; exit 0; fi
echo "skill validation: $errors error(s)" >&2
exit 1

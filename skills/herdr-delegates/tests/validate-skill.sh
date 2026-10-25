#!/usr/bin/env bash
# tests/validate-skill.sh — structural validation of the skill directory:
# frontmatter shape, name/directory agreement, description bounds, every
# bin script SKILL.md names exists, is executable and parses under the
# system bash, Markdown links resolve, and SKILL.md names no agent vendor
# or model (Herdr itself is this skill's subject and is allowed).
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

# --- referenced helpers exist ----------------------------------------------
while IFS= read -r ref; do
  [ -e "$ref" ] || err "SKILL.md references missing $ref"
done < <(grep -o -E 'bin/[a-z-]+\.sh' SKILL.md | sort -u)

# --- scripts ---------------------------------------------------------------
for s in bin/*.sh; do
  [ -x "$s" ] || err "$s is not executable"
  /bin/bash -n "$s" || err "$s fails bash -n under $(/bin/bash --version | head -n1)"
  head -n1 "$s" | grep -q 'bash' || err "$s lacks a bash shebang"
done
for s in tests/*.sh; do
  /bin/bash -n "$s" || err "$s fails bash -n"
done

# --- Markdown links resolve relative to their file ---------------------------
link_pattern='\]\(([^)]*)\)'
while IFS= read -r -d '' f; do
  link_base=${f%/*}
  while IFS= read -r line || [[ -n $line ]]; do
    remaining=$line
    while [[ $remaining =~ $link_pattern ]]; do
      target=${BASH_REMATCH[1]}
      remaining=${remaining#*"${BASH_REMATCH[0]}"}
      case $target in https:*|http:*|mailto:*|\#*) continue ;; esac
      target=${target%%#*}
      [[ -e $link_base/$target ]] || err "$f links to missing $target"
    done
  done <"$f"
done < <(find . -type f -name '*.md' -print0)

# --- portability: SKILL.md names no vendor or model -------------------------
pattern='claude|anthropic|codex|openai|gpt-|cursor|grok|gemini|copilot|sonnet|opus|bugbot|macos|darwin'
hits=$(grep -n -i -E "$pattern" SKILL.md | grep -v 'CLAUDE_SKILL_DIR' || true)
[ -z "$hits" ] || err "vendor names in SKILL.md:
$hits"

if [ "$errors" = 0 ]; then echo "skill validation ok ($name)"; exit 0; fi
echo "skill validation: $errors error(s)" >&2
exit 1

#!/usr/bin/env bash
# Land a worktree as a pull request in one uninterrupted process:
#   stage the named paths → commit → push → gh pr create --body-file
#   → optional squash auto-merge → run-marker injection.
# On a branch that already has an open PR, the same sequence updates it:
# commit → push; the PR body gains the run marker only if it lacks one.
#
# Why one process: a forked or backgrounded agent turn that ends while the
# pre-commit hook is still running gets the hook SIGTERMed, leaving files
# staged and nothing landed. Run this in a background shell instead and read
# its last line: `PR <url>` (created) or `PR <url> updated` on success,
# `FAILED <stage>: <detail>` otherwise. Hooks run: the script never passes
# --no-verify unless you do.
#
# Usage:
#   land-pr.sh <worktree> --title "<type(scope): subject>" --body-file <file>
#              --stage <path> [--stage <path>]...
#              [--base <branch>] [--auto-merge] [--run-id <id>]
#              [--attribution "<final line>"] [--trailer "<Key: value>"]...
#              [--allow-unlanded] [--no-verify]
#
# Staging is explicit: only `--stage` paths are added (`git add -A -- <path>`,
# so a deletion under a named path is staged too); a path that is neither
# on disk nor tracked is an error. Anything already staged before the script
# runs is ambiguous — it may be a half-finished hook, or work nobody named —
# and fails the run before any mutation. Every other dirty path (modified or
# untracked and not under a --stage path) is "unlanded": the run stops before
# mutation and lists them, unless --allow-unlanded is passed, in which case
# they are printed as NOTE lines so no success line hides them.
#
# The body file is the PR body, passed verbatim through --body-file.
# `--run-id` inserts the invisible `<!-- herdr-run: <id> -->` marker so
# `run-report.sh` can find the PR; `--attribution` names a line the body
# must end with (a harness's required final attribution) — the marker is
# inserted before it, and it is appended if absent.
# Exit: 0 landed, 1 failed (last line says which stage).

set -euo pipefail

fail() { printf 'FAILED %s\n' "$*"; exit 1; }

[[ $# -ge 1 ]] || fail "usage: worktree path required"
WORKTREE=$1; shift
TITLE='' BODY_FILE='' BASE='' AUTO_MERGE=0 RUN_ID='' NO_VERIFY=0
ATTRIBUTION='' ALLOW_UNLANDED=0
TRAILERS=() STAGE_PATHS=()

need_value() { [[ $# -ge 2 && -n $2 ]] || fail "args: $1 requires a value"; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --title) need_value "$@"; TITLE=$2; shift 2 ;;
    --body-file) need_value "$@"; BODY_FILE=$2; shift 2 ;;
    --stage) need_value "$@"; STAGE_PATHS+=("$2"); shift 2 ;;
    --base) need_value "$@"; BASE=$2; shift 2 ;;
    --auto-merge) AUTO_MERGE=1; shift ;;
    --run-id) need_value "$@"; RUN_ID=$2; shift 2 ;;
    --attribution) need_value "$@"; ATTRIBUTION=$2; shift 2 ;;
    --allow-unlanded) ALLOW_UNLANDED=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    --trailer) need_value "$@"; TRAILERS+=("$2"); shift 2 ;;
    *) fail "args: unknown option $1" ;;
  esac
done

[[ -n $TITLE ]] || fail "args: --title is required"
[[ -n $BODY_FILE && -f $BODY_FILE ]] || fail "args: --body-file must name an existing file"
[[ -d $WORKTREE/.git || -f $WORKTREE/.git ]] || fail "args: $WORKTREE is not a git worktree"
BODY_FILE=$(cd "$(dirname "$BODY_FILE")" && pwd)/$(basename "$BODY_FILE")

# shellcheck source=gh-json.sh
. "$(dirname "$0")/gh-json.sh"
GH=${GH:-gh}

cd "$WORKTREE" || fail "args: cannot cd into $WORKTREE"

BRANCH=$(git rev-parse --abbrev-ref HEAD) || fail "git: cannot read branch"
[[ $BRANCH != main && $BRANCH != master && $BRANCH != HEAD ]] || fail "branch: refusing to land from $BRANCH"

if [[ -z $BASE ]]; then
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  BASE=${BASE:-main}
fi

# --- pre-mutation checks -------------------------------------------------

git diff --cached --quiet \
  || fail "stage: index already has staged changes — unstage them or name them with --stage: $(git diff --cached --name-only | tr '\n' ' ')"

for p in ${STAGE_PATHS[@]+"${STAGE_PATHS[@]}"}; do
  [[ -e $p ]] || git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 \
    || fail "stage: $p is neither on disk nor tracked"
done

# Dirty paths not covered by a --stage path. A --stage directory covers
# everything beneath it.
covered() {
  local path=$1 s
  for s in ${STAGE_PATHS[@]+"${STAGE_PATHS[@]}"}; do
    s=${s%/}
    [[ $path == "$s" || $path == "$s"/* ]] && return 0
  done
  return 1
}
unlanded=()
while IFS= read -r line; do
  [[ -n $line ]] || continue
  path=${line:3}
  path=${path#\"}; path=${path%\"}
  case $path in *" -> "*) path=${path##* -> } ;; esac
  covered "$path" || unlanded+=("$path")
done < <(git status --porcelain --untracked-files=all)

if [[ ${#unlanded[@]} -gt 0 ]]; then
  if [[ $ALLOW_UNLANDED -eq 0 ]]; then
    fail "unlanded: ${#unlanded[@]} changed path(s) not named by --stage (pass --stage or --allow-unlanded): ${unlanded[*]}"
  fi
  for p in "${unlanded[@]}"; do printf 'NOTE unlanded: %s\n' "$p"; done
fi

existing=''
if url_json=$(gh_json pr view "$BRANCH" --json url,body) && [[ -n $url_json ]]; then
  existing=$(jq -r '.url // empty' <<<"$url_json")
fi

# --- body assembly (literal; only the ends are touched) -------------------

# Read the file byte-for-byte (the trailing-x trick keeps final newlines).
raw=$(cat "$BODY_FILE"; printf x); raw=${raw%x}
body=${raw%"${raw##*[![:space:]]}"}
if [[ -n $ATTRIBUTION ]]; then
  last=${body##*$'\n'}
  if [[ $last == "$ATTRIBUTION" ]]; then
    body=${body%"$last"}
    body=${body%"${body##*[![:space:]]}"}
  fi
fi
if [[ -n $RUN_ID ]]; then
  body=$(printf '%s\n\n<!-- herdr-run: %s -->' "$body" "$RUN_ID")
fi
if [[ -n $ATTRIBUTION ]]; then
  body=$(printf '%s\n\n%s' "$body" "$ATTRIBUTION")
fi
FINAL_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/land-pr-body.XXXXXX")
trap 'rm -f "$FINAL_BODY_FILE"' EXIT
printf '%s\n' "$body" >"$FINAL_BODY_FILE"

# --- mutation -------------------------------------------------------------

if [[ ${#STAGE_PATHS[@]} -gt 0 ]]; then
  git add -A -- "${STAGE_PATHS[@]}" || fail "stage: git add"
fi
if ! git diff --cached --quiet; then
  msg=$TITLE
  for t in ${TRAILERS[@]+"${TRAILERS[@]}"}; do
    [[ -n $t ]] && msg=$(printf '%s\n\n%s' "$msg" "$t")
  done
  verify=()
  [[ $NO_VERIFY -eq 1 ]] && verify=(--no-verify)
  git commit -q ${verify[@]+"${verify[@]}"} -m "$msg" || fail "commit: pre-commit hook or commit failed (see hook output above)"
fi

ahead=$(git rev-list --count "origin/$BASE..HEAD" 2>/dev/null || echo 1)
[[ $ahead -gt 0 ]] || fail "commit: nothing to land — branch has no commits beyond origin/$BASE"

if [[ -n $existing ]] && git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null \
   && [[ $(git rev-list --count "origin/$BRANCH..HEAD") -eq 0 ]] && git diff --quiet "origin/$BRANCH" HEAD; then
  printf 'PR %s unchanged — nothing new to land\n' "$existing"
  exit 0
fi

push=()
[[ $NO_VERIFY -eq 1 ]] && push=(--no-verify)
if ! git push -q ${push[@]+"${push[@]}"} -u origin "$BRANCH"; then
  # A bot (e.g. a CI mender) may have pushed onto the branch since we last
  # fetched. Rebase onto it once and retry; anything else is a real failure.
  git fetch -q origin "$BRANCH" 2>/dev/null || fail "push: git push (pre-push hook or remote rejected)"
  git merge-base --is-ancestor "origin/$BRANCH" HEAD \
    && fail "push: git push (pre-push hook or remote rejected)"
  git rebase -q "origin/$BRANCH" || { git rebase --abort 2>/dev/null; fail "push: remote moved and rebase onto origin/$BRANCH conflicts"; }
  git push -q ${push[@]+"${push[@]}"} -u origin "$BRANCH" || fail "push: git push after rebasing onto origin/$BRANCH"
fi

if [[ -n $existing ]]; then
  if [[ -n $RUN_ID ]] && ! jq -e --arg m "<!-- herdr-run: $RUN_ID -->" '(.body // "") | contains($m)' <<<"$url_json" >/dev/null; then
    "$GH" pr edit "$existing" --body-file "$FINAL_BODY_FILE" >/dev/null 2>&1 \
      || fail "pr: gh pr edit could not add the run marker to $existing"
  fi
  printf 'PR %s updated\n' "$existing"
  exit 0
fi

url=$("$GH" pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$FINAL_BODY_FILE" 2>&1 | tail -n1) \
  || fail "pr: gh pr create: $url"
[[ $url == https://* ]] || fail "pr: gh pr create returned: $url"

if [[ $AUTO_MERGE -eq 1 ]]; then
  "$GH" pr merge --auto --squash "$url" >/dev/null 2>&1 || fail "auto-merge: gh pr merge --auto failed for $url"
fi

printf 'PR %s\n' "$url"

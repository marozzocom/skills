#!/usr/bin/env bash
# Land a worktree as a pull request in one uninterrupted process:
#   stage → commit → push (upstream) → gh pr create from a body file
#   → optional squash auto-merge → run-marker injection.
#
# Why one process: a forked or backgrounded agent turn that ends while the
# pre-commit hook is still running gets the hook SIGTERMed, leaving files
# staged and nothing landed. Run this in a background shell instead and read
# its last line: `PR <url>` on success, `FAILED <stage>: <detail>` otherwise.
#
# Usage:
#   land-pr.sh <worktree> --title "<type(scope): subject>" --body-file <file>
#              [--base <branch>] [--auto-merge] [--run-id <id>]
#              [--no-verify] [--trailer "<Key: value>"]...
#
# The body file is the PR body verbatim; `--run-id` appends the invisible
# `<!-- herdr-run: <id> -->` marker so `run-report.sh` can find the PR.
# Nothing to commit but the branch is ahead of its base → commit is skipped
# and the push/PR proceed. Already-open PR for the branch → its URL is printed.

set -euo pipefail

fail() { printf 'FAILED %s\n' "$*"; exit 1; }

[[ $# -ge 1 ]] || fail "usage: worktree path required"
WORKTREE=$1; shift
TITLE='' BODY_FILE='' BASE='' AUTO_MERGE=0 RUN_ID='' NO_VERIFY=0
TRAILERS=()

need_value() { [[ $# -ge 2 && -n $2 ]] || fail "args: $1 requires a value"; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --title) need_value "$@"; TITLE=$2; shift 2 ;;
    --body-file) need_value "$@"; BODY_FILE=$2; shift 2 ;;
    --base) need_value "$@"; BASE=$2; shift 2 ;;
    --auto-merge) AUTO_MERGE=1; shift ;;
    --run-id) need_value "$@"; RUN_ID=$2; shift 2 ;;
    --no-verify) NO_VERIFY=1; shift ;;
    --trailer) need_value "$@"; TRAILERS+=("$2"); shift 2 ;;
    *) fail "args: unknown option $1" ;;
  esac
done

[[ -n $TITLE ]] || fail "args: --title is required"
[[ -n $BODY_FILE && -f $BODY_FILE ]] || fail "args: --body-file must name an existing file"
[[ -d $WORKTREE/.git || -f $WORKTREE/.git ]] || fail "args: $WORKTREE is not a git worktree"

cd "$WORKTREE" || fail "args: cannot cd into $WORKTREE"

BRANCH=$(git rev-parse --abbrev-ref HEAD) || fail "git: cannot read branch"
[[ $BRANCH != main && $BRANCH != master && $BRANCH != HEAD ]] || fail "branch: refusing to land from $BRANCH"

if [[ -z $BASE ]]; then
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  BASE=${BASE:-main}
fi

if existing=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null) && [[ -n $existing ]]; then
  printf 'PR %s\n' "$existing"
  exit 0
fi

BODY=$(cat "$BODY_FILE")
if [[ -n $RUN_ID ]]; then
  BODY=$(printf '%s\n\n<!-- herdr-run: %s -->\n' "$BODY" "$RUN_ID")
fi

git add -A || fail "stage: git add"
if ! git diff --cached --quiet; then
  msg=$TITLE
  for t in "${TRAILERS[@]:-}"; do
    [[ -n $t ]] && msg=$(printf '%s\n\n%s' "$msg" "$t")
  done
  verify=()
  [[ $NO_VERIFY -eq 1 ]] && verify=(--no-verify)
  git commit -q ${verify[@]+"${verify[@]}"} -m "$msg" || fail "commit: pre-commit hook or commit failed (see hook output above)"
fi

ahead=$(git rev-list --count "origin/$BASE..HEAD" 2>/dev/null || echo 1)
[[ $ahead -gt 0 ]] || fail "commit: nothing to land — branch has no commits beyond origin/$BASE"

push=()
[[ $NO_VERIFY -eq 1 ]] && push=(--no-verify)
git push -q ${push[@]+"${push[@]}"} -u origin "$BRANCH" || fail "push: git push (pre-push hook or remote rejected)"

url=$(gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body "$BODY" 2>&1 | tail -n1) \
  || fail "pr: gh pr create: $url"
[[ $url == https://* ]] || fail "pr: gh pr create returned: $url"

if [[ $AUTO_MERGE -eq 1 ]]; then
  gh pr merge --auto --squash "$url" >/dev/null 2>&1 || fail "auto-merge: gh pr merge --auto failed for $url"
fi

printf 'PR %s\n' "$url"

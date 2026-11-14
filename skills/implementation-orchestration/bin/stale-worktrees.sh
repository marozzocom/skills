#!/usr/bin/env bash
# stale-worktrees.sh [REPO_DIR]
# Lists the linked worktrees of REPO_DIR (default: the current directory)
# whose branch has a merged pull request, so a finished run cannot leave
# them behind unnoticed. Read-only: it never removes anything; removal
# follows phase-landing.md §Closeout step 4.
# One line per such worktree:
#   STALE <path> #<pr> <branch>           clean, HEAD is the merged PR's head
#                                         commit, no process has its cwd there
#   KEEP <path> #<pr> <branch> <reason>   dirty | head-differs | in-use |
#                                         locked (git worktree lock) |
#                                         status-failed (git status failed) |
#                                         cwd-unchecked (no lsof or /proc)
#   UNKNOWN <path> <branch>               gh could not answer for this branch
# A worktree with no branch, or whose branch has no merged PR from this
# repository (fork PRs do not count), prints nothing. When one branch has
# several merged PRs, the one whose head commit is HEAD decides.
# Limits: ignored files (build output, but also a local .env) do not make a
# tree dirty, and removing the worktree deletes them; "in use" sees only a
# process whose working directory is inside the tree, not one that edits it
# by absolute path.
# Exit: 0 nothing stale, 3 at least one STALE, 1 git or gh failed (not
# checked — any lines printed are still true), 2 usage.
set -u

[ $# -le 1 ] || { echo "usage: stale-worktrees.sh [REPO_DIR]" >&2; exit 2; }
dir=${1:-.}
fail() { echo "ERROR: $*" >&2; exit 1; }
list=$(git -C "$dir" worktree list --porcelain 2>/dev/null) || fail "not a git repository: $dir"
command -v gh >/dev/null 2>&1 || fail "gh not found"
command -v jq >/dev/null 2>&1 || fail "jq not found"

# One read of every process's working directory; empty when unavailable.
cwds=''; cwd_source=none
if command -v lsof >/dev/null 2>&1 && cwds=$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p') && [ -n "$cwds" ]; then
  cwd_source=lsof
elif [ -d /proc/self ]; then
  cwds=$(for p in /proc/[0-9]*; do readlink "$p/cwd" 2>/dev/null; done); cwd_source=proc
fi
in_use() { printf '%s\n' "$cwds" | grep -q -x -F -e "$1" || printf '%s\n' "$cwds" | grep -q -F -e "$1/"; }

stale=0; failed=0; first=1; path=''; head=''; branch=''; locked=0
check() {
  [ -n "$path" ] || return 0
  if [ "$first" = 1 ]; then first=0; return 0; fi  # the main worktree
  [ -n "$branch" ] || return 0
  local prs match number status
  if ! prs=$(cd "$dir" && gh pr list --head "$branch" --state merged --limit 50 \
      --json number,headRefName,headRefOid,isCrossRepository 2>/dev/null) ||
     ! prs=$(printf '%s' "$prs" | jq -c --arg b "$branch" \
      'if type == "array" then map(select(.headRefName == $b and (.isCrossRepository | not))) else error("shape") end' 2>/dev/null); then
    printf 'UNKNOWN %s %s\n' "$path" "$branch"; failed=1; return 0
  fi
  [ "$(jq 'length' <<<"$prs")" -gt 0 ] || return 0
  match=$(jq -r --arg h "$head" '[.[] | select(.headRefOid == $h)][0].number // empty' <<<"$prs")
  if [ -z "$match" ]; then
    number=$(jq -r '.[0].number' <<<"$prs")
    printf 'KEEP %s #%s %s head-differs\n' "$path" "$number" "$branch"
  elif [ "$locked" = 1 ]; then
    printf 'KEEP %s #%s %s locked\n' "$path" "$match" "$branch"
  elif ! status=$(git -C "$path" status --porcelain 2>/dev/null); then
    printf 'KEEP %s #%s %s status-failed\n' "$path" "$match" "$branch"
  elif [ -n "$status" ]; then
    printf 'KEEP %s #%s %s dirty\n' "$path" "$match" "$branch"
  elif [ "$cwd_source" = none ]; then
    printf 'KEEP %s #%s %s cwd-unchecked\n' "$path" "$match" "$branch"
  elif in_use "$path"; then
    printf 'KEEP %s #%s %s in-use\n' "$path" "$match" "$branch"
  else
    printf 'STALE %s #%s %s\n' "$path" "$match" "$branch"; stale=1
  fi
}
while IFS= read -r line; do
  case $line in
    'worktree '*) check; path=${line#worktree }; head=''; branch=''; locked=0 ;;
    locked|'locked '*) locked=1 ;;
    'HEAD '*) head=${line#HEAD } ;;
    'branch refs/heads/'*) branch=${line#branch refs/heads/} ;;
  esac
done <<<"$list"
check
[ "$failed" = 0 ] || exit 1
[ "$stale" = 0 ] || exit 3
exit 0

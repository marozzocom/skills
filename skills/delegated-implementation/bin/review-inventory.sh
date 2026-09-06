#!/usr/bin/env bash
# review-inventory.sh <worktree> <base-rev>
# The complete set of changed artifacts a review must cover, relative to the
# task's base: committed, staged and unstaged changes (git name-status) plus
# untracked additions (marked ??). One path per line, `<status>\t<path>`.
# Reconcile a triage manifest against this list by path identity, never by
# count.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <worktree> <base-rev>" >&2; exit 2; }
wt=$1; base=$2
git -C "$wt" rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "review-inventory: base '$base' is not a commit" >&2; exit 2; }
{
  git -C "$wt" diff --name-status "$base"
  git -C "$wt" ls-files --others --exclude-standard | sed 's/^/??\t/'
} | sort -k2

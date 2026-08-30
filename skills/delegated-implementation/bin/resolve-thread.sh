#!/usr/bin/env bash
# resolve-thread.sh <owner/repo> <pr-number> <comment-id> <message> [--no-resolve]
#
# Reply to a PR review comment in-thread, then resolve the thread it
# belongs to — one call and one output line, instead of three gh
# invocations whose JSON lands in the orchestrator's context.
# <comment-id> is the finding comment's databaseId (its REST id). Pass
# --no-resolve for a reply that must leave the thread open (deferred items,
# questions back to the reviewer).
# Exit: 0 on success, 1 when the thread cannot be found or a call fails,
# 2 usage error.
set -euo pipefail

repo=${1:?usage: resolve-thread.sh <owner/repo> <pr> <comment-id> <message> [--no-resolve]}
pr=${2:?usage: resolve-thread.sh <owner/repo> <pr> <comment-id> <message> [--no-resolve]}
cid=${3:?usage: resolve-thread.sh <owner/repo> <pr> <comment-id> <message> [--no-resolve]}
msg=${4:?usage: resolve-thread.sh <owner/repo> <pr> <comment-id> <message> [--no-resolve]}
resolve=1
[ "${5:-}" = "--no-resolve" ] && resolve=0

case $pr in *[!0-9]*|'') echo "ERROR: pr must be a number: $pr" >&2; exit 2;; esac
case $cid in *[!0-9]*|'') echo "ERROR: comment-id must be a number: $cid" >&2; exit 2;; esac

owner=${repo%%/*}
name=${repo##*/}

gh api "repos/$repo/pulls/$pr/comments" \
  -f body="$msg" -F in_reply_to="$cid" --jq '.id' >/dev/null

if [ "$resolve" = 0 ]; then
  echo "REPLIED (left open): comment $cid on $repo#$pr"
  exit 0
fi

tid=$(gh api graphql \
  -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviewThreads(first:100){nodes{id comments(first:100){nodes{databaseId}}}}}}}' \
  -f owner="$owner" -f name="$name" -F pr="$pr" \
  --jq ".data.repository.pullRequest.reviewThreads.nodes[] | select(any(.comments.nodes[]; .databaseId == $cid)) | .id")

[ -n "$tid" ] || { echo "ERROR: no review thread contains comment $cid on $repo#$pr (replied, not resolved)" >&2; exit 1; }

gh api graphql \
  -f query='mutation($tid:ID!){resolveReviewThread(input:{threadId:$tid}){thread{isResolved}}}' \
  -f tid="$tid" --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null

echo "RESOLVED: thread $tid (comment $cid) on $repo#$pr"

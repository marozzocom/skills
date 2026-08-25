#!/usr/bin/env bash
# watch-pr.sh <owner/repo> <pr-number> [poll-seconds]
#
# CI poll loop for a Monitor-style harness: emits one line per check as it
# reaches a terminal state, and a final ALL-SETTLED line. Designed to be run
# under a background monitor that turns stdout lines into notifications —
# never as a long-lived `gh pr checks --watch` (macOS QoS kills those).
#
# Correctness properties (the reasons this is a script, not ad-hoc prose):
#   - an empty check list means "checks not registered yet", not "done"
#   - every terminal bucket is emitted (pass/fail/cancel/skipping), so a
#     failure is as loud as a success — silence only ever means "pending"
#   - transient gh/API errors are survived, not fatal
# Exit: 0 all pass/skip, 1 any fail/cancel.
set -u

repo=${1:?usage: watch-pr.sh <owner/repo> <pr-number> [poll-seconds]}
pr=${2:?usage: watch-pr.sh <owner/repo> <pr-number> [poll-seconds]}
poll=${3:-30}

seen_file=$(mktemp)
trap 'rm -f "$seen_file"' EXIT

while true; do
  s=$(gh pr checks "$pr" --repo "$repo" --json name,bucket 2>/dev/null) || { sleep "$poll"; continue; }
  jq -e 'length > 0' <<<"$s" >/dev/null 2>&1 || { sleep "$poll"; continue; }

  # Emit each newly-terminal check once.
  jq -r '.[] | select(.bucket != "pending") | "\(.bucket)\t\(.name)"' <<<"$s" |
    while IFS=$'\t' read -r bucket name; do
      grep -qxF "$name" "$seen_file" 2>/dev/null && continue
      printf '%s\n' "$name" >>"$seen_file"
      case $bucket in
        pass)     echo "PASS: $name" ;;
        skipping) echo "SKIP: $name" ;;
        fail)     echo "FAIL: $name" ;;
        cancel)   echo "CANCELLED: $name" ;;
        *)        echo "$bucket: $name" ;;
      esac
    done

  if jq -e 'all(.bucket != "pending")' <<<"$s" >/dev/null 2>&1; then
    if jq -e 'all(.bucket == "pass" or .bucket == "skipping")' <<<"$s" >/dev/null 2>&1; then
      echo "ALL-SETTLED: PR #$pr green"
      exit 0
    fi
    echo "ALL-SETTLED: PR #$pr has failures"
    exit 1
  fi
  sleep "$poll"
done

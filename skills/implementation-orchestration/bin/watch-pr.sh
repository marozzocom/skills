#!/usr/bin/env bash
# watch-pr.sh <owner/repo> <pr-number> [poll-seconds]
#
# CI poll loop for a background monitor: emits one line per check as it
# reaches a terminal state, and a final ALL-SETTLED line. Designed to be run
# under a monitor that turns stdout lines into notifications, on platforms
# where a long-lived `gh pr checks --watch` is unreliable (notes in
# references/environment.md).
#
# Reads `gh pr view --json statusCheckRollup`, never `gh pr checks`: the
# latter exits non-zero for failed *and* pending checks, so a loop that
# treats every non-zero exit as a transport failure can never report a
# failure — and some gh wrappers suppress stdout on a non-zero exit. The
# rollup read succeeds whenever the PR exists, so a non-zero exit there is
# a real transport failure. Both record types are normalized: CheckRun
# (status + conclusion) and StatusContext (state). The gh in PATH may be the
# native CLI (JSON inline) or a wrapper that prints the path of a JSON file.
#
# Correctness properties (the reasons this is a script, not ad-hoc prose):
#   - an empty check list means "checks not registered yet", not "done"
#   - every terminal bucket is emitted (pass/fail/cancel/skip), so a
#     failure is as loud as a success — silence only ever means "pending"
#   - transient transport errors are retried and reported as RETRY lines,
#     never folded into a verdict; a run of them beyond
#     WATCH_PR_MAX_TRANSPORT_FAILURES (default 20) ends the watch visibly
#   - WATCH_PR_MAX_POLLS (default unlimited) bounds a watch whose checks
#     never settle, ending it with a STILL-PENDING line instead of silence
# Exit: 0 all pass/skip, 1 any fail/cancel, 2 usage, 3 transport gave up,
#       4 poll budget exhausted while checks were still pending.
set -u

repo=${1:?usage: watch-pr.sh <owner/repo> <pr-number> [poll-seconds]}
pr=${2:?usage: watch-pr.sh <owner/repo> <pr-number> [poll-seconds]}
poll=${3:-30}
max_failures=${WATCH_PR_MAX_TRANSPORT_FAILURES:-20}
max_polls=${WATCH_PR_MAX_POLLS:-0}

case $pr in *[!0-9]*|'') echo "usage: pr must be a number: $pr" >&2; exit 2;; esac
case $poll in *[!0-9]*|'') echo "usage: poll-seconds must be a number: $poll" >&2; exit 2;; esac

# shellcheck source=gh-json.sh
. "$(dirname "$0")/gh-json.sh"

seen_file=$(mktemp)
trap 'rm -f "$seen_file"' EXIT

# One record per check: "<bucket>\t<key>\t<display name>". Bucket mirrors
# gh's own vocabulary: pass, fail, cancel, skipping, pending.
normalize='
  .statusCheckRollup // []
  | map(
      if .__typename == "StatusContext" then
        { key: ("status:" + (.context // "")),
          name: (.context // "unnamed status"),
          verdict: (if .state == "SUCCESS" then "pass"
                    elif .state == "FAILURE" or .state == "ERROR" then "fail"
                    else "pending" end) }
      else
        { key: ((.workflowName // "") + "/" + (.name // "")),
          name: (if (.workflowName // "") == "" then (.name // "unnamed check")
                 else (.workflowName + " / " + (.name // "unnamed check")) end),
          verdict: (if .status != "COMPLETED" then "pending"
                    elif .conclusion == "SUCCESS" then "pass"
                    elif .conclusion == "SKIPPED" or .conclusion == "NEUTRAL" then "skipping"
                    elif .conclusion == "CANCELLED" then "cancel"
                    elif .conclusion == null or .conclusion == "" then "pending"
                    else "fail" end) }
      end)
'

failures=0
polls=0
while true; do
  polls=$((polls + 1))
  if [ "$max_polls" -gt 0 ] && [ "$polls" -gt "$max_polls" ]; then
    echo "STILL-PENDING: PR #$pr has unsettled checks after $max_polls polls — watch ended, not a verdict"
    exit 4
  fi
  if ! raw=$(gh_json pr view "$pr" --repo "$repo" --json statusCheckRollup) \
     || ! s=$(jq -c "$normalize" <<<"$raw" 2>/dev/null); then
    failures=$((failures + 1))
    echo "RETRY: could not read checks for PR #$pr (transport failure $failures/$max_failures)"
    if [ "$failures" -ge "$max_failures" ]; then
      echo "GAVE-UP: PR #$pr checks unreadable after $failures consecutive transport failures"
      exit 3
    fi
    sleep "$poll"; continue
  fi
  failures=0

  jq -e 'length > 0' <<<"$s" >/dev/null 2>&1 || { sleep "$poll"; continue; }

  # Emit each newly-terminal check once, keyed by workflow + name so two
  # jobs sharing a name in different workflows both get reported.
  jq -r '.[] | select(.verdict != "pending") | "\(.verdict)\t\(.key)\t\(.name)"' <<<"$s" |
    while IFS=$'\t' read -r verdict key name; do
      grep -qxF "$key" "$seen_file" 2>/dev/null && continue
      printf '%s\n' "$key" >>"$seen_file"
      case $verdict in
        pass)     echo "PASS: $name" ;;
        skipping) echo "SKIP: $name" ;;
        fail)     echo "FAIL: $name" ;;
        cancel)   echo "CANCELLED: $name" ;;
        *)        echo "$verdict: $name" ;;
      esac
    done

  if jq -e 'all(.verdict != "pending")' <<<"$s" >/dev/null 2>&1; then
    if jq -e 'all(.verdict == "pass" or .verdict == "skipping")' <<<"$s" >/dev/null 2>&1; then
      echo "ALL-SETTLED: PR #$pr green"
      exit 0
    fi
    echo "ALL-SETTLED: PR #$pr has failures"
    exit 1
  fi
  sleep "$poll"
done

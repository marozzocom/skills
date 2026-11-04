#!/usr/bin/env bash
# run-report.sh <run-id> <owner/repo> [ledger-file]
#
# Gathers the deterministic half of the §Closeout run report and prints a
# report skeleton to stdout. The orchestrator fills in the judgment half
# (highlights, verdicts, what to do differently) per
# references/run-report.md — this script never invents those.
#
# Deterministic inputs:
#   - PRs carrying the run marker `<!-- herdr-run: <run-id> -->` (state,
#     additions/deletions, merged time) via gh
#   - teardown post-state reads: `herdr pane list`, `git worktree list`
#   - the ledger file, echoed by path for the timeline source
set -euo pipefail

run_id=${1:?usage: run-report.sh <run-id> <owner/repo> [ledger-file]}
repo=${2:?usage: run-report.sh <run-id> <owner/repo> [ledger-file]}
ledger=${3:-}

echo "# Run report: $run_id"
echo
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$ledger" ] && echo "Ledger (timeline source): $ledger"
echo
echo "## PRs"
echo
# gh's search is token-based: it also returns other runs' markers and ids
# that merely start with this one, so keep only bodies with the exact marker.
# RUN_REPORT_PR_LIMIT caps the candidates fetched: 1-1000, default 1000 (gh
# paginates; GitHub search returns at most 1000, so larger values are clamped).
marker="<!-- herdr-run: $run_id -->"
limit=${RUN_REPORT_PR_LIMIT:-1000}
case $limit in ''|*[!0-9]*|0*) echo "run-report.sh: RUN_REPORT_PR_LIMIT must be 1-1000" >&2; exit 2 ;; esac
[ "${#limit}" -le 4 ] && [ "$limit" -le 1000 ] || limit=1000
if prs=$(gh pr list --repo "$repo" --state all --limit "$limit" \
    --search "\"herdr-run: $run_id\" in:body" \
    --json number,title,state,additions,deletions,mergedAt,body 2>/dev/null); then
  # Exactly one JSON array, or the response is not trusted (empty included).
  if lines=$(printf '%s' "$prs" | jq -rs --arg m "$marker" --argjson cap "$limit" '
      if length == 1 and (.[0] | type) == "array" then .[0] else error("shape") end |
      (map(select((.body | type) == "string" and (.body | contains($m)))) |
        map("- #\(.number) \(.title) — \(.state)\(if .mergedAt then " (merged \(.mergedAt))" else "" end), +\(.additions)/-\(.deletions)")) as $rows |
      if ($rows | length) == 0 then ["- (no PR carries \($m) — check the ledger'"'"'s PR list)"] else $rows end +
      (if length >= $cap then ["- (warning: gh returned \(length) candidates, the fetch limit; the list may be incomplete — " + (if $cap >= 1000 then "that is GitHub'"'"'s search ceiling, check the ledger" else "raise RUN_REPORT_PR_LIMIT (max 1000) or check the ledger" end) + ")"] else [] end) |
      .[]' 2>/dev/null); then
    printf '%s\n' "$lines"
  else
    echo "- (could not parse gh output — list PRs manually from the ledger)"
  fi
else
  echo "- (gh query failed — list PRs manually from the ledger)"
fi
echo
echo "## Teardown post-state (evidence, not narrative)"
echo
echo '### herdr pane list'
echo '```'
# The optional transport helper owns all Herdr CLI calls.
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/../../herdr-delegates/bin/herdr-backend.sh
if [ -x "$backend" ]; then
  if [ -n "$ledger" ] && [ -f "$(dirname "$ledger")/status.json" ]; then
    export HERDR_BACKEND_RUN_DIR=$(dirname "$ledger")
  fi
  "$backend" panes 2>/dev/null | jq -r '.[] | "\(.id)\t\(.agent)\t\(.status)\t\(.cwd)"' 2>/dev/null || echo "herdr unavailable"
else echo "herdr unavailable"; fi
echo '```'
echo
echo '### git worktree list'
echo '```'
git worktree list 2>&1 || true
echo '```'
echo
cat <<'EOF'
## Timeline
<!-- Orchestrator: render from the timestamped ledger — agent spawns,
     rotations, gates with verdicts, fix rounds, teardown. -->

## Stats
<!-- Orchestrator: fix rounds per implementer, review escalations, wall
     time. Report only what was measured — delegate-side token spend is not
     observable; never invent it. -->

## Per-node outcomes
<!-- Orchestrator: one row per node, from the ledger's task-fit and gate
     lines. Measured values only; `not measured` where not; `none known`
     for post-landing defects. Include single-node and all-direct runs. -->

| node | transport (signal) | implementer (family, effort) | reviewers (families) | fix rounds | findings by family | defects after landing | overseer wall time |
|---|---|---|---|---|---|---|---|

## Experiment
<!-- Orchestrator: what was varied, the judging criterion from the
     contract, the observation, keep / revise / drop — or why none. -->

## Highlights and next-run changes
<!-- Orchestrator: what worked, what cost a round-trip, what the next run
     should do differently. Feed durable items back into the skill's
     references. -->
EOF

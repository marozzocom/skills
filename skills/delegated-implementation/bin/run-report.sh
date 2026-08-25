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
gh pr list --repo "$repo" --state all --limit 100 \
  --search "herdr-run: $run_id in:body" \
  --json number,title,state,additions,deletions,mergedAt \
  --jq '.[] | "- #\(.number) \(.title) — \(.state)\(if .mergedAt then " (merged \(.mergedAt))" else "" end), +\(.additions)/-\(.deletions)"' \
  || echo "- (gh query failed — list PRs manually from the ledger)"
echo
echo "## Teardown post-state (evidence, not narrative)"
echo
echo '### herdr pane list'
echo '```'
# Compact to one line per pane when the JSON shape allows; raw otherwise.
herdr pane list 2>&1 | jq -r '.result.panes[] | "\(.pane_id)\t\(.agent)\t\(.agent_status)\t\(.cwd)"' 2>/dev/null \
  || herdr pane list 2>&1 || echo "herdr unavailable"
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

## Highlights and next-run changes
<!-- Orchestrator: what worked, what cost a round-trip, what the next run
     should do differently. Feed durable items back into the skill's
     references. -->
EOF

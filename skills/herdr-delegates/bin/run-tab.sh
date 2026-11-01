#!/usr/bin/env bash
# run-tab.sh RUN_DIR GROUP CWD
# Creates <prefix>·<GROUP> in status.json herdr.workspace, refusing any
# server-wide label collision. Prints tab=ID pane=ROOT_PANE_ID.
# Exit: 0 created, 1 missing setup/herdr failure/collision, 2 usage.
set -euo pipefail
usage() { echo "usage: run-tab.sh RUN_DIR GROUP CWD" >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -eq 3 ] && [ -n "$2" ] && [ -n "$3" ] || usage
run=$1; group=$2; cwd=$3
prefix=$(jq -er '.prefix | strings | select(length > 0)' "$run/status.json" 2>/dev/null) || fail "run run-cockpit.sh first (prefix missing)"
workspace=$(jq -er '.herdr.workspace | strings | select(length > 0)' "$run/status.json" 2>/dev/null) || fail "run run-cockpit.sh first (workspace missing)"
label=${prefix}·$group
tabs=$(herdr tab list) || fail "herdr tab list failed"
jq -e '.result.tabs|type == "array"' <<<"$tabs" >/dev/null || fail "unreadable herdr tab list"
if jq -e --arg label "$label" 'any(.result.tabs[]; .label == $label)' <<<"$tabs" >/dev/null; then
  fail "tab label already exists: $label"
fi
created=$(herdr tab create --workspace "$workspace" --cwd "$cwd" --label "$label" --no-focus) || fail "tab create failed"
jq -er '.result | select((.tab.tab_id|type) == "string" and (.root_pane.pane_id|type) == "string") |
  "tab=\(.tab.tab_id) pane=\(.root_pane.pane_id)"' <<<"$created" || fail "tab create returned no tab/pane IDs"

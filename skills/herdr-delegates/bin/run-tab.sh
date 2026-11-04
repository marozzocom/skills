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
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/herdr-backend.sh
export HERDR_BACKEND_RUN_DIR=$run
"$backend" flavor "$run" >/dev/null || exit 1
label=${prefix}·$group
tabs=$("$backend" tabs) || fail "herdr tab list failed"
jq -e 'type == "array"' <<<"$tabs" >/dev/null || fail "unreadable herdr tab list"
if jq -e --arg label "$label" 'any(.[]; .label == $label)' <<<"$tabs" >/dev/null; then
  fail "tab label already exists: $label"
fi
"$backend" tab-new "$workspace" "$label" "$cwd" || exit 1

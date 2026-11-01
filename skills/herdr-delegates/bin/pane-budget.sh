#!/usr/bin/env bash
# pane-budget.sh [--pane ID] [--reserve-rows N=0]
# Prints budget=B cols=C rows=R width=W height=H from the selected pane rect.
# B=min(4, max(1,floor(W/PANE_MIN_COLS))*max(1,floor((H-N)/PANE_MIN_ROWS))).
# PANE_MIN_COLS=100 and PANE_MIN_ROWS=30 by default; both positive integers.
# Exit: 0 printed budget, 1 herdr/layout failure, 2 usage.
set -euo pipefail
usage() { echo "usage: pane-budget.sh [--pane ID] [--reserve-rows N]" >&2; exit 2; }
pane=''; reserve=0; min_cols=${PANE_MIN_COLS:-100}; min_rows=${PANE_MIN_ROWS:-30}
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in --pane) pane=$2; [ -n "$pane" ] || usage ;; --reserve-rows) reserve=$2 ;; *) usage ;; esac
  shift 2
done
for n in "$reserve" "$min_cols" "$min_rows"; do case $n in ''|*[!0-9]*) usage ;; esac; done
[ "$min_cols" -gt 0 ] && [ "$min_rows" -gt 0 ] || usage
if [ -n "$pane" ]; then layout=$(herdr pane layout --pane "$pane") || exit 1
else layout=$(herdr pane layout --current) || exit 1; fi
printf '%s' "$layout" | jq -er --arg pane "${pane:-${HERDR_PANE_ID:-}}" --argjson reserve "$reserve" \
  --argjson mc "$min_cols" --argjson mr "$min_rows" '
  .result.layout | . as $layout |
  (if $pane != "" then $pane else ($layout.pane_id // $layout.focused_pane_id) end) as $id |
  [.panes[] | select(.pane_id == $id)][0].rect |
  if . == null then error("pane rect not found") else
    .width as $w | .height as $h |
    ([1, ($w / $mc | floor)] | max) as $c |
    ([1, (($h - $reserve) / $mr | floor)] | max) as $r |
    "budget=\([4, ($c * $r)]|min) cols=\($c) rows=\($r) width=\($w) height=\($h)"
  end' || exit 1

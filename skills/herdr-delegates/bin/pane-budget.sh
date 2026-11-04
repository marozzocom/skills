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
here=$(cd "$(dirname "$0")" && pwd)
if [ -n "$pane" ]; then geometry=$("$here/herdr-backend.sh" geometry "$pane") || exit 1
else geometry=$("$here/herdr-backend.sh" geometry) || exit 1; fi
if [ "$geometry" = unknown ]; then
  echo 'budget=1 cols=1 rows=1 width=unknown height=unknown'; exit 0
fi
read -r width height <<<"$geometry"
jq -ner --argjson w "$width" --argjson h "$height" --argjson reserve "$reserve" \
  --argjson mc "$min_cols" --argjson mr "$min_rows" '
  ([1, ($w / $mc | floor)] | max) as $c |
  ([1, (($h - $reserve) / $mr | floor)] | max) as $r |
  "budget=\([4, ($c * $r)]|min) cols=\($c) rows=\($r) width=\($w) height=\($h)"' || exit 1

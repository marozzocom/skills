#!/usr/bin/env bash
# Rect selection, reservations, environment thresholds and failure codes.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
P="$BIN_DIR/pane-budget.sh"
unset HERDR_PANE_ID
layout() {
  jq -n --argjson w "$1" --argjson h "$2" \
    '{result:{layout:{focused_pane_id:"w1:p1",panes:[{pane_id:"w1:p1",rect:{width:$w,height:$h}},{pane_id:"w1:p2",rect:{width:320,height:80}}]}}}' >"$HERDR_SCENARIO/layout.json"
}
layout 158 71
assert_eq default 'budget=2 cols=1 rows=2 width=158 height=71' "$("$P")"
assert_contains current-selector 'herdr pane layout --current' "$(cat "$MOCK_LOG")"
assert_eq reserve 'budget=2 cols=1 rows=2 width=158 height=71' "$("$P" --reserve-rows 10)"
assert_eq explicit-pane 'budget=4 cols=3 rows=2 width=320 height=80' "$("$P" --pane w1:p2)"
assert_contains pane-selector 'herdr pane layout --pane w1:p2' "$(cat "$MOCK_LOG")"
HERDR_PANE_ID=w1:p2 "$P" >"$SCRATCH/caller"
assert_eq caller-over-focused 'budget=4 cols=3 rows=2 width=320 height=80' "$(cat "$SCRATCH/caller")"
layout 320 80
assert_eq capped 'budget=4 cols=3 rows=2 width=320 height=80' "$("$P")"
layout 90 20
assert_eq small 'budget=1 cols=1 rows=1 width=90 height=20' "$("$P")"
assert_eq exhausted-reservation 'budget=1 cols=1 rows=1 width=90 height=20' "$("$P" --reserve-rows 90)"
assert_eq env-overrides 'budget=4 cols=2 rows=2 width=90 height=20' "$(PANE_MIN_COLS=40 PANE_MIN_ROWS=10 "$P")"
"$P" --pane absent >/dev/null 2>&1; assert_eq absent-pane 1 "$?"
for args in '--reserve-rows -1' '--reserve-rows nope' '--pane' '--other x'; do
  # shellcheck disable=SC2086
  "$P" $args >/dev/null 2>&1; assert_eq "usage-$args" 2 "$?"
done
PANE_MIN_COLS=0 "$P" >/dev/null 2>&1; assert_eq bad-env 2 "$?"
rm "$HERDR_SCENARIO/layout.json"
"$P" >/dev/null 2>&1; assert_eq herdr-fails 1 "$?"
app_fixture
assert_eq app-drawn 'budget=1 cols=1 rows=1 width=114 height=31' "$("$P")"
assert_eq app-pane-map 'budget=1 cols=1 rows=1 width=114 height=31' "$("$P" --pane pa1)"
jq '.[0].cols=200|.[0].rows=120' "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"
mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"
assert_eq app-core-default 'budget=1 cols=1 rows=1 width=unknown height=unknown' "$("$P")"
jq '.[0].cols=120|.[0].rows=40' "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"
mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"
assert_eq app-root-default 'budget=1 cols=1 rows=1 width=unknown height=unknown' "$("$P")"
finish

#!/usr/bin/env bash
# Documented pane enumeration must close every run-created core terminal.
. "$(dirname "$0")/lib.sh"
H=$BIN_DIR/herdr-backend.sh
rewrite_core() { jq "$1" "$HC_SCENARIO/terminals.json" >"$SCRATCH/core"; mv "$SCRATCH/core" "$HC_SCENARIO/terminals.json"; }
setup() {
  app_fixture
  baseline=$(hc ls --all --json)
  "$H" tab-new sp1 'fixture·N1' "$SCRATCH" >/dev/null
}
teardown_node() {
  local pane
  while IFS= read -r pane; do
    "$H" close "$pane" || { assert_eq teardown-close-success 0 "$?"; return 1; }
  done < <("$H" panes | jq -r '.[]|select(.tab=="tbnew1")|.id')
}
setup
rewrite_core '.[1].foreground={name:"zsh",argv:["/bin/zsh","-l"]}'
assert_eq start-adopted tnew1 "$("$H" start worker sh "$SCRATCH" --pane proottbnew1 --timeout 2 -- -c fixture)"
assert_eq adopted-pane-survives-root-disposal '["tnew1"]' "$("$H" panes | jq -c '[.[]|select(.tab=="tbnew1")|.terminal]')"
assert_eq adopted-parent-is-overseer t1 "$(hc get tnew1 --json | jq -r .parent)"
assert_eq no-hidden-root-record-before-teardown 0 "$(hc ls --all --json | jq '[.terminals[]|select(.address=="roottbnew1")]|length')"
teardown_node
assert_eq documented-teardown-no-survivors "$baseline" "$(hc ls --all --json)"

# Missing foreground information preserves the shell as a visible pane;
# the same documented enumeration still closes both run-created terminals.
setup
assert_eq unknown-root-start tnew1 "$("$H" start worker sh "$SCRATCH" --pane proottbnew1 --timeout 2 -- -c fixture)"
assert_eq unknown-root-remains-visible 2 "$("$H" panes | jq '[.[]|select(.tab=="tbnew1")]|length')"
assert_eq unknown-root-still-live live "$(hc get roottbnew1 --json | jq -r .state)"
teardown_node
assert_eq unknown-root-teardown-no-survivors "$baseline" "$(hc ls --all --json)"

# An adoption failure must not consume the available root before replacement.
setup
rewrite_core '.[1].foreground={name:"zsh",argv:["/bin/zsh","-l"]}'
touch "$HC_SCENARIO/no-adoption"
"$H" start worker sh "$SCRATCH" --pane proottbnew1 --timeout 1 -- -c fixture >/dev/null 2>&1
assert_eq failed-adoption 1 "$?"
assert_eq failed-adoption-preserves-root live "$(hc get roottbnew1 --json | jq -r .state)"
assert_eq failed-adoption-only-root '["roottbnew1"]' "$("$H" panes | jq -c '[.[]|select(.tab=="tbnew1")|.terminal]')"
teardown_node
assert_eq failed-adoption-teardown-no-survivors "$baseline" "$(hc ls --all --json)"
finish

#!/usr/bin/env bash
# inbox-resolve.sh: run_id, prefix and <prefix>-overseer targets, live-watcher
# tie-breaking over zombie runs, ambiguity, unwatched and app refusals, bare
# names never read as paths, traversal, heartbeat freshness, dead pids and the
# --once rearm window. No Herdr calls, no HERDR_ENV.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
R=$BIN_DIR/inbox-resolve.sh
unset HERDR_ENV HERDR_PANE_ID ORCHESTRATION_RUNS_DIR
NOW=2030-01-01T01:00:00Z
export INBOX_NOW=$NOW
epoch() { jq -n --arg s "$1" '$s|fromdateiso8601'; }
E=$(epoch "$NOW")
sleep 0 & DEAD=$!; wait "$DEAD"
runs=$SCRATCH/runs; mkdir -p "$runs"; runs=$(cd "$runs" && pwd -P)
mkrun() { # ID PREFIX [FLAVOR] [OVERSEER-STATE]
  mkdir -p "$runs/$1/inbox/new"
  jq -n --arg id "$1" --arg p "$2" --arg f "${3:-}" --arg st "${4:-open}" \
    '{run_id:$id,prefix:$p,herdr:({overseer_pane:"w1:p1"} + (if $f == "" then {} else {flavor:$f} end)),
      agents:[{name:($p + "-overseer"),role:"overseer",state:$st}]}' >"$runs/$1/status.json"
}
watch() { # DIR PID EPOCH [INTERVAL] [REARM]
  mkdir -p "$1/inbox"
  jq -cn --argjson pid "$2" --argjson e "$3" --argjson i "${4:-2}" --arg r "${5:-}" \
    '{pid:$pid,pane:"w1:p1",ts:($e|todateiso8601),epoch:$e,interval:$i} + (if $r == "" then {} else {rearm:true} end)' >"$1/inbox/.watch"
}
res() { "$R" --runs-dir "$runs" "$@"; }

# Direct run_id.
mkrun r-live lv; watch "$runs/r-live" $$ "$E"
assert_eq run-id "$runs/r-live" "$(res r-live)"
mkrun r-quiet qt
err=$(res r-quiet 2>&1 >/dev/null); assert_eq run-id-unwatched 1 "$?"
assert_contains run-id-unwatched-msg 'run r-quiet has no live inbox watcher (pass --allow-unwatched to queue anyway)' "$err"
assert_eq run-id-allow "$runs/r-quiet" "$(res --allow-unwatched r-quiet)"
# Prefix and <prefix>-overseer: one live run wins over open zombie runs.
for z in z-old1 z-old2 z-old3; do mkrun "$z" gm; done
watch "$runs/z-old2" $$ $((E - 3600))  # stale heartbeat, live pid
watch "$runs/z-old3" "$DEAD" "$E"      # fresh heartbeat, dead pid
mkrun z-now gm; watch "$runs/z-now" $$ "$E"
assert_eq prefix "$runs/z-now" "$(res gm)"
assert_eq prefix-overseer "$runs/z-now" "$(res gm-overseer)"
# Two live runs: ambiguous, both named.
mkrun z-now2 gm; watch "$runs/z-now2" $$ "$E"
err=$(res gm-overseer 2>&1 >/dev/null); assert_eq ambiguous 1 "$?"
assert_contains ambiguous-1 'z-now' "$err"; assert_contains ambiguous-2 'z-now2' "$err"
assert_contains ambiguous-msg 'ambiguous target gm-overseer: multiple live runs match' "$err"
assert_eq ambiguous-by-id "$runs/z-now2" "$(res z-now2)"
rm "$runs/z-now/inbox/.watch" "$runs/z-now2/inbox/.watch"
# No live match: refused (counting the unwatched ones); --allow-unwatched
# takes only a single run with an open overseer row.
err=$(res gm 2>&1 >/dev/null); assert_eq none-live 1 "$?"
assert_contains none-live-msg 'no live run matching gm (5 unwatched match(es)' "$err"
res --allow-unwatched gm >/dev/null 2>&1; assert_eq allow-ambiguous 1 "$?"
mkrun u-one uo; mkrun u-two uo '' closed
assert_eq allow-single-open "$runs/u-one" "$(res --allow-unwatched uo-overseer)"
res uo >/dev/null 2>&1; assert_eq single-open-needs-allow 1 "$?"
res nosuch >/dev/null 2>&1; assert_eq no-match 1 "$?"
# App flavor: exit 3, with or without --allow-unwatched, by id, prefix or path.
mkrun a-run ap app; watch "$runs/a-run" $$ "$E"
for args in 'a-run' '--allow-unwatched a-run' 'ap-overseer' '--allow-unwatched ap'; do
  # shellcheck disable=SC2086
  err=$(res $args 2>&1 >/dev/null); assert_eq "app-$args" 3 "$?"
done
assert_contains app-msg 'target run a-run uses app flavor; no inbox watcher' "$err"
"$R" --allow-unwatched "$runs/a-run" >/dev/null 2>&1; assert_eq app-path 3 "$?"
# A live TUI run beats an app run with the same prefix.
mkrun a-tui ap; watch "$runs/a-tui" $$ "$E"
assert_eq app-and-tui "$runs/a-tui" "$(res ap)"
# Paths: a TARGET with / is a directory; without status.json it still needs a
# watcher unless --allow-unwatched.
assert_eq path "$runs/r-live" "$("$R" "$runs/../runs/r-live/")"
bare=$SCRATCH/plain; mkdir -p "$bare"; bare=$(cd "$bare" && pwd -P)
"$R" "$bare" >/dev/null 2>&1; assert_eq path-unwatched 1 "$?"
assert_eq path-allow "$bare" "$("$R" --allow-unwatched "$bare")"
"$R" "$SCRATCH/missing/" >/dev/null 2>&1; assert_eq path-missing 1 "$?"
"$R" ../evil >/dev/null 2>&1; assert_eq path-traversal-missing 1 "$?"
# Bare names are never paths, even when the cwd holds that directory.
# Each cwd directory would resolve as a watched run if it were read as a path.
cwd=$SCRATCH/cwd; mkdir -p "$cwd"
for name in inbox docs; do watch "$cwd/$name" $$ "$E"; echo '{"prefix":"zz","agents":[]}' >"$cwd/$name/status.json"; done
before=$(find "$cwd" | sort)
for name in inbox docs; do
  out=$(cd "$cwd" && "$R" --runs-dir "$runs" --allow-unwatched "$name" 2>/dev/null); assert_eq "bare-$name" 1 "$?"
  assert_eq "bare-$name-out" '' "$out"
done
assert_eq bare-as-path "$(cd "$cwd/docs" && pwd -P)" "$(cd "$cwd" && "$R" ./docs)"
assert_eq bare-untouched "$before" "$(find "$cwd" | sort)"
# Unsafe names: usage.
for bad in . .. 'a b' 'x;y' "$(printf 'a\nb')"; do
  res --allow-unwatched "$bad" >/dev/null 2>&1; assert_eq "unsafe-$bad" 2 "$?"
done
res >/dev/null 2>&1; assert_eq no-target 2 "$?"
res a b >/dev/null 2>&1; assert_eq two-targets 2 "$?"
res --bogus r-live >/dev/null 2>&1; assert_eq bad-flag 2 "$?"
INBOX_NOW=nope res r-live >/dev/null 2>&1; assert_eq bad-clock 2 "$?"
# Heartbeat freshness: max(30, ceil(3 x interval)) seconds; pid must exist
# (pid 0 is never live); a rearm heartbeat is live while fresh, pid gone.
fresh() { watch "$runs/r-live" "$@"; res r-live >/dev/null 2>&1 && echo live || echo unwatched; }
assert_eq fresh-30 live "$(fresh $$ $((E - 30)))"
assert_eq stale-31 unwatched "$(fresh $$ $((E - 31)))"
assert_eq interval-scaled live "$(fresh $$ $((E - 59)) 19.5)"
assert_eq interval-scaled-stale unwatched "$(fresh $$ $((E - 61)) 19.5)"
assert_eq dead-pid unwatched "$(fresh "$DEAD" "$E")"
assert_eq pid-zero unwatched "$(fresh 0 "$E")"
assert_eq rearm-fresh live "$(fresh "$DEAD" $((E - 20)) 2 rearm)"
assert_eq rearm-expired unwatched "$(fresh "$DEAD" $((E - 31)) 2 rearm)"
echo '{"pid":"1","epoch":"x"}' >"$runs/r-live/inbox/.watch"
res r-live >/dev/null 2>&1; assert_eq malformed-watch 1 "$?"
echo 'not json' >"$runs/r-live/inbox/.watch"
res r-live >/dev/null 2>&1; assert_eq garbage-watch 1 "$?"
# Closed runs (overseer rows, none open) are refused by id, path and prefix,
# even with --allow-unwatched or a fresh rearm heartbeat.
mkrun c-run cl '' closed
err=$(res --allow-unwatched c-run 2>&1 >/dev/null); assert_eq closed-id-allow 1 "$?"
assert_contains closed-msg 'target run c-run is closed' "$err"
"$R" --allow-unwatched "$runs/c-run" >/dev/null 2>&1; assert_eq closed-path-allow 1 "$?"
watch "$runs/c-run" "$DEAD" $((E - 5)) 2 rearm
res c-run >/dev/null 2>&1; assert_eq closed-rearm-id 1 "$?"
res cl-overseer >/dev/null 2>&1; assert_eq closed-rearm-prefix 1 "$?"
res --allow-unwatched cl >/dev/null 2>&1; assert_eq closed-rearm-prefix-allow 1 "$?"
watch "$runs/c-run" $$ "$E"
res cl >/dev/null 2>&1; assert_eq closed-live-pid-prefix 1 "$?"
# A run with no overseer row yet is governed by its heartbeat as before.
mkdir -p "$runs/n-run/inbox"; echo '{"prefix":"nr","herdr":{},"agents":[]}' >"$runs/n-run/status.json"
assert_eq no-overseer-allow "$runs/n-run" "$(res --allow-unwatched n-run)"
watch "$runs/n-run" $$ "$E"; assert_eq no-overseer-live "$runs/n-run" "$(res nr)"
# Heartbeat edge cases: far-future epoch, bad intervals, a float pid.
assert_eq future-10 live "$(fresh $$ $((E + 10)))"
assert_eq future-11 unwatched "$(fresh $$ $((E + 11)))"
assert_eq interval-false unwatched "$(fresh $$ "$E" false)"
assert_eq interval-negative unwatched "$(fresh $$ "$E" -1)"
echo "{\"pid\":$$,\"epoch\":$E}" >"$runs/r-live/inbox/.watch"
res r-live >/dev/null 2>&1; assert_eq interval-missing 0 "$?"
assert_eq pid-float live "$(fresh "$$.0" "$E")"
assert_eq pid-fraction unwatched "$(fresh "$$.5" "$E")"
watch "$runs/r-live" $$ "$E"
# Dotfile, leading-dash and bare -overseer targets are usage errors.
mkrun .hidden hd; watch "$runs/.hidden" $$ "$E"
for bad in .hidden -dash -overseer; do
  res --allow-unwatched -- "$bad" >/dev/null 2>&1; assert_eq "unsafe-$bad" 2 "$?"
done
# Runs root: ORCHESTRATION_RUNS_DIR, else XDG_STATE_HOME.
watch "$runs/r-live" $$ "$E"
assert_eq env-runs "$runs/r-live" "$(ORCHESTRATION_RUNS_DIR=$runs "$R" lv)"
xdg=$SCRATCH/xdg; mkdir -p "$xdg/implementation-orchestration"; ln -s "$runs" "$xdg/implementation-orchestration/runs"
assert_eq xdg-runs "$runs/r-live" "$(XDG_STATE_HOME=$xdg "$R" r-live)"
assert_eq no-herdr-calls '' "$(cat "$MOCK_LOG")"
finish

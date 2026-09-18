#!/usr/bin/env bash
# watch-pr.sh against the mock gh: success, failure, cancellation, pending
# and empty rollups, both record types, inline and file-path output, quiet
# wrappers, and transport-failure retry/exhaustion.
. "$(dirname "$0")/lib.sh"
W="$BIN_DIR/watch-pr.sh"
S=$GH_SCENARIO

rollup() { # <file> <json array of records>
  printf '{"statusCheckRollup":%s}\n' "$2" >"$S/$1"
}
run_watch() { # prints "<exit>\n<stdout>"
  local out rc
  out=$(WATCH_PR_MAX_POLLS=${MAXP:-50} WATCH_PR_MAX_TRANSPORT_FAILURES=${MAXF:-20} "$W" o/r 7 0 2>&1); rc=$?
  printf '%s\n%s' "$rc" "$out"
}
reset_seq() { rm -f "$S/pr-view.cursor" "$S/pr-view.sequence" "$S"/*.exit; }

cr() { # CheckRun: <name> <status> <conclusion> [workflow]
  printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":%s,"workflowName":"%s"}' \
    "$1" "$2" "$( [ "$3" = null ] && echo null || printf '"%s"' "$3")" "${4:-CI}"
}
sc() { # StatusContext: <context> <state>
  printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"
}

# --- 1. empty → pending → all green (CheckRun + StatusContext) -------------
reset_seq; echo inline >"$S/mode"
rollup s1.json '[]'
rollup s2.json "[$(cr Test IN_PROGRESS null), $(sc lint PENDING)]"
rollup s3.json "[$(cr Test COMPLETED SUCCESS), $(sc lint SUCCESS), $(cr Docs COMPLETED SKIPPED)]"
printf 's1.json\ns2.json\ns3.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq green-exit 0 "$rc"
assert_contains green-pass "PASS: CI / Test" "$out"
assert_contains green-status-pass "PASS: lint" "$out"
assert_contains green-skip "SKIP: CI / Docs" "$out"
assert_contains green-settled "ALL-SETTLED: PR #7 green" "$out"
assert_eq green-no-early-lines-before-settle "$(printf '%s\n' "$out" | grep -c ALL-SETTLED)" 1

# --- 2. failure: CheckRun FAILURE + StatusContext ERROR, one still pending then done
reset_seq
rollup f1.json "[$(cr Test COMPLETED FAILURE), $(sc deploy ERROR), $(cr Build IN_PROGRESS null)]"
rollup f2.json "[$(cr Test COMPLETED FAILURE), $(sc deploy ERROR), $(cr Build COMPLETED SUCCESS)]"
printf 'f1.json\nf2.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq fail-exit 1 "$rc"
assert_contains fail-checkrun "FAIL: CI / Test" "$out"
assert_contains fail-statuscontext "FAIL: deploy" "$out"
assert_contains fail-later-pass "PASS: CI / Build" "$out"
assert_contains fail-settled "ALL-SETTLED: PR #7 has failures" "$out"
assert_eq fail-emitted-once 1 "$(printf '%s\n' "$out" | grep -c 'FAIL: CI / Test')"

# --- 3. cancellation and timed-out ----------------------------------------
reset_seq
rollup c1.json "[$(cr Test COMPLETED CANCELLED), $(cr Lint COMPLETED TIMED_OUT)]"
printf 'c1.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq cancel-exit 1 "$rc"
assert_contains cancel-line "CANCELLED: CI / Test" "$out"
assert_contains timed-out-is-fail "FAIL: CI / Lint" "$out"

# --- 4. same job name in two workflows is two checks -----------------------
reset_seq
rollup d1.json "[$(cr Test COMPLETED SUCCESS CI), $(cr Test COMPLETED FAILURE Nightly)]"
printf 'd1.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq dup-exit 1 "$rc"
assert_contains dup-pass "PASS: CI / Test" "$out"
assert_contains dup-fail "FAIL: Nightly / Test" "$out"

# --- 5. wrapper prints a file path instead of JSON -------------------------
reset_seq; echo file >"$S/mode"
rollup p1.json "[$(cr Test COMPLETED SUCCESS)]"
printf 'p1.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq file-mode-exit 0 "$rc"
assert_contains file-mode-pass "PASS: CI / Test" "$out"

# --- 6. transport failure retried, then a real failure reported ------------
reset_seq; echo file-quiet >"$S/mode"
rollup t1.json '[]'; echo 1 >"$S/t1.exit"
rollup t2.json "[$(cr Test COMPLETED FAILURE)]"
printf 't1.json\nt1.json\nt2.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq retry-exit 1 "$rc"
assert_eq retry-count 2 "$(printf '%s\n' "$out" | grep -c '^RETRY:')"
assert_contains retry-then-fail "FAIL: CI / Test" "$out"
assert_not_contains retry-never-green "green" "$out"

# --- 7. transport failures exhaust the budget visibly ----------------------
reset_seq; echo inline >"$S/mode"
rollup e1.json '[]'; echo 1 >"$S/e1.exit"
printf 'e1.json\n' >"$S/pr-view.sequence"
r=$(MAXF=3 run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq exhaust-exit 3 "$rc"
assert_contains exhaust-line "GAVE-UP: PR #7" "$out"
assert_not_contains exhaust-no-settled "ALL-SETTLED" "$out"

# --- 8. a non-JSON body (wrapper prose on stdout) is a transport failure ---
reset_seq
printf 'error: rate limited\n' >"$S/n1.json"
rollup n2.json "[$(cr Test COMPLETED SUCCESS)]"
printf 'n1.json\nn2.json\n' >"$S/pr-view.sequence"
r=$(run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq prose-exit 0 "$rc"
assert_eq prose-retried 1 "$(printf '%s\n' "$out" | grep -c '^RETRY:')"

# --- 8b. a check that never settles ends with STILL-PENDING, exit 4 -------
reset_seq
rollup q1.json "[$(cr Test IN_PROGRESS null)]"
printf 'q1.json\n' >"$S/pr-view.sequence"
r=$(MAXP=3 run_watch); rc=${r%%$'\n'*}; out=${r#*$'\n'}
assert_eq still-pending-exit 4 "$rc"
assert_contains still-pending-line "STILL-PENDING: PR #7" "$out"
assert_not_contains still-pending-no-verdict "ALL-SETTLED" "$out"

# --- 9. usage ----------------------------------------------------------------
"$W" o/r abc 0 >/dev/null 2>&1; assert_eq usage-pr 2 "$?"
"$W" o/r 7 x >/dev/null 2>&1; assert_eq usage-poll 2 "$?"

# every read went through pr view, never pr checks
assert_eq never-pr-checks 0 "$(grep -c 'gh pr checks' "$MOCK_LOG")"

finish

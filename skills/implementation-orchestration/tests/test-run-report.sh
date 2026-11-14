#!/usr/bin/env bash
# run-report.sh lists only PRs whose body carries this run's exact marker.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
R="$BIN_DIR/run-report.sh"
id=2026-11-01-run-board
# gh's search is token-based: it also returns other runs' markers, a run id
# that merely extends this one, and bodies that only mention the words.
cat >"$GH_SCENARIO/pr-list.json" <<JSON
[
 {"number":32,"title":"this run","state":"MERGED","additions":10,"deletions":2,"mergedAt":"2026-11-01T11:50:20Z","body":"Body\n\n<!-- herdr-run: $id -->"},
 {"number":2272,"title":"other run","state":"MERGED","additions":5,"deletions":1,"mergedAt":"2026-10-25T08:57:00Z","body":"x\n<!-- herdr-run: 2026-10-24-kvark-r1 -->"},
 {"number":40,"title":"longer id","state":"OPEN","additions":1,"deletions":0,"mergedAt":null,"body":"<!-- herdr-run: $id-v2 -->"},
 {"number":41,"title":"prose mention","state":"OPEN","additions":1,"deletions":0,"mergedAt":null,"body":"see herdr-run: $id for context"},
 {"number":42,"title":"no body","state":"OPEN","additions":3,"deletions":3,"mergedAt":null,"body":null},
 {"number":33,"title":"this run, open","state":"OPEN","additions":7,"deletions":0,"mergedAt":null,"body":"<!-- herdr-run: $id -->\ntrailing text"}
]
JSON
out=$("$R" "$id" o/r 2>&1); rc=$?
assert_eq exit-zero 0 "$rc"
assert_contains own-merged "- #32 this run — MERGED (merged 2026-11-01T11:50:20Z), +10/-2" "$out"
assert_contains own-open "- #33 this run, open — OPEN, +7/-0" "$out"
for n in 2272 40 41 42; do assert_not_contains "excluded-$n" "#$n " "$out"; done
assert_eq two-pr-lines 2 "$(printf '%s\n' "$out" | grep -c '^- #')"
# A run with no marked PR says so instead of printing an empty section.
out=$("$R" 2026-01-01-none o/r 2>&1)
assert_contains none-found 'no PR carries <!-- herdr-run: 2026-01-01-none -->' "$out"
# gh failure keeps the manual fallback line.
echo 1 >"$GH_SCENARIO/pr-list.exit"
out=$("$R" "$id" o/r 2>&1)
assert_contains gh-failure-fallback '(gh query failed — list PRs manually from the ledger)' "$out"
rm "$GH_SCENARIO/pr-list.exit"
# Untrusted responses give exactly one fallback line, nothing on stderr, exit 0.
parse='- (could not parse gh output — list PRs manually from the ledger)'
for case in not-json empty number-array two-docs; do
  case $case in
    not-json) printf 'not-json\n' ;;
    empty) : ;;
    number-array) printf '[1]\n' ;;
    two-docs) printf '[]\n[]\n' ;;
  esac >"$GH_SCENARIO/pr-list.json"
  "$R" "$id" o/r >"$SCRATCH/out" 2>"$SCRATCH/err"; rc=$?
  assert_eq "$case-exit" 0 "$rc"
  assert_eq "$case-one-line" 1 "$(grep -c '^- ' "$SCRATCH/out")"
  assert_contains "$case-fallback" "$parse" "$(cat "$SCRATCH/out")"
  assert_eq "$case-stderr-empty" '' "$(cat "$SCRATCH/err")"
done
# A non-string body is not a match and not an error.
printf '[{"number":5,"title":"t","state":"OPEN","additions":0,"deletions":0,"mergedAt":null,"body":123}]\n' >"$GH_SCENARIO/pr-list.json"
out=$("$R" "$id" o/r 2>&1)
assert_contains numeric-body-no-match "no PR carries <!-- herdr-run: $id -->" "$out"
# The fetch limit applies before the exact filter: a match past it is lost,
# so reaching the limit warns that the list may be incomplete.
jq -n --arg id "$id" '[range(3) | {number:(100+.),title:"other",state:"OPEN",additions:0,deletions:0,mergedAt:null,body:"x"}]
  + [{number:7,title:"late",state:"OPEN",additions:0,deletions:0,mergedAt:null,body:("<!-- herdr-run: " + $id + " -->")}]' >"$GH_SCENARIO/pr-list.json"
out=$(RUN_REPORT_PR_LIMIT=3 "$R" "$id" o/r 2>&1)
assert_contains cap-warning 'gh returned 3 candidates, the fetch limit; the list may be incomplete' "$out"
assert_not_contains cap-truncates '#7 late' "$out"
out=$(RUN_REPORT_PR_LIMIT=4 "$R" "$id" o/r 2>&1)
assert_contains cap-reached-still-lists '#7 late' "$out"
out=$("$R" "$id" o/r 2>&1)
assert_not_contains default-limit-no-warning 'fetch limit' "$out"
assert_contains default-limit-passed "--limit 1000" "$(cat "$MOCK_LOG")"
# Above GitHub's 1000-result ceiling the limit is clamped, so the warning
# still fires and names the ceiling instead of suggesting a higher limit.
jq -n '[range(1000) | {number:(1000+.),title:"o",state:"OPEN",additions:0,deletions:0,mergedAt:null,body:"x"}]' >"$GH_SCENARIO/pr-list.json"
out=$(RUN_REPORT_PR_LIMIT=1001 "$R" "$id" o/r 2>&1)
assert_contains ceiling-warning "gh returned 1000 candidates, the fetch limit; the list may be incomplete — that is GitHub's search ceiling" "$out"
assert_contains ceiling-clamped "--limit 1000" "$(grep '^gh pr list' "$MOCK_LOG" | tail -n1)"
out=$(RUN_REPORT_PR_LIMIT=99999999999999999999 "$R" "$id" o/r 2>&1)
assert_contains huge-clamped "GitHub's search ceiling" "$out"
out=$(RUN_REPORT_PR_LIMIT=3 "$R" "$id" o/r 2>&1)
assert_contains below-ceiling-hint "raise RUN_REPORT_PR_LIMIT (max 1000)" "$out"
for bad in 0 -5 abc 010 ''; do
  RUN_REPORT_PR_LIMIT=$bad "$R" "$id" o/r >/dev/null 2>"$SCRATCH/err"; rc=$?
  if [ -z "$bad" ]; then assert_eq empty-means-default 0 "$rc"; continue; fi
  assert_eq "invalid-limit-$bad" 2 "$rc"
  assert_contains "invalid-limit-$bad-msg" 'RUN_REPORT_PR_LIMIT must be 1-1000' "$(cat "$SCRATCH/err")"
done
# The shared app stubs exercise teardown through the optional transport helper.
out=$(
  . "$TESTS_DIR/../../herdr-delegates/tests/lib.sh"
  app_fixture
  "$R" app-run o/r
)
assert_contains app-teardown $'pa1\tfixture\tidle\t/tmp/own-worktree' "$out"
# Installed without herdr-delegates, the report remains useful and has no raw CLI fallback.
mkdir -p "$SCRATCH/standalone/bin"
cp "$R" "$SCRATCH/standalone/bin/run-report.sh"
out=$("$SCRATCH/standalone/bin/run-report.sh" standalone o/r)
assert_contains standalone-unavailable 'herdr unavailable' "$out"
# Approved failure-path exception does not change a successful TUI read.
out=$(
  . "$TESTS_DIR/../../herdr-delegates/tests/lib.sh"
  echo '{"result":{"panes":[{"pane_id":"w1:p7","agent":"fixture","agent_status":"done","cwd":"/tmp/worktree"}]}}' >"$HERDR_SCENARIO/panes.json"
  "$R" success o/r
  [ "$(grep -c '^herdr pane list$' "$MOCK_LOG")" = 1 ] || exit 1
)
assert_eq tui-success-one-read 0 "$?"
assert_contains tui-success-original-row $'w1:p7\tfixture\tdone\t/tmp/worktree' "$out"
# Gate time: rendered from gates.tsv beside the ledger, never estimated.
export PATH="$MOCK_BIN:$PATH"
printf '[]' >"$GH_SCENARIO/pr-list.json"
mkdir "$SCRATCH/run"; : >"$SCRATCH/run/ledger.md"
out=$("$R" "$id" o/r "$SCRATCH/run/ledger.md" 2>&1)
assert_contains gate-time-absent 'not measured (no gates.tsv beside the ledger' "$out"
out=$("$R" "$id" o/r 2>&1)
assert_contains gate-time-no-ledger 'not measured (no gates.tsv beside the ledger' "$out"
printf '%s\t/wt\t%s\t%s\t%s\t%s\n' \
  t lock heavy 0 40  t gate fmt 0 2  t gate test 1 100 \
  t lock heavy 75 600  t gate test 0 95  t gate fmt 0 3 >"$SCRATCH/run/gates.tsv"
printf 'garbage line\n' >>"$SCRATCH/run/gates.tsv"
out=$("$R" "$id" o/r "$SCRATCH/run/ledger.md" 2>&1)
assert_contains gate-row-fmt '| fmt | 2 | 0 | 5 |' "$out"
assert_contains gate-row-test '| test | 2 | 1 | 195 |' "$out"
assert_contains gate-total '| **all gates** | | | **200** |' "$out"
assert_contains gate-locks 'Lock waits: 2, 640 s in total, 1 not acquired.' "$out"
assert_contains gate-malformed '(1 malformed line(s) skipped)' "$out"
assert_eq gate-order 'fmt test' "$(printf '%s\n' "$out" | grep -o -E '^\| (fmt|test) ' | tr -d '| ' | tr '\n' ' ' | sed 's/ $//')"
# Teardown evidence carries the stale-worktree read and what its exit means.
repo=$(cd "$SCRATCH" && pwd -P)/repo
git init -q -b main "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
git -C "$repo" worktree add -q -b feat/done "$repo-done" main
oid=$(git -C "$repo" rev-parse HEAD)
printf '[{"number":9,"headRefName":"feat/done","headRefOid":"%s","isCrossRepository":false,"title":"t","state":"MERGED","additions":0,"deletions":0,"mergedAt":null,"body":""}]' "$oid" >"$GH_SCENARIO/pr-list.json"
out=$(cd "$repo" && "$R" "$id" o/r 2>&1); rc=$?
assert_eq stale-report-exit 0 "$rc"
assert_contains stale-report-line "STALE $repo-done #9 feat/done" "$out"
assert_contains stale-report-verdict 'exit 3: STALE worktrees remain' "$out"
git -C "$repo" worktree remove "$repo-done"
out=$(cd "$repo" && "$R" "$id" o/r 2>&1)
assert_contains stale-report-clean 'exit 0: no worktree of a merged PR remains' "$out"
out=$(cd "$SCRATCH/run" && "$R" "$id" o/r 2>&1)
assert_contains stale-report-unchecked 'exit 1: not checked' "$out"
finish

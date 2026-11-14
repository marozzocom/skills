#!/usr/bin/env bash
# stale-worktrees.sh classifies linked worktrees against merged PRs and
# never removes one.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export PATH="$MOCK_BIN:$PATH"
S=$BIN_DIR/stale-worktrees.sh
# git prints physical paths (/private/var/... on macOS).
SCRATCH=$(cd "$SCRATCH" && pwd -P)
repo=$SCRATCH/repo
git init -q -b main "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
add() { # <name>: worktree on branch feat/<name> with one commit; prints its HEAD
  git -C "$repo" worktree add -q -b "feat/$1" "$SCRATCH/$1" main
  git -C "$SCRATCH/$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"
  git -C "$SCRATCH/$1" rev-parse HEAD
}
merged=$(add merged); dirty=$(add dirty); busy=$(add busy); moved=$(add moved)
add open >/dev/null; fork=$(add fork); reused=$(add reused)
locked=$(add locked); broken=$(add broken); ignored=$(add ignored)
git -C "$repo" worktree lock --reason 'in use by an agent' "$SCRATCH/locked"
printf 'not an index' >"$(git -C "$SCRATCH/broken" rev-parse --git-dir)/index"
echo secret >"$SCRATCH/ignored/.env"; echo .env >>"$repo/.git/info/exclude"
git -C "$repo" worktree add -q --detach "$SCRATCH/detached" main
: >"$SCRATCH/dirty/untracked"
(cd "$SCRATCH/busy" && exec sleep 30) &
sleeper=$!; sleep 0.3
cat >"$GH_SCENARIO/pr-list.json" <<JSON
[
 {"number":1,"headRefName":"feat/merged","headRefOid":"$merged","isCrossRepository":false},
 {"number":2,"headRefName":"feat/dirty","headRefOid":"$dirty","isCrossRepository":false},
 {"number":3,"headRefName":"feat/busy","headRefOid":"$busy","isCrossRepository":false},
 {"number":4,"headRefName":"feat/moved","headRefOid":"0000000000000000000000000000000000000000","isCrossRepository":false},
 {"number":5,"headRefName":"feat/fork","headRefOid":"$fork","isCrossRepository":true},
 {"number":6,"headRefName":"feat/reused","headRefOid":"1111111111111111111111111111111111111111","isCrossRepository":false},
 {"number":7,"headRefName":"feat/reused","headRefOid":"$reused","isCrossRepository":false},
 {"number":8,"headRefName":"feat/locked","headRefOid":"$locked","isCrossRepository":false},
 {"number":9,"headRefName":"feat/broken","headRefOid":"$broken","isCrossRepository":false},
 {"number":10,"headRefName":"feat/ignored","headRefOid":"$ignored","isCrossRepository":false}
]
JSON
out=$("$S" "$repo" 2>&1); rc=$?
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null
assert_eq stale-exit 3 "$rc"
assert_contains stale-line "STALE $SCRATCH/merged #1 feat/merged" "$out"
assert_contains dirty-line "KEEP $SCRATCH/dirty #2 feat/dirty dirty" "$out"
assert_contains busy-line "KEEP $SCRATCH/busy #3 feat/busy in-use" "$out"
assert_contains moved-line "KEEP $SCRATCH/moved #4 feat/moved head-differs" "$out"
assert_contains reused-picks-matching "STALE $SCRATCH/reused #7 feat/reused" "$out"
assert_contains locked-line "KEEP $SCRATCH/locked #8 feat/locked locked" "$out"
assert_contains status-failed-line "KEEP $SCRATCH/broken #9 feat/broken status-failed" "$out"
# Documented limit: ignored files alone do not keep a tree.
assert_contains ignored-only-stale "STALE $SCRATCH/ignored #10 feat/ignored" "$out"
for quiet in open fork detached repo; do assert_not_contains "silent-$quiet" "$SCRATCH/$quiet " "$out"; done
assert_eq line-count 8 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_contains asks-merged-only '--state merged' "$(cat "$MOCK_LOG")"
# Read-only: every worktree is still there.
assert_eq nothing-removed 12 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"
# No sleeper now: the busy tree is stale too. Default REPO_DIR is the cwd.
out=$(cd "$repo" && "$S" 2>&1)
assert_contains idle-now-stale "STALE $SCRATCH/busy #3 feat/busy" "$out"
# Nothing stale: exit 0, and only the KEEP lines.
git -C "$repo" worktree remove "$SCRATCH/merged"; git -C "$repo" worktree remove "$SCRATCH/busy"
git -C "$repo" worktree remove "$SCRATCH/reused"; git -C "$repo" worktree remove --force "$SCRATCH/ignored"
out=$("$S" "$repo" 2>&1); rc=$?
assert_eq clean-exit 0 "$rc"
assert_not_contains clean-no-stale STALE "$out"
# gh failing, or answering with something that is not a list, is "not checked".
echo 1 >"$GH_SCENARIO/pr-list.exit"
out=$("$S" "$repo" 2>&1); rc=$?
assert_eq gh-failure-exit 1 "$rc"
assert_contains gh-failure-line "UNKNOWN $SCRATCH/dirty feat/dirty" "$out"
rm "$GH_SCENARIO/pr-list.exit"
printf '{"message":"nope"}' >"$GH_SCENARIO/pr-list.json"
out=$("$S" "$repo" 2>&1); rc=$?
assert_eq gh-shape-exit 1 "$rc"
out=$("$S" "$SCRATCH" 2>&1); rc=$?
assert_eq not-a-repo 1 "$rc"
out=$("$S" a b 2>&1); rc=$?
assert_eq usage-exit 2 "$rc"
finish

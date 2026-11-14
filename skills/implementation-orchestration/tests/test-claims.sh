#!/usr/bin/env bash
# Footprint claims: prefix overlap at path boundaries, per repo, release frees.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
C="$BIN_DIR/claims.sh"
export XDG_STATE_HOME="$SCRATCH/state"
out=$("$C" claim run-a owner/repo packages/ui/ convex/schema.ts); assert_eq claim-a-exit 0 $?
assert_contains claim-a-out "claimed run-a" "$out"
out=$("$C" claim run-b owner/repo packages/ui/src/chip.tsx); code=$?
assert_eq nested-file-overlaps 3 "$code"
assert_contains overlap-names-run "run-a packages/ui/ packages/ui/src/chip.tsx" "$out"
"$C" claim run-b owner/repo packages/ui-manifest/ >/dev/null; assert_eq sibling-prefix-is-not-overlap 0 $?
"$C" claim run-c owner/repo convex/schema.tsx >/dev/null; assert_eq similar-file-is-not-overlap 0 $?
"$C" claim run-d other/repo packages/ui/ >/dev/null; assert_eq other-repo-is-independent 0 $?
"$C" check owner/repo ./convex/ >/dev/null; assert_eq check-dir-covers-file 3 $?
"$C" claim run-a owner/repo packages/ui/ >/dev/null; assert_eq reclaim-replaces-own 0 $?
"$C" release run-a >/dev/null
"$C" claim run-e owner/repo packages/ui/src/chip.tsx >/dev/null; assert_eq release-frees 0 $?
assert_not_contains list-after-release "run-a" "$("$C" list)"
finish

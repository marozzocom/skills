#!/usr/bin/env bash
# gh-json.sh: inline JSON, JSON-file path, and everything that is neither.
. "$(dirname "$0")/lib.sh"
. "$BIN_DIR/gh-json.sh"

f="$SCRATCH/x.json"; printf '{"a":1}\n' >"$f"

out=$(gh_json_normalize '{"a":1}'); assert_eq inline-object '{"a":1}' "$out"
out=$(gh_json_normalize '  [1,2]'); assert_eq inline-array-leading-space '  [1,2]' "$out"
out=$(gh_json_normalize "$f"); assert_eq file-path '{"a":1}' "$out"
gh_json_normalize '' >/dev/null; assert_eq empty-is-failure 1 "$?"
gh_json_normalize 'error: not found' >/dev/null; assert_eq prose-is-failure 1 "$?"
gh_json_normalize "$SCRATCH/missing.json" >/dev/null; assert_eq missing-file-is-failure 1 "$?"
gh_json_normalize "$f
$f" >/dev/null; assert_eq multiline-path-is-failure 1 "$?"

# through the mock gh, both modes
printf '{"url":"https://x/pr/1"}\n' >"$GH_SCENARIO/pr-view.json"
echo inline >"$GH_SCENARIO/mode"
out=$(gh_json pr view 1 --json url); assert_eq mock-inline '{"url":"https://x/pr/1"}' "$out"
echo file >"$GH_SCENARIO/mode"
out=$(gh_json pr view 1 --json url); assert_eq mock-file '{"url":"https://x/pr/1"}' "$out"
echo 1 >"$GH_SCENARIO/pr-view.exit"
gh_json pr view 1 --json url >/dev/null; assert_eq mock-file-nonzero-fails 1 "$?"
echo file-quiet >"$GH_SCENARIO/mode"
gh_json pr view 1 --json url >/dev/null; assert_eq mock-quiet-nonzero-fails 1 "$?"

finish

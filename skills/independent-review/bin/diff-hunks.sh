#!/usr/bin/env bash
# diff-hunks.sh <worktree> <base-rev> <file> <start>-<end>|all [...]
# Print the hunks of <file>'s diff against <base-rev> (committed, staged and
# unstaged task changes alike; an untracked file diffs against /dev/null)
# that overlap the given NEW-side line ranges, or the whole file diff for
# `all`. Bounds a scoped review read to what a routing entry names.
# Exit 3 with a diagnostic when nothing matched — an unrepresentable range
# (a deletion, a rename, a mode change) is routed with `all`, never assumed
# reviewed.
set -euo pipefail
usage() { echo "usage: $0 <worktree> <base-rev> <file> <start>-<end>|all [...]" >&2; exit 2; }
[ $# -ge 4 ] || usage
wt=$1; base=$2; file=$3; shift 3
git -C "$wt" rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "diff-hunks: base '$base' is not a commit" >&2; exit 2; }
all=0; ranges=()
for r in "$@"; do
  case $r in
    all) all=1 ;;
    *) [[ $r =~ ^([0-9]+)-([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] || { echo "diff-hunks: bad range '$r' (want <start>-<end> with start<=end, or all)" >&2; exit 2; }
       ranges+=("$r") ;;
  esac
done
if git -C "$wt" ls-files --error-unmatch -- "$file" >/dev/null 2>&1 || git -C "$wt" cat-file -e "$base:$file" 2>/dev/null; then
  patch=$(git -C "$wt" diff -U5 "$base" -- "$file")
else
  patch=$(git -C "$wt" diff -U5 --no-index -- /dev/null "$wt/$file" || true)
fi
[ -n "$patch" ] || { echo "diff-hunks: no diff for '$file' against $base" >&2; exit 3; }
if [ $all = 1 ]; then printf '%s\n' "$patch"; exit 0; fi
out=$(printf '%s\n' "$patch" | awk -v ranges="${ranges[*]}" '
BEGIN { n = split(ranges, r, " "); for (i = 1; i <= n; i++) { split(r[i], b, "-"); lo[i] = b[1] + 0; hi[i] = b[2] + 0 } }
/^diff --git/ { header = $0 "\n"; inhdr = 1; keep = 0; printed_header = 0; next }
inhdr && !/^@@/ { header = header $0 "\n"; next }
/^@@/ {
  inhdr = 0
  match($0, /\+[0-9]+(,[0-9]+)?/); spec = substr($0, RSTART + 1, RLENGTH - 1)
  split(spec, p, ","); start = p[1] + 0; len = (p[2] == "" ? 1 : p[2] + 0); end = start + len - 1
  keep = 0; for (i = 1; i <= n; i++) if (start <= hi[i] && end >= lo[i]) keep = 1
  if (keep && !printed_header) { printf "%s", header; printed_header = 1 }
}
keep { print }
')
[ -n "$out" ] || { echo "diff-hunks: no hunk of '$file' overlaps ${ranges[*]} (new-side lines); a deletion, rename, or mode change is routed with 'all'" >&2; exit 3; }
printf '%s\n' "$out"

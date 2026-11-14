#!/usr/bin/env bash
# claims.sh claim RUN_ID REPO PATH... | check REPO PATH... | release RUN_ID | list
# Cross-run footprint claims, so concurrent runs in one repo do not open
# PRs that collide in CI (design-gate §5 footprint). One shared file:
# ${XDG_STATE_HOME:-~/.local/state}/implementation-orchestration/claims.json.
# PATH is repo-relative: a file or a directory prefix ("packages/ui/",
# "convex/schema.ts"). Two claims overlap when they name the same REPO
# and one path is a prefix of the other at a path boundary.
# claim  records RUN_ID's footprint unless another live run overlaps it;
#        re-claiming by the same RUN_ID replaces its footprint.
# check  reports overlaps without writing.
# Exit: 0 no overlap (claim written), 3 overlap (one line per conflicting
# run: "<run-id> <its path> <your path>"), 1 failure, 2 usage.
set -euo pipefail
usage() { echo "usage: claims.sh claim RUN_ID REPO PATH... | check REPO PATH... | release RUN_ID | list" >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -ge 1 ] || usage
dir=${XDG_STATE_HOME:-$HOME/.local/state}/implementation-orchestration
file=$dir/claims.json lock=$dir/claims.lock
mkdir -p "$dir"
[ -f "$file" ] || echo '{}' >"$file"
for _ in $(seq 1 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
[ -d "$lock" ] || fail "claims lock busy: $lock"
trap 'rmdir "$lock"' EXIT

overlaps() { # $1 run-id to ignore, $2 repo, rest paths -> conflict lines
  local self=$1 repo=$2; shift 2
  jq -r --arg self "$self" --arg repo "$repo" '
    def norm: sub("^\\./"; "");
    def hit($a; $b): ($a|norm) as $x | ($b|norm) as $y
      | $x == $y
        or ($x | endswith("/")) and ($y | startswith($x))
        or ($y | endswith("/")) and ($x | startswith($y));
    to_entries[] | select(.key != $self and .value.repo == $repo)
    | .key as $run | .value.paths[] as $theirs
    | $ARGS.positional[] as $mine | select(hit($theirs; $mine))
    | "\($run) \($theirs) \($mine)"' --args "$@" <"$file"
}

cmd=$1; shift
case $cmd in
  claim)
    [ $# -ge 3 ] || usage
    run=$1 repo=$2; shift 2
    hits=$(overlaps "$run" "$repo" "$@")
    if [ -n "$hits" ]; then echo "$hits"; exit 3; fi
    tmp=$(mktemp "$dir/claims.XXXXXX")
    jq --arg run "$run" --arg repo "$repo" --arg at "$(date -u +%FT%TZ)" \
      '.[$run] = {repo: $repo, paths: $ARGS.positional, at: $at}' --args "$@" <"$file" >"$tmp"
    mv "$tmp" "$file"
    echo "claimed $run: $*" ;;
  check)
    [ $# -ge 2 ] || usage
    repo=$1; shift
    hits=$(overlaps "" "$repo" "$@")
    if [ -n "$hits" ]; then echo "$hits"; exit 3; fi
    echo "no overlap" ;;
  release)
    [ $# -eq 1 ] || usage
    tmp=$(mktemp "$dir/claims.XXXXXX")
    jq --arg run "$1" 'del(.[$run])' "$file" >"$tmp"
    mv "$tmp" "$file"
    echo "released $1" ;;
  list)
    jq -r 'to_entries[] | "\(.key) \(.value.repo) \(.value.at) \(.value.paths | join(" "))"' "$file" ;;
  *) usage ;;
esac

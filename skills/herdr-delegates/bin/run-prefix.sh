#!/usr/bin/env bash
# run-prefix.sh <run-slug>
#
# Prints the run's agent-name prefix (SKILL.md §Communication mesh): the
# slug lowercased, anything outside [a-z0-9] folded to single dashes, cut
# to 12 characters. Herdr agent names are global across workspaces, so a
# prefix is taken when any live agent is named exactly it or starts with
# "<prefix>-"; the script then appends -2, -3, ... until one is free.
# Every agent of the run is named <prefix>-<role>: <prefix>-overseer,
# <prefix>-impl, <prefix>-review, <prefix>-oracle, ...
# Exit: 0 printed a prefix, 1 herdr unavailable, 2 usage.
set -u

slug=${1:-}
[ -n "$slug" ] || { echo "usage: run-prefix.sh <run-slug>" >&2; exit 2; }

base=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' |
  sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' | cut -c1-12 | sed -e 's/-$//')
[ -n "$base" ] || { echo "usage: run-slug '$slug' has no letters or digits" >&2; exit 2; }

list=$(herdr agent list 2>/dev/null) && [ -n "$list" ] ||
  { echo "ERROR: herdr agent list failed — not in a Herdr session?" >&2; exit 1; }
names=$(printf '%s' "$list" | jq -r '.result.agents[].name // empty') ||
  { echo "ERROR: unreadable herdr agent list" >&2; exit 1; }

taken() {
  printf '%s\n' "$names" | grep -q -x -e "$1" -e "$1-.*"
}

prefix=$base
n=1
while taken "$prefix"; do
  n=$((n + 1))
  prefix="$base-$n"
done
echo "$prefix"

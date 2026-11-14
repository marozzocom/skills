#!/usr/bin/env bash
# park-idea.sh PRODUCT TITLE BODY [--tag TAG]... [--dry-run]
# Files one parked idea as a card on PRODUCT's ideas board
# (phase-landing.md §Complete deliverables). Boards come from
# ${XDG_CONFIG_HOME:-~/.config}/implementation-orchestration/ideas-boards.json:
#   { "<product>": { "url": "<create endpoint>", "boardId": "<id>",
#                    "tokenCmd": "<command printing a bearer token>",
#                    "tags": ["idea"] } }
# The token goes from tokenCmd straight into the request header and is
# never printed. The card's idempotency key is derived from PRODUCT and
# TITLE, so re-parking the same idea returns the existing card.
# Exit: 0 prints "parked <card id> on <product>" (or the dry-run body),
# 1 request or config failure, 2 usage.
set -euo pipefail
usage() { echo "usage: park-idea.sh PRODUCT TITLE BODY [--tag TAG]... [--dry-run]" >&2; exit 2; }
fail() { echo "ERROR: $*" >&2; exit 1; }
[ $# -ge 3 ] || usage
product=$1 title=$2 body=$3; shift 3
tags=() dry=0
while [ $# -gt 0 ]; do
  case $1 in
    --tag) [ $# -ge 2 ] || usage; tags+=("$2"); shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$title" ] && [ -n "$body" ] || usage
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/implementation-orchestration/ideas-boards.json
[ -f "$cfg" ] || fail "no ideas-board config at $cfg"
entry=$(jq -ec --arg p "$product" '.[$p] // empty' "$cfg") || fail "no ideas board configured for '$product' in $cfg"
url=$(jq -er .url <<<"$entry") || fail "'$product' has no url"
board=$(jq -er .boardId <<<"$entry") || fail "'$product' has no boardId"
token_cmd=$(jq -er .tokenCmd <<<"$entry") || fail "'$product' has no tokenCmd"
key="park-$(printf '%s\n%s' "$product" "$title" | shasum -a 256 | cut -c1-32)"
extra=$(printf '%s\n' ${tags[@]+"${tags[@]}"} | jq -R 'select(length > 0)' | jq -s .)
payload=$(jq -n --arg t "$title" --arg b "$body" --arg board "$board" --arg k "$key" \
  --argjson base "$(jq -c '.tags // ["idea"]' <<<"$entry")" --argjson extra "$extra" \
  '{title: $t, body: $b, boardId: $board, status: "todo", tags: ($base + $extra | unique), idempotencyKey: $k}')
if [ "$dry" = 1 ]; then jq . <<<"$payload"; exit 0; fi
token=$(bash -c "$token_cmd") || fail "tokenCmd failed for '$product'"
[ -n "$token" ] || fail "tokenCmd printed nothing for '$product'"
resp=$(printf 'Authorization: Bearer %s\n' "$token" | curl -sS -X POST "$url" -H @- \
  -H "Content-Type: application/json" --data-binary "$payload" -w '\n%{http_code}') || fail "request failed"
code=${resp##*$'\n'}; json=${resp%$'\n'*}
[ "$code" -ge 200 ] && [ "$code" -lt 300 ] || fail "HTTP $code: $(jq -c '{error, code}' <<<"$json" 2>/dev/null || echo "$json" | head -c 300)"
id=$(jq -er '.data.id' <<<"$json") || fail "response has no data.id"
echo "parked $id on $product"

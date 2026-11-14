#!/usr/bin/env bash
# park-idea: config lookup, payload shape, stable idempotency key, no token in output.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
P="$BIN_DIR/park-idea.sh"
export XDG_CONFIG_HOME="$SCRATCH/cfg"
mkdir -p "$XDG_CONFIG_HOME/implementation-orchestration"
cat >"$XDG_CONFIG_HOME/implementation-orchestration/ideas-boards.json" <<'J'
{ "furnace": { "url": "http://127.0.0.1:9/none", "boardId": "board-1",
  "tokenCmd": "echo secret-token", "tags": ["idea", "agent"] } }
J
"$P" tide "T" "B" --dry-run >/dev/null 2>&1; assert_eq unknown-product-fails 1 $?
one=$("$P" furnace "Chip ellipsis" "Origin: x.ts:1" --tag ui --dry-run)
assert_eq board "board-1" "$(jq -r .boardId <<<"$one")"
assert_eq status todo "$(jq -r .status <<<"$one")"
assert_eq tags '["agent","idea","ui"]' "$(jq -c .tags <<<"$one")"
two=$("$P" furnace "Chip ellipsis" "other body" --dry-run)
assert_eq stable-key "$(jq -r .idempotencyKey <<<"$one")" "$(jq -r .idempotencyKey <<<"$two")"
three=$("$P" furnace "Another" "B" --dry-run)
[ "$(jq -r .idempotencyKey <<<"$one")" != "$(jq -r .idempotencyKey <<<"$three")" ]; assert_eq distinct-key 0 $?
err=$("$P" furnace "T" "B" 2>&1); assert_eq unreachable-fails 1 $?
assert_not_contains token-not-printed "secret-token" "$err"
finish

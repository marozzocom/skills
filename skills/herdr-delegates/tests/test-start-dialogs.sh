#!/usr/bin/env bash
# herdr-backend.sh TUI start/rotate against startup dialogs: classification,
# safe naming, the folder-trust allowlist and its refusals, banner dismissal,
# exit 4 reporting, and rotate's no-retry rule. SD_CASE selects one group.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
H=$BIN_DIR/herdr-backend.sh

# A herdr whose agent list is a file. agent start follows $S/start.mode:
#   ok | not_ready_stderr (herdr 0.9.5: exit 1, empty stdout, JSON on stderr)
#   | not_ready_stdout (older shape) | timeout | busy | other | fail_once
# and adds $S/start-agent.json (pane_id and, unless the file sets one, name
# filled in) except for busy/other/fail_once or when $S/no-agent exists; ok
# seeds it idle. send-keys call N logs its keys to keys.log and applies
# on-keys-N.txt (screen) and on-keys-N.status (idle/done without a screen
# file clears the screen) and arms on-keys-N.next-after (see below).
# Delayed change: while $S/next-after holds N, the Nth agent get applies
# next.txt and next.status. rename-fail refuses every rename; get-null makes
# agent get answer {"result":{"agent":null}}.
cat >"$MOCK_BIN/herdr" <<'MOCK'
#!/usr/bin/env bash
set -u
S=${HERDR_SCENARIO:?}
printf 'herdr %s\n' "$*" >>"${MOCK_LOG:?}"
edit() { jq "$@" "$S/agents.json" >"$S/agents.tmp" && mv "$S/agents.tmp" "$S/agents.json"; }
case "$1 $2" in
  "agent list") cat "$S/agents.json" ;;
  "agent get")
    if [ -f "$S/next-after" ]; then
      n=$(($(cat "$S/next-after") - 1)); echo "$n" >"$S/next-after"
      if [ "$n" -le 0 ]; then
        rm "$S/next-after"; [ ! -f "$S/next.txt" ] || mv "$S/next.txt" "$S/pane.txt"
        [ ! -f "$S/next.status" ] || { edit --arg s "$(cat "$S/next.status")" '.result.agents |= map(.agent_status = $s)'; rm "$S/next.status"; }
      fi
    fi
    if [ -f "$S/get-null" ]; then echo '{"result":{"agent":null}}'; exit 0; fi
    a=$(jq -ce --arg p "$3" '[.result.agents[]|select(.pane_id==$p or .name==$p)][0] // empty' "$S/agents.json")
    if [ -z "$a" ]; then echo '{"error":{"code":"agent_not_found","message":"no agent"}}' >&2; exit 1; fi
    jq -cn --argjson a "$a" '{result:{agent:$a}}' ;;
  "agent start")
    name=$3; pane=''; shift 3
    while [ $# -gt 0 ]; do case $1 in --pane) pane=$2; shift 2 ;; --) break ;; *) shift ;; esac; done
    mode=$(cat "$S/start.mode")
    if [ "$mode" = fail_once ]; then
      if [ ! -f "$S/failed-once" ]; then touch "$S/failed-once"; echo '{"error":{"code":"agent_pane_busy"}}'; exit 1; fi
      mode=ok
    fi
    case $mode in busy) echo '{"error":{"code":"agent_pane_busy","message":"busy"}}'; exit 1 ;;
      other) echo '{"error":{"code":"agent_spawn_failed","message":"no"}}' >&2; exit 1 ;; esac
    if [ -f "$S/no-agent" ]; then :
    elif [ -f "$S/start-agent.json" ]; then
      edit --arg n "$name" --arg p "$pane" --slurpfile a "$S/start-agent.json" \
        '.result.agents += [{name:$n} + $a[0] + {pane_id:$p}]'
    else
      edit --arg n "$name" --arg p "$pane" '.result.agents += [{name:$n,pane_id:$p,agent:"fixture",agent_status:"idle"}]'
    fi
    [ "$mode" != ok ] || edit --arg p "$pane" '.result.agents |= map(if .pane_id == $p then .agent_status = "idle" else . end)'
    case $mode in
      ok) jq -cn --arg p "$pane" '{result:{agent:{pane_id:$p,agent_status:"idle"}}}' ;;
      not_ready_stderr) printf '{"error":{"code":"agent_not_ready","message":"agent %s is blocked during startup and is not ready for prompts"},"id":"cli:agent:start"}\n' "$name" >&2; exit 1 ;;
      not_ready_stdout) printf '{"error":{"code":"agent_not_ready","message":"blocked"}}\n'; exit 1 ;;
      timeout) echo '{"error":{"code":"timeout","message":"timed out"}}' >&2; exit 1 ;;
    esac ;;
  "agent rename")
    [ ! -f "$S/rename-fail" ] || { echo '{"error":{"code":"agent_name_taken"}}' >&2; exit 1; }
    edit --arg p "$3" --arg n "$4" '.result.agents |= map(if .pane_id == $p then .name = $n else . end)'; echo '{}' ;;
  "agent read"|"pane read")
    lines=''; while [ $# -gt 0 ]; do [ "$1" != --lines ] || lines=$2; shift; done
    [ -n "$lines" ] || { echo "UNBOUNDED read" >>"$MOCK_LOG"; exit 1; }
    [ -f "$S/pane.txt" ] || exit 1
    tail -n "$lines" "$S/pane.txt" ;;
  "agent send-keys")
    shift 3; echo "$*" >>"$S/keys.log"; n=$(wc -l <"$S/keys.log" | tr -d ' ')
    [ ! -f "$S/on-keys-$n.txt" ] || cp "$S/on-keys-$n.txt" "$S/pane.txt"
    if [ -f "$S/on-keys-$n.status" ]; then
      st=$(cat "$S/on-keys-$n.status")
      edit --arg s "$st" '.result.agents |= map(.agent_status = $s)'
      case $st in idle|done) [ -f "$S/on-keys-$n.txt" ] || echo 'Ready for input' >"$S/pane.txt" ;; esac
    fi
    for f in next-after next.txt next.status; do [ ! -f "$S/on-keys-$n.$f" ] || cp "$S/on-keys-$n.$f" "$S/$f"; done
    echo '{}' ;;
  "pane get") cat "$S/pane-get.json" ;;
  "pane run") echo '{}' ;;
  *) echo "mock herdr: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/herdr"

S=$HERDR_SCENARIO
mkdir -p "$SCRATCH/wt" "$SCRATCH/roots/child" "$SCRATCH/roots-evil" "$SCRATCH/other"
WT=$(cd "$SCRATCH/wt" && pwd -P)
export XDG_CONFIG_HOME=$SCRATCH/xdg
ROOTS=$XDG_CONFIG_HOME/implementation-orchestration/trust-roots
RUN=$SCRATCH/run
layout1() { # PATH
  printf 'Accessing workspace:\n\n%s\n\nDo you trust the contents of this project?\nOnly trust folders you know.\n\n> Yes, I trust this folder\n  No, exit\n' "$1"
}
layout2() { # PATH
  printf ' Accessing workspace:\n\n %s\n\n Quick safety check: Is this a project you created or one you trust?\n\n \033[36m\342\235\257 No, exit\033[0m\n   Yes, I trust this folder\n' "$1"
}
banner() { printf '\033[1mWhat'"'"'s new\033[0m\n A new model is available.\n Press Esc to dismiss\n'; }
# reset CASE MODE CWD: an empty pane w1:p3 whose shell sits in CWD, a fresh
# run dir, no allowlist, no keys yet. The agent appears as blocked.
reset() {
  case_name=$1
  rm -rf "${S:?}"/* "$RUN" "$XDG_CONFIG_HOME"
  mkdir -p "$RUN"
  echo '{"result":{"agents":[]}}' >"$S/agents.json"
  echo "$2" >"$S/start.mode"
  jq -n --arg c "$3" '{agent:"fixture",agent_status:"blocked",foreground_cwd:$c,cwd:"/somewhere/else"}' >"$S/start-agent.json"
  jq -n --arg c "$3" '{result:{pane:{foreground_cwd:$c,cwd:$c}}}' >"$S/pane-get.json"
  : >"$S/keys.log"; : >"$MOCK_LOG"
}
allow() { # ROOT [MODE]
  mkdir -p "${ROOTS%/*}"; printf '# trusted roots\n%s\n' "$1" >"$ROOTS"; chmod "${2:-600}" "$ROOTS"
}
start() { # run start for fixture-impl into w1:p3; sets rc, out, err
  out=$(HERDR_BACKEND_RUN_DIR=$RUN "$H" start fixture-impl fixture /tmp/example-worktree --pane w1:p3 --timeout 5 -- --pin x 2>"$SCRATCH/err")
  rc=$?; err=$(cat "$SCRATCH/err")
}
keys() { tr '\n' '|' <"$S/keys.log"; }
blocked_case() { # LABEL REASON — exit 4, empty stdout, zero keys, the reason
  assert_eq "$case_name-$1-exit" 4 "$rc"
  assert_eq "$case_name-$1-stdout" '' "$out"
  assert_eq "$case_name-$1-no-keys" '' "$(keys)"
  assert_contains "$case_name-$1-reason" "$2" "$err"
}
group() { [ -z "${SD_CASE:-}" ] || [ "$SD_CASE" = "$1" ]; }

if group no-allowlist; then
  for mode in not_ready_stderr not_ready_stdout; do
    reset "no-allowlist-$mode" "$mode" "$WT"; layout1 "$WT" >"$S/pane.txt"
    start
    blocked_case refused 'no allowlist'
    assert_contains "$case_name-diagnostic" "start: dialog=folder_trust agent=fixture-impl pane=w1:p3 cwd=$WT action=none" "$err"
    assert_not_contains "$case_name-no-tui-cwd" /tmp/example-worktree "$err"
    assert_contains "$case_name-tail" '  | > Yes, I trust this folder' "$err"
    assert_not_contains "$case_name-no-unbounded" UNBOUNDED "$(cat "$MOCK_LOG")"
    drop=$(ls "$RUN/inbox/new")
    assert_eq "$case_name-one-drop" 1 "$(printf '%s\n' "$drop" | grep -c '^fixture-impl--start-dialog-.*\.md$')"
    assert_eq "$case_name-drop-kind" 'kind: blocker' "$(head -n 1 "$RUN/inbox/new/$drop")"
    assert_contains "$case_name-drop-body" 'folder_trust' "$(cat "$RUN/inbox/new/$drop")"
  done
  # No run dir: no drop, same exit.
  reset no-run not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"
  "$H" start fixture-impl fixture "$WT" --pane w1:p3 --timeout 5 -- >/dev/null 2>&1
  assert_eq no-run-exit 4 "$?"
  assert_eq no-run-no-inbox false "$([ -d "$RUN/inbox" ] && echo true || echo false)"
fi

if group allowlisted; then
  reset layout1 not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq layout1-exit 0 "$rc"; assert_eq layout1-pane w1:p3 "$out"; assert_eq layout1-keys 'enter|' "$(keys)"
  reset layout2 not_ready_stderr "$WT"; layout2 "$WT" >"$S/pane.txt"; allow "$WT"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq layout2-exit 0 "$rc"; assert_eq layout2-pane w1:p3 "$out"; assert_eq layout2-keys 'down enter|' "$(keys)"
  # A cwd strictly inside a root is trusted; the dialog prints the same path.
  inner=$(cd "$SCRATCH/roots/child" && pwd -P)
  reset inside-root not_ready_stderr "$inner"; layout1 "$inner" >"$S/pane.txt"; allow "$SCRATCH/roots"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq inside-root-exit 0 "$rc"; assert_eq inside-root-keys 'enter|' "$(keys)"
  # Trust, then a banner: both cleared in order.
  reset trust-banner not_ready_stderr "$WT"; layout2 "$WT" >"$S/pane.txt"; allow "$WT"
  banner >"$S/on-keys-1.txt"; echo idle >"$S/on-keys-2.status"
  start
  assert_eq trust-banner-exit 0 "$rc"; assert_eq trust-banner-keys 'down enter|esc|' "$(keys)"
  # A third dialog is never handled: two transitions at most.
  reset bounded not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT"
  banner >"$S/on-keys-1.txt"; printf 'Press Esc to close\nAnother notice\n' >"$S/on-keys-2.txt"
  start
  assert_eq bounded-exit 4 "$rc"; assert_eq bounded-keys 'enter|esc|' "$(keys)"
  assert_contains bounded-reason 'two dialog transitions' "$err"
  assert_contains bounded-action 'action=sent:esc' "$err"
fi

if group refusals; then
  for mode in 620 602; do
    reset "mode-$mode" not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT" "$mode"
    start; blocked_case refused 'group- or world-writable'
  done
  reset symlink not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT"
  mv "$ROOTS" "$SCRATCH/real-roots"; ln -s "$SCRATCH/real-roots" "$ROOTS"
  start; blocked_case refused 'is a symlink'
  evil=$(cd "$SCRATCH/roots-evil" && pwd -P)
  reset sibling not_ready_stderr "$evil"; layout1 "$evil" >"$S/pane.txt"; allow "$SCRATCH/roots"
  start; blocked_case refused 'is not under a root'
  other=$(cd "$SCRATCH/other" && pwd -P)
  reset printed-mismatch not_ready_stderr "$WT"; layout1 "$other" >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused "dialog workspace $other is not the pane cwd $WT"
  reset printed-missing not_ready_stderr "$WT"; layout1 /tmp/example-worktree-gone >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused 'cannot be resolved'
  reset unknown-choice not_ready_stderr "$WT"; layout1 "$WT" | sed 's/> Yes, I trust this folder/> Yes, and remember everything/' >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused 'not recognized'
  reset two-marks not_ready_stderr "$WT"; { layout1 "$WT"; echo '> '; } >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused '2 highlighted choices'
  reset no-exit-unpaired not_ready_stderr "$WT"; layout2 "$WT" | sed 's/Yes, I trust this folder/Cancel/' >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused "highlighted choice 'No, exit' not recognized"
  # A directory in the allowlist's place is not a regular file.
  reset not-a-file not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; mkdir -p "$ROOTS"
  start; blocked_case refused 'no allowlist'
fi

if group other-dialogs; then
  reset banner not_ready_stderr "$WT"; banner >"$S/pane.txt"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq banner-exit 0 "$rc"; assert_eq banner-pane w1:p3 "$out"; assert_eq banner-keys 'esc|' "$(keys)"
  # A dialog that ignores its key gets no second one.
  reset banner-stuck not_ready_stderr "$WT"; banner >"$S/pane.txt"
  start
  assert_eq banner-stuck-exit 4 "$rc"; assert_eq banner-stuck-keys 'esc|' "$(keys)"
  assert_contains banner-stuck-reason 'nothing more sent' "$err"
  # An agent already ready after the failed start gets no key at all.
  reset self-cleared not_ready_stderr "$WT"; jq '.agent_status="idle"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  banner >"$S/pane.txt"; start
  assert_eq self-cleared-exit 0 "$rc"; assert_eq self-cleared-pane w1:p3 "$out"; assert_eq self-cleared-no-keys '' "$(keys)"
  reset banner-with-approval not_ready_stderr "$WT"; printf 'Allow this tool permission?\nPress Esc to dismiss\n' >"$S/pane.txt"
  start; blocked_case refused 'unrecognized startup dialog'
  assert_contains banner-with-approval-class 'dialog=unknown_dialog' "$err"
  reset update not_ready_stderr "$WT"; printf 'Update available: 2.0\n> Update now\n  Skip\n' >"$S/pane.txt"
  start; blocked_case refused 'update prompt'
  assert_contains update-class 'dialog=update_prompt' "$err"
  reset unknown not_ready_stderr "$WT"; printf 'Choose a theme\n> Dark\n  Light\n' >"$S/pane.txt"
  start; blocked_case refused 'unrecognized startup dialog'
  assert_contains unknown-class 'dialog=unknown_dialog' "$err"
fi

if group adoption; then
  # A timed-out, unnamed agent of the same kind is named, then its dialog is reported.
  reset adopt timeout "$WT"; jq '.name=""' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  printf 'Choose a theme\n> Dark\n' >"$S/pane.txt"
  start
  assert_eq adopt-exit 4 "$rc"
  assert_contains adopt-renamed 'herdr agent rename w1:p3 fixture-impl' "$(cat "$MOCK_LOG")"
  assert_eq adopt-named fixture-impl "$(jq -r '.result.agents[0].name' "$S/agents.json")"
  # Never rename a pane that already holds an agent: refused before start.
  reset occupied ok "$WT"
  echo '{"result":{"agents":[{"name":"","pane_id":"w1:p3","agent":"fixture","agent_status":"idle"}]}}' >"$S/agents.json"
  start
  assert_eq occupied-exit 1 "$rc"; assert_contains occupied-msg 'already holds an agent' "$err"
  assert_eq occupied-no-start-rename 0 "$(grep -cE 'agent (start|rename)' "$MOCK_LOG")"
  # A different name or kind showing up after a failure is never renamed or keyed.
  reset foreign-name not_ready_stderr "$WT"; jq '.name="someone-else"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  banner >"$S/pane.txt"; start
  assert_eq foreign-name-exit 1 "$rc"; assert_eq foreign-name-no-rename 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
  assert_eq foreign-name-no-keys '' "$(keys)"
  reset foreign-kind timeout "$WT"; jq '.name="" | .agent="other"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  banner >"$S/pane.txt"; start
  assert_eq foreign-kind-exit 1 "$rc"; assert_eq foreign-kind-no-rename 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
  assert_eq foreign-kind-no-keys '' "$(keys)"
  # Busy, another error code, or no agent in the pane: a plain failure.
  reset busy busy "$WT"; banner >"$S/pane.txt"; start
  assert_eq busy-exit 1 "$rc"; assert_eq busy-stdout '' "$out"; assert_contains busy-err agent_pane_busy "$err"
  reset other other "$WT"; banner >"$S/pane.txt"; start
  assert_eq other-exit 1 "$rc"; assert_eq other-no-keys '' "$(keys)"
  reset no-agent not_ready_stderr "$WT"; touch "$S/no-agent"; banner >"$S/pane.txt"; start
  assert_eq no-agent-exit 1 "$rc"; assert_eq no-agent-no-keys '' "$(keys)"
  assert_eq no-agent-no-rename 0 "$(grep -c 'agent rename' "$MOCK_LOG")"
fi

if group success-path; then
  reset ok-trust-refused ok "$WT"; layout1 "$WT" >"$S/pane.txt"
  start; blocked_case refused 'no allowlist'
  reset ok-trust-allowed ok "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq ok-trust-allowed-exit 0 "$rc"; assert_eq ok-trust-allowed-pane w1:p3 "$out"; assert_eq ok-trust-allowed-keys 'enter|' "$(keys)"
  reset ok-update ok "$WT"; printf 'Update available: 2.0 (run the updater)\n' >"$S/pane.txt"
  start
  assert_eq ok-update-exit 0 "$rc"; assert_eq ok-update-pane w1:p3 "$out"
  assert_contains ok-update-warning 'warning: fixture-impl shows an update notice' "$err"
  reset ok-banner ok "$WT"; banner >"$S/pane.txt"
  start; assert_eq ok-banner-exit 0 "$rc"; assert_eq ok-banner-no-keys '' "$(keys)"
  reset ok-unreadable ok "$WT"
  start; assert_eq ok-unreadable-exit 0 "$rc"; assert_eq ok-unreadable-pane w1:p3 "$out"; assert_eq ok-unreadable-err '' "$err"
fi

if group rotate; then
  rotate() { out=$(HERDR_BACKEND_RUN_DIR=$RUN "$H" rotate fixture-impl w1:p3 "$WT" fixture -- --pin x 2>"$SCRATCH/err"); rc=$?; err=$(cat "$SCRATCH/err"); }
  reset rotate-dialog not_ready_stderr "$WT"; printf 'Choose a theme\n> Dark\n' >"$S/pane.txt"
  rotate
  assert_eq rotate-dialog-exit 4 "$rc"; assert_eq rotate-dialog-stdout '' "$out"
  assert_eq rotate-dialog-one-start 1 "$(grep -c 'agent start' "$MOCK_LOG")"
  reset rotate-retry fail_once "$WT"; rm "$S/start-agent.json"
  rotate
  assert_eq rotate-retry-exit 0 "$rc"
  assert_eq rotate-retry-one-json 1 "$(jq -s length <<<"$out")"
  assert_eq rotate-retry-pane w1:p3 "$(jq -r .result.agent.pane_id <<<"$out")"
  assert_eq rotate-retry-two-starts 2 "$(grep -c 'agent start' "$MOCK_LOG")"
  reset rotate-trust not_ready_stderr "$WT"; layout2 "$WT" >"$S/pane.txt"; allow "$WT"; echo idle >"$S/on-keys-1.status"
  rotate
  assert_eq rotate-trust-exit 0 "$rc"; assert_eq rotate-trust-pane w1:p3 "$(jq -r .result.agent.pane_id <<<"$out")"
  assert_eq rotate-trust-keys 'down enter|' "$(keys)"
fi
if group fix1-paths; then
  other=$(cd "$SCRATCH/other" && pwd -P)
  # A cwd that only lexically sits under a root ("missing/.." components) never passes.
  sneaky=$WT/missing/../../other
  reset dotdot not_ready_stderr "$sneaky"; layout1 "$sneaky" >"$S/pane.txt"; allow "$WT"
  start; blocked_case refused "cwd $sneaky cannot be resolved"
  # A relative workspace path in the dialog is never resolved against the caller's cwd.
  reset relative-shown not_ready_stderr "$WT"; layout1 wt >"$S/pane.txt"; allow "$WT"
  out=$(cd "$SCRATCH" && HERDR_BACKEND_RUN_DIR=$RUN "$H" start fixture-impl fixture /tmp/example-worktree --pane w1:p3 --timeout 5 -- 2>"$SCRATCH/err"); rc=$?; err=$(cat "$SCRATCH/err")
  blocked_case refused 'dialog workspace wt is not an absolute path'
  # Without the workspace header, every path line still has to be the pane cwd.
  reset no-header-mismatch not_ready_stderr "$WT"; allow "$WT"
  printf 'Do you trust the files in this folder?\n%s\n\n> Yes, proceed\n  No, exit\n' "$other" >"$S/pane.txt"
  start; blocked_case refused "dialog workspace $other is not the pane cwd $WT"
  reset no-header-match not_ready_stderr "$WT"; allow "$WT"
  printf 'Do you trust the files in this folder?\n%s\n\n> Yes, proceed\n  No, exit\n' "$WT" >"$S/pane.txt"; echo idle >"$S/on-keys-1.status"
  start; assert_eq no-header-match-exit 0 "$rc"; assert_eq no-header-match-keys 'enter|' "$(keys)"
  reset two-headers not_ready_stderr "$WT"; allow "$WT"
  { printf 'Accessing workspace:\n%s\n' "$other"; layout1 "$WT"; } >"$S/pane.txt"
  start; blocked_case refused "dialog workspace $other is not the pane cwd"
  reset header-no-path not_ready_stderr "$WT"; allow "$WT"
  printf 'Do you trust the contents of this project?\n> Yes, I trust this folder\n  No, exit\nAccessing workspace:\n\n' >"$S/pane.txt"
  start; blocked_case refused 'no path follows'
  # A relative XDG_CONFIG_HOME (here one that find would read as an option) is refused.
  reset xdg-dash not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"
  mkdir -p "$SCRATCH/-xdg/implementation-orchestration"; printf '%s\n' "$WT" >"$SCRATCH/-xdg/implementation-orchestration/trust-roots"
  chmod 666 "$SCRATCH/-xdg/implementation-orchestration/trust-roots"
  out=$(cd "$SCRATCH" && XDG_CONFIG_HOME=-xdg HERDR_BACKEND_RUN_DIR=$RUN "$H" start fixture-impl fixture /tmp/x --pane w1:p3 --timeout 5 -- 2>"$SCRATCH/err"); rc=$?; err=$(cat "$SCRATCH/err")
  blocked_case refused 'XDG_CONFIG_HOME must be an absolute path'
  # A permission check that cannot run fails closed (find is wrapped to fail).
  real_find=$(command -v find)
  # shellcheck disable=SC2016 # the wrapper expands these itself
  printf '#!/bin/sh\n[ -z "${FIND_FAIL:-}" ] || exit 1\nexec %s "$@"\n' "$real_find" >"$MOCK_BIN/find"; chmod +x "$MOCK_BIN/find"
  reset find-fails not_ready_stderr "$WT"; layout1 "$WT" >"$S/pane.txt"; allow "$WT" 666
  out=$(FIND_FAIL=1 HERDR_BACKEND_RUN_DIR=$RUN "$H" start fixture-impl fixture /tmp/x --pane w1:p3 --timeout 5 -- 2>"$SCRATCH/err"); rc=$?; err=$(cat "$SCRATCH/err")
  blocked_case refused 'could not check allowlist permissions'
  rm "$MOCK_BIN/find"
  # Allowlist entries: surrounding spaces, a space inside, a trailing slash, /, a symlinked root.
  mkdir -p "$SCRATCH/with space/wt"; spaced=$(cd "$SCRATCH/with space/wt" && pwd -P)
  ln -s "$WT" "$SCRATCH/link-to-wt"
  i=0
  for entry in "   $WT   " "$SCRATCH/with space" "$WT/" / "$SCRATCH/link-to-wt"; do
    cwd=$WT; [ "$entry" != "$SCRATCH/with space" ] || cwd=$spaced
    i=$((i + 1)); reset "root-entry-$i" not_ready_stderr "$cwd"; layout1 "$cwd" >"$S/pane.txt"
    allow "$entry"; echo idle >"$S/on-keys-1.status"
    start; assert_eq "$case_name-exit" 0 "$rc"; assert_eq "$case_name-keys" 'enter|' "$(keys)"
  done
  # foreground_cwd wins over the agent's launch cwd, wherever it is reported.
  reset fg-precedence not_ready_stderr "$WT"; allow "$WT"; layout1 "$WT" >"$S/pane.txt"; echo idle >"$S/on-keys-1.status"
  jq --arg o "$other" 'del(.foreground_cwd) | .cwd = $o' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  start; assert_eq fg-precedence-exit 0 "$rc"; assert_eq fg-precedence-keys 'enter|' "$(keys)"
  # An empty agent object from agent get falls through to the agent list.
  reset get-null not_ready_stderr "$WT"; allow "$WT"; layout1 "$WT" >"$S/pane.txt"; echo idle >"$S/on-keys-1.status"; touch "$S/get-null"
  start; assert_eq get-null-exit 0 "$rc"; assert_eq get-null-keys 'enter|' "$(keys)"
fi

if group fix1-timing; then
  # After the keys, a loading frame is waited out, not reported.
  reset loading-after-keys not_ready_stderr "$WT"; allow "$WT"; layout1 "$WT" >"$S/pane.txt"
  echo 'Loading workspace...' >"$S/on-keys-1.txt"; echo blocked >"$S/on-keys-1.status"
  echo 2 >"$S/on-keys-1.next-after"; echo 'Ready for input' >"$S/on-keys-1.next.txt"; echo idle >"$S/on-keys-1.next.status"
  start; assert_eq loading-after-keys-exit 0 "$rc"; assert_eq loading-after-keys-pane w1:p3 "$out"; assert_eq loading-after-keys-keys 'enter|' "$(keys)"
  # Loading frames between dialogs are not transitions: trust, loading, banner, loading, ready.
  reset loading-between not_ready_stderr "$WT"; allow "$WT"; layout1 "$WT" >"$S/pane.txt"
  for n in 1 2; do echo 'Loading workspace...' >"$S/on-keys-$n.txt"; echo blocked >"$S/on-keys-$n.status"; echo 2 >"$S/on-keys-$n.next-after"; done
  banner >"$S/on-keys-1.next.txt"; echo blocked >"$S/on-keys-1.next.status"
  echo 'Ready for input' >"$S/on-keys-2.next.txt"; echo idle >"$S/on-keys-2.next.status"
  start; assert_eq loading-between-exit 0 "$rc"; assert_eq loading-between-keys 'enter|esc|' "$(keys)"
  # Reported idle while the trust prompt stays on screen: never success.
  reset idle-trust-stays ok "$WT"; allow "$WT"; layout1 "$WT" >"$S/pane.txt"; layout1 "$WT" >"$S/on-keys-1.txt"; echo idle >"$S/on-keys-1.status"
  start
  assert_eq idle-trust-stays-exit 4 "$rc"; assert_eq idle-trust-stays-stdout '' "$out"
  assert_eq idle-trust-stays-keys 'enter|' "$(keys)"; assert_contains idle-trust-stays-reason 'nothing more sent' "$err"
  # unknown status on a loading screen that turns into a banner: the banner is handled.
  reset unknown-to-banner timeout "$WT"; jq '.name="" | .agent_status="unknown"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  echo 'Loading workspace...' >"$S/pane.txt"; echo 4 >"$S/next-after"; banner >"$S/next.txt"; echo blocked >"$S/next.status"
  echo idle >"$S/on-keys-1.status"
  start
  assert_eq unknown-to-banner-exit 0 "$rc"; assert_eq unknown-to-banner-keys 'esc|' "$(keys)"
  assert_eq unknown-to-banner-named fixture-impl "$(jq -r '.result.agents[0].name' "$S/agents.json")"
  # Ready but unnamed (every rename refused): a failure, never a success.
  reset rename-refused timeout "$WT"; jq '.name="" | .agent_status="idle"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  touch "$S/rename-fail"
  start
  assert_eq rename-refused-exit 1 "$rc"; assert_eq rename-refused-stdout '' "$out"
  assert_eq rename-refused-tries 2 "$(grep -c 'agent rename' "$MOCK_LOG")"
  assert_contains rename-refused-msg 'does not hold the name fixture-impl' "$err"
  # Ready after a failed start, with the trust prompt still shown: the trust rules apply.
  reset failed-idle-trust not_ready_stderr "$WT"; jq '.agent_status="idle"' "$S/start-agent.json" >"$S/a" && mv "$S/a" "$S/start-agent.json"
  layout1 "$WT" >"$S/pane.txt"
  start; blocked_case refused 'no allowlist'
  # A malformed agent list starts nothing.
  reset bad-list ok "$WT"; echo 'not json' >"$S/agents.json"
  start
  assert_eq bad-list-exit 1 "$rc"; assert_eq bad-list-no-start 0 "$(grep -c 'agent start' "$MOCK_LOG")"
  assert_contains bad-list-msg 'malformed' "$err"
fi
finish

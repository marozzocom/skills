#!/usr/bin/env bash
# herdr-backend.sh VERB [ARGS] — sole Herdr CLI boundary; bash 3.2.
# stdout contract (mutators are silent unless specified):
# flavor [RUN_DIR]: tui|app; marker-only, HERDR_ENV=1 wins; HERDR_FLAVOR
# selects only a present marker. RUN_DIR (or HERDR_BACKEND_RUN_DIR) rejects
# a recorded flavor mismatch. self: {flavor,id,pane,tab,space}; null app
# membership means not in the window, never the focused pane.
# agents: [{name,id,pane,tab,space,kind,status,status_age_s,title}]; missing
# agents/prefixes skip addresses lost to not_found during inventory.
# status stays null. tabs: [{id,label,space}]; spaces: [{id,label}].
# panes: [{id,tab,space,terminal,agent,status,cwd}] (cwd may be null).
# prefixes: [string] app run.prefix labels; tui [] without CLI calls.
# geometry [ID]: "cols rows", app never-drawn 200x120/120x40 => unknown.
# rename-self NAME: TUI rename; app run.name/run.role/run.prefix labels.
# rename-tab ID LABEL / rename-space ID LABEL: silent.
# tab-new SPACE LABEL CWD: tab=<id> pane=<id> (await app adoption).
# open-board RUN_DIR RATIO: pane id; app argv down split ignores ratio.
# start NAME KIND CWD (--pane P|--tab T [--space S]) [--timeout SECONDS]
#   -- ARGS: id, only after reported idle/done; KIND is executable in app.
#   App awaits adoption, then kill+removes an eligible idle sole root shell;
#   it creates no hidden parked root for teardown to discover.
# prompt NAME TEXT: started=true|false|null; wait NAME SECONDS: final status.
# App wait: ended => status/exit 0; otherwise reason (timeout/message/
# not_started) on stdout and exit 1.
# read-tail NAME N: <=N lines (app screen read locally tailed); keys NAME KEY…;
# close PANE_ID: silent (TUI pane close; app kill+rm of its terminal, also by name/address).
# callback-line PREFIX: TUI push line / app PULL brief wording.
# rotate NAME PANE CWD KIND -- ARGS: TUI original start JSON and unchanged
# quit/get/cwd/run/start sequence; app resolves NAME, ignores PANE, prints
# the new address; same name/tab/space, physical resolved CWD and supplied pin.
# App cockpit stores address in herdr.overseer_id; overseer_pane is physical.
# Exit: 0 success, 1 runtime/session/readiness failure, 2 usage, 3 unsupported
# verb in this flavor. Diagnostics on stderr. No vendor-to-executable table.
set -Eeuo pipefail
trap 'exit 1' ERR
usage() { echo "usage: herdr-backend.sh VERB [ARGS]" >&2; exit 2; }
fail() { echo "$*" >&2; exit 1; }
[ $# -gt 0 ] || usage
verb=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
flavor=''
case ${HERDR_FLAVOR:-} in
  tui) if [ "${HERDR_ENV:-}" = 1 ]; then flavor=tui; fi ;;
  app) if [ -n "${HC_TERMINAL_ID:-}" ]; then flavor=app; fi ;;
  '') if [ "${HERDR_ENV:-}" = 1 ]; then flavor=tui
      elif [ -n "${HC_TERMINAL_ID:-}" ]; then flavor=app; fi ;;
  *) fail "invalid HERDR_FLAVOR: $HERDR_FLAVOR" ;;
esac
[ -n "$flavor" ] || fail "not inside a Herdr session"
run=${HERDR_BACKEND_RUN_DIR:-}
if [ "$verb" = flavor ]; then [ $# -le 1 ] || usage; run=${1:-$run}; fi
if [ -n "$run" ] && [ -f "$run/status.json" ]; then
  recorded=$(jq -r '.herdr.flavor // ""' "$run/status.json")
  [ -z "$recorded" ] || [ "$recorded" = "$flavor" ] || fail "Herdr flavor mismatch: run=$recorded caller=$flavor"
fi
app_panes() {
  local core; core=$(hc ls --json) || return 1
  herdr-app ls | jq -ce --argjson core "$core" '[.spaces[] as $s | $s.tabs[] as $t | $t.terminals[] |
    {id:.pane,tab:$t.id,space:$s.id,terminal:.terminal,agent:.app,status:.status,
     cwd:(.terminal as $id|[$core.terminals[]|select(.address==$id)][0].cwd)}]'
}
self() {
  if [ "$flavor" = tui ]; then
    jq -cn --arg id "${HERDR_PANE_ID:-}" --arg tab "${HERDR_TAB_ID:-}" --arg space "${HERDR_WORKSPACE_ID:-}" \
      '{flavor:"tui",id:$id,pane:$id,tab:$tab,space:$space}'
  else
    app_panes | jq -c --arg id "$HC_TERMINAL_ID" '[.[]|select(.terminal==$id)][0] |
      {flavor:"app",id:$id,pane:.id,tab:.tab,space:.space}'
  fi
}
start_tui() {
  local name=$1 kind=$2 pane=$3 timeout=$4; shift 4
  local cmd=(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout "$timeout")
  if [ $# -gt 0 ]; then cmd+=(-- "$@"); fi
  "${cmd[@]}"
}
abort_start() {
  local id=$1; shift
  hc kill "$id" >/dev/null 2>&1 || true
  hc rm "$id" >/dev/null 2>&1 || true
  fail "$*"
}
start_app() {
  local name=$1 kind=$2 cwd=$3 pane=$4 tab=$5 space=$6 timeout=$7; shift 7
  local inventory root='' before detail created id deadline state remaining adopted
  inventory=$(app_panes)
  if [ -n "$pane" ]; then
    before=$(jq -ce --arg p "$pane" '[.[]|select(.id==$p)][0] // error("pane not in window")' <<<"$inventory")
    tab=$(jq -r .tab <<<"$before"); space=$(jq -r .space <<<"$before")
  elif [ -z "$space" ]; then
    before=$(herdr-app ls | jq -ce --arg t "$tab" --arg s "$space" \
      '[.spaces[]|select($s=="" or .id==$s)|. as $s|.tabs[]|select(.id==$t)|{space:$s.id}][0] // error("tab not in window")')
    space=$(jq -r .space <<<"$before")
  fi
  before=$(jq -c --arg t "$tab" '[.[]|select(.tab==$t)]' <<<"$inventory")
  if [ "$(jq length <<<"$before")" = 1 ]; then
    root=$(jq -r '.[0].terminal' <<<"$before")
  fi
  created=$(hc run --bg --name "$name" --cwd "$cwd" --label "herdr.space=$space" --label "herdr.tab=$tab" -- "$kind" "$@")
  id=$(jq -er '.address|strings|select(length>0)' <<<"$created")
  deadline=$((SECONDS + timeout))
  while :; do
    detail=$(hc get "$id" --json) || abort_start "$id" "$name readiness query failed"
    state=$(jq -r 'if (.status|type)=="object" then .status.state else .status end // "unreported"' <<<"$detail") || abort_start "$id" "$name invalid readiness response"
    if jq -e '.reported==true and (.status.state=="idle" or .status.state=="done")' <<<"$detail" >/dev/null; then break; fi
    case $state in blocked|error) abort_start "$id" "$name not ready: $state" ;; esac
    [ "$(jq -r .state <<<"$detail")" != finished ] || abort_start "$id" "$name exited before readiness"
    remaining=$((deadline - SECONDS)); [ "$remaining" -gt 0 ] || abort_start "$id" "$name readiness timed out ($state)"
    hc wait "$id" --timeout "$remaining" >/dev/null || abort_start "$id" "$name readiness wait failed"
    [ "$SECONDS" -lt "$deadline" ] || abort_start "$id" "$name readiness timed out ($state)"
  done
  while :; do
    inventory=$(app_panes) || abort_start "$id" "$name adoption query failed"
    adopted=$(jq -r --arg id "$id" --arg t "$tab" --arg s "$space" 'any(.[];.terminal==$id and .tab==$t and .space==$s)' <<<"$inventory") || abort_start "$id" "$name invalid adoption response"
    [ "$adopted" != true ] || break
    [ "$SECONDS" -lt "$deadline" ] || abort_start "$id" "$name not adopted into tab $tab"
    sleep 0.1
  done
  if [ -n "$root" ] && jq -e --arg t "$tab" --arg r "$root" \
    '[.[]|select(.tab==$t)]|length==2 and any(.[];.terminal==$r)' <<<"$inventory" >/dev/null; then
    # Recheck after adoption: the user may have used the root during startup.
    detail=$(hc get "$root" --json)
    if jq -e '.state=="live" and .name==null and .reported!=true and .status==null and
      (.argv[0]|split("/")|last|test("^(sh|bash|zsh|fish|dash|ksh)$")) and
      (.foreground!=null) and (.foreground==null or (.foreground.name|test("^(sh|bash|zsh|fish|dash|ksh)$")))' <<<"$detail" >/dev/null; then
      hc kill "$root" >/dev/null
      hc rm "$root" >/dev/null
    fi
  fi
  printf '%s\n' "$id"
}
case $verb in
  flavor) echo "$flavor" ;;
  self) [ $# -eq 0 ] || usage; self ;;
  prefixes)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = tui ]; then echo '[]'
    else
      list=$(hc ls --json); labels='[]'
      jq -e ' .terminals|type=="array"' <<<"$list" >/dev/null
      while IFS= read -r id; do
        if detail=$(hc get "$id" --json); then :
        else rc=$?; [ "$rc" -eq 3 ] && continue; exit 1; fi
        labels=$(jq -cn --argjson a "$labels" --argjson d "$detail" '$a + [$d.labels["run.prefix"]|strings]')
      done < <(jq -r '.terminals[].address' <<<"$list")
      echo "$labels"
    fi ;;
  agents)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = tui ]; then
      herdr agent list | jq -ce '[.result.agents[]|{name,id:.pane_id,pane:.pane_id,tab:.tab_id,space:.workspace_id,
        kind:.agent,status:.agent_status,status_age_s:.status_age_s,title:.terminal_title_stripped}]'
    else
      list=$(hc ls --json); inventory=$(app_panes); agents='[]'
      jq -e '.terminals|type=="array"' <<<"$list" >/dev/null
      while IFS= read -r id; do
        if detail=$(hc get "$id" --json); then :
        else rc=$?; [ "$rc" -eq 3 ] && continue; exit 1; fi
        agents=$(jq -cn --argjson a "$agents" --argjson d "$detail" --argjson ls "$list" --argjson p "$inventory" '
          ($ls.terminals[]|select(.address==$d.address)) as $l |
          ([$p[]|select(.terminal==$d.address)][0]) as $p |
          $a + [{name:($d.name // $d.labels["run.name"] // $l.name),id:$d.address,pane:$p.id,tab:$p.tab,space:$p.space,
            kind:($d.agent // $l.agent),status:(if ($d.status|type)=="object" then $d.status.state else $d.status end),
            status_age_s:(if $d.status_ms then ([0,(now-$d.status_ms/1000)]|max) else null end),title:$d.title}]')
      done < <(jq -r '.terminals[].address' <<<"$list")
      echo "$agents"
    fi ;;
  tabs|spaces|panes)
    [ $# -eq 0 ] || usage
    if [ "$flavor" = app ]; then
      case $verb in
        tabs) herdr-app ls | jq -ce '[.spaces[] as $s|$s.tabs[]|{id,label:.name,space:$s.id}]' ;;
        spaces) herdr-app ls | jq -ce '[.spaces[]|{id,label:.name}]' ;;
        panes) app_panes ;;
      esac
    else
      case $verb in
        tabs) herdr tab list | jq -ce '[.result.tabs[]|{id:.tab_id,label,space:.workspace_id}]' ;;
        spaces) herdr workspace list | jq -ce '[.result.workspaces[]|{id:.workspace_id,label}]' ;;
        panes) herdr pane list | jq -ce '[.result.panes[]|{id:.pane_id,tab:.tab_id,space:.workspace_id,terminal:.pane_id,agent,status:.agent_status,cwd}]' ;;
      esac
    fi ;;
  geometry)
    [ $# -le 1 ] || usage; id=${1:-}
    if [ "$flavor" = tui ]; then
      if [ -n "$id" ]; then layout=$(herdr pane layout --pane "$id"); else layout=$(herdr pane layout --current); fi
      jq -er --arg p "${id:-${HERDR_PANE_ID:-}}" '.result.layout|. as $l|
        (if $p!="" then $p else ($l.pane_id // $l.focused_pane_id) end) as $p |
        [.panes[]|select(.pane_id==$p)][0].rect // error("pane rect not found") | "\(.width) \(.height)"' <<<"$layout"
    else
      if [ -z "$id" ]; then id=$HC_TERMINAL_ID
      else inventory=$(app_panes); id=$(jq -r --arg id "$id" '[.[]|select(.id==$id)][0].terminal // $id' <<<"$inventory"); fi
      hc get "$id" --json | jq -er 'if (.cols==200 and .rows==120) or (.cols==120 and .rows==40) then "unknown"
        elif (.cols|type)=="number" and (.rows|type)=="number" then "\(.cols) \(.rows)" else error("geometry unavailable") end'
    fi ;;
  rename-self)
    [ $# -eq 1 ] || usage
    if [ "$flavor" = tui ]; then herdr agent rename "${HERDR_PANE_ID:?}" "$1" >/dev/null
    else hc label "$HC_TERMINAL_ID" "run.name=$1" "run.prefix=${1%-overseer}" run.role=overseer >/dev/null; fi ;;
  rename-tab|rename-space)
    [ $# -eq 2 ] || usage
    if [ "$flavor" = app ]; then
      case $verb in rename-tab) object=tab ;; *) object=space ;; esac
      herdr-app do "$object.rename" --id "$1" --name "$2" >/dev/null
    elif [ "$verb" = rename-tab ]; then herdr tab rename "$1" "$2" >/dev/null
    else herdr workspace rename "$1" "$2" >/dev/null; fi ;;
  tab-new)
    [ $# -eq 3 ] || usage
    if [ "$flavor" = tui ]; then
      created=$(herdr tab create --workspace "$1" --cwd "$3" --label "$2" --no-focus) || fail "ERROR: tab create failed"
      jq -er '.result|select((.tab.tab_id|type)=="string" and (.root_pane.pane_id|type)=="string")|"tab=\(.tab.tab_id) pane=\(.root_pane.pane_id)"' <<<"$created" || fail "ERROR: tab create returned no tab/pane IDs"
    else
      created=$(herdr-app do tab.new --space "$1" --folder "$3" --name "$2")
      tab=$(jq -er '.tab|strings' <<<"$created"); id=$(jq -er '.terminal|strings' <<<"$created"); deadline=$((SECONDS+10))
      while :; do
        inventory=$(app_panes); pane=$(jq -r --arg id "$id" '[.[]|select(.terminal==$id)][0].id // ""' <<<"$inventory")
        [ -z "$pane" ] || break
        [ "$SECONDS" -lt "$deadline" ] || fail "tab root not adopted"; sleep 0.1
      done
      echo "tab=$tab pane=$pane"
    fi ;;
  open-board)
    [ $# -eq 2 ] || usage; run=$1; ratio=$2; caller=$(self); pane=$(jq -er '.pane|strings|select(length>0)' <<<"$caller")
    if [ "$flavor" = tui ]; then
      split=$(herdr pane split "$pane" --direction down --ratio "$ratio" --cwd "$run" --no-focus) || fail "ERROR: board split failed"
      board=$(jq -er '.result.pane.pane_id|strings|select(length>0)' <<<"$split") || fail "ERROR: split did not return pane_id"
      "$here/../../implementation-orchestration/bin/status-set.sh" "$run" meta "board_pane=$board" >/dev/null
      printf -v command '%q %q' "$here/run-board.sh" "$run"
      herdr pane run "$board" "$command" >/dev/null || fail "ERROR: board command failed"
    else
      argv=$(jq -cn --arg s "$here/run-board.sh" --arg r "$run" '[$s,$r]')
      split=$(herdr-app do pane.split --direction down --pane "$pane" --argv "$argv")
      board=$(jq -er '.pane|strings|select(length>0)' <<<"$split")
    fi
    echo "$board" ;;
  start)
    [ $# -ge 5 ] || usage; name=$1; kind=$2; cwd=$3; shift 3; pane=''; tab=''; space=''; timeout=30
    while [ $# -gt 0 ]; do
      case $1 in --) shift; break ;; --pane|--tab|--space|--timeout)
        [ $# -ge 2 ] || usage
        case $1 in --pane) pane=$2 ;; --tab) tab=$2 ;; --space) space=$2 ;; --timeout) timeout=$2 ;; esac; shift 2 ;; *) usage ;; esac
    done
    [ -n "$name" ] && [ -n "$kind" ] && [ -n "$cwd" ] || usage
    case $timeout in ''|*[!0-9]*) usage ;; esac
    [ "$timeout" -gt 0 ] || usage
    { [ -n "$pane" ] && [ -z "$tab" ] && [ -z "$space" ]; } || { [ -n "$tab" ] && [ -z "$pane" ]; } || usage
    if [ "$flavor" = app ]; then start_app "$name" "$kind" "$cwd" "$pane" "$tab" "$space" "$timeout" "$@"
    else
      if [ -z "$pane" ]; then
        pane=$(herdr pane list | jq -r --arg t "$tab" '[.result.panes[]|select(.tab_id==$t and .agent==null)][0].pane_id // empty')
        [ -n "$pane" ] || { echo "start: tab $tab has no pane without an agent; create a tab with run-tab.sh and pass --pane" >&2; exit 1; }
      fi
      start_tui "$name" "$kind" "$pane" "$((timeout*1000))" "$@" | jq -er '.result.agent.pane_id // .result.pane_id // error("start returned no id")'
    fi ;;
  prompt)
    [ $# -eq 2 ] || usage
    if [ "$flavor" = tui ]; then result=$(herdr agent prompt "$1" "$2"); else result=$(hc send "$1" "$2"); fi
    jq -r '(if has("result") then .result else . end)|"started=\(if .started==true then "true" elif .started==false then "false" else "null" end)"' <<<"$result" ;;
  wait)
    [ $# -eq 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac
    if [ "$flavor" = tui ]; then herdr agent wait "$1" --timeout "$(($2*1000))" | jq -er '.result.agent.agent_status // .result.agent_status // .result.status'
    else
      result=$(hc wait "$1" --timeout "$2")
      jq -r 'if .ended==true then .status // .reason else .reason end' <<<"$result"
      jq -e '.ended==true' <<<"$result" >/dev/null || exit 1
    fi ;;
  read-tail)
    [ $# -eq 2 ] || usage; case $2 in ''|*[!0-9]*) usage ;; esac; [ "$2" -gt 0 ] || usage
    if [ "$flavor" = tui ]; then herdr agent read "$1" --source visible --lines "$2"
    else hc read "$1" --lines 0 --json | jq -j '.text' | tail -n "$2"; fi ;;
  keys)
    [ $# -ge 2 ] || usage
    if [ "$flavor" = tui ]; then herdr agent send-keys "$@" >/dev/null
    else name=$1; shift; keys=(); for key in "$@"; do keys+=("${key/ctrl-c/ctrl+c}"); done; hc keys "$name" "${keys[@]}" >/dev/null; fi ;;
  close)
    [ $# -eq 1 ] || usage
    if [ "$flavor" = tui ]; then herdr pane close "$1" >/dev/null
    else inventory=$(app_panes); id=$(jq -r --arg id "$1" '[.[]|select(.id==$id)][0].terminal // $id' <<<"$inventory")
      id=$(hc get "$id" --json | jq -er .address); hc kill "$id" >/dev/null; hc rm "$id" >/dev/null; fi ;;
  rotate)
    [ $# -ge 5 ] || usage; name=$1; pane=$2; dir=$3; kind=$4; shift 4
    [ "${1:-}" = -- ] || usage; shift; agent_args=("$@")
    target=$(cd "$dir" && pwd -P)
    if [ ${#agent_args[@]} -eq 0 ]; then
      echo "warning: no native agent args — '$kind' will start on its config" \
           "default, not an explicit model pin (see environment.md)" >&2
    fi
    if [ "$flavor" = app ]; then
      detail=$(hc get "$name" --json); id=$(jq -er .address <<<"$detail")
      inventory=$(app_panes)
      location=$(jq -ce --arg id "$id" '[.[]|select(.terminal==$id)][0] // error("agent not in window")' <<<"$inventory")
      tab=$(jq -r .tab <<<"$location"); space=$(jq -r .space <<<"$location")
      hc kill "$id" >/dev/null; hc rm "$id" >/dev/null
      if [ ${#agent_args[@]} -eq 0 ]; then start_app "$name" "$kind" "$target" '' "$tab" "$space" 60
      else start_app "$name" "$kind" "$target" '' "$tab" "$space" 60 "${agent_args[@]}"; fi
    else
      pane_has_agent() { herdr agent get "$pane" >/dev/null 2>&1; }
      await_agent_gone() {
        local deadline=$((SECONDS + $1))
        while pane_has_agent; do
          [ "$SECONDS" -ge "$deadline" ] && return 1
          sleep 1
        done
        return 0
      }
      if pane_has_agent; then
        primary='/quit'
        secondary='/exit'
        if [ -n "${ROTATE_QUIT_CMD:-}" ]; then
          secondary=$primary
          primary=$ROTATE_QUIT_CMD
        fi
        wait_each=${ROTATE_QUIT_WAIT:-8}
        ladder=(
          "prompt:$primary"
          "prompt:$primary"
          "keys:esc|prompt:$primary"
          "prompt:$secondary"
          "keys:ctrl-c|prompt:$secondary"
        )
        quit_ok=0
        for round in "${ladder[@]}"; do
          IFS='|' read -r -a steps <<<"$round"
          for step in "${steps[@]}"; do
            case "$step" in
              keys:*)
                herdr agent send-keys "$pane" "${step#keys:}" >/dev/null 2>&1 || true
                sleep 1
                ;;
              prompt:*)
                herdr agent prompt "$pane" "${step#prompt:}" >/dev/null 2>&1 || true
                ;;
            esac
          done
          if await_agent_gone "$wait_each"; then quit_ok=1; break; fi
          echo "quit attempt did not take ($round) — escalating" >&2
        done
        if [ "$quit_ok" != 1 ]; then
          echo "agent in pane $pane survived every quit attempt — not proceeding" >&2
          echo "(inspect with: herdr agent read $pane --source visible)" >&2
          exit 1
        fi
        sleep 1
      fi
      pane_foreground_cwd() {
        herdr pane get "$pane" | python3 -c 'import json,sys; d=json.load(sys.stdin)["result"]; p=d.get("pane") or d; print(p.get("foreground_cwd") or p.get("cwd") or "")'
      }
      herdr pane run "$pane" "cd '$dir'" >/dev/null
      deadline=$((SECONDS + 10))
      while [ "$(pane_foreground_cwd)" != "$target" ]; do
        if [ "$SECONDS" -ge "$deadline" ]; then
          echo "pane $pane did not reach cwd $target within 10s — not proceeding" >&2
          exit 1
        fi
        sleep 1
      done
      start_agent() {
        if [ ${#agent_args[@]} -eq 0 ]; then
          herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000
        else
          herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 \
            -- "${agent_args[@]}"
        fi
      }

      if ! start_agent; then
        sleep 3
        start_agent
      fi
    fi ;;
  callback-line)
    [ $# -eq 1 ] || usage
    if [ "$flavor" = tui ]; then printf 'herdr agent prompt %s-overseer "<message>"\n' "$1"
    else echo 'Write the report/questions file named in the brief, then end your turn. The overseer is watching your turn state.'; fi ;;
  *) echo "unsupported verb in $flavor: $verb" >&2; exit 3 ;;
esac

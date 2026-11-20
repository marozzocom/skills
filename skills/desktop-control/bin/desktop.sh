#!/usr/bin/env bash
# Tell the person at this Mac, out loud and on screen, that an agent is taking
# the desktop (real windows, mouse, keyboard or focus), and when it gives it back.
#
#   desktop.sh take WHO WHAT [MINUTES]   speak + notify, keep the display awake,
#                                        record the hold. Prints "desktop TAKEN …".
#   desktop.sh release                   end the hold, speak + notify.
#                                        Prints "desktop RELEASED".
#   desktop.sh status                    print the current hold, if any.
#
# WHO is the agent or project ("Claude, for Tide"); WHAT is a few words the
# person will hear ("a visible test run"). MINUTES defaults to 2.
#
# Exit codes of `take`: 0 taken; 3 the screen is locked (nothing would work,
# and keystrokes would land in the password field); 4 another hold is live
# (its line is printed). A hold older than its own estimate plus 10 minutes is
# stale and is replaced. `release` always exits 0, also with nothing held.
#
# DESKTOP_CONTROL_QUIET=1 skips the voice; the notification still shows.
set -euo pipefail

state="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-control"
hold="$state/hold"
mkdir -p "$state"

notify() { # title, text
    osascript -e 'on run argv
        display notification (item 2 of argv) with title (item 1 of argv)
    end run' "$1" "$2" >/dev/null 2>&1 || true
}
speak() {
    [ -n "${DESKTOP_CONTROL_QUIET-}" ] || say "$1" 2>/dev/null || true
}
locked() {
    ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'
}
# Prints the live hold's line and returns 0, or returns 1 after clearing a stale one.
live_hold() {
    [ -f "$hold" ] || return 1
    local until who what awake
    IFS=$'\t' read -r until who what awake < "$hold" || true
    if [ "$(date +%s)" -gt "$((until + 600))" ]; then
        [ -z "${awake-}" ] || kill "$awake" 2>/dev/null || true
        rm -f "$hold"
        return 1
    fi
    printf 'held by %s for %s until about %s\n' "$who" "$what" "$(date -r "$until" +%H:%M)"
}

case "${1-}" in
take)
    who="${2:?WHO}"; what="${3:?WHAT}"; minutes="${4:-2}"
    if locked; then
        echo "desktop NOT taken: the screen is locked"
        exit 3
    fi
    if line="$(live_hold)"; then
        echo "desktop NOT taken: $line"
        exit 4
    fi
    caffeinate -d -i -t "$((minutes * 60 + 600))" &
    awake=$!
    disown "$awake" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\n' "$(($(date +%s) + minutes * 60))" "$who" "$what" "$awake" > "$hold"
    notify "Desktop TAKEN: hands off" "$who: $what, about $minutes min"
    speak "Hands off. $who is taking the desktop for $what. About $minutes minutes."
    echo "desktop TAKEN by $who for $what, about $minutes min"
    ;;
release)
    if [ -f "$hold" ]; then
        IFS=$'\t' read -r _ who _ awake < "$hold" || true
        [ -z "${awake-}" ] || kill "$awake" 2>/dev/null || true
        rm -f "$hold"
        notify "Desktop RELEASED" "${who:-The agent} is done. It's yours again."
        speak "Desktop released. It's yours again."
    fi
    echo "desktop RELEASED"
    ;;
status)
    live_hold || echo "free"
    ;;
*)
    sed -n '2,20p' "$0"
    exit 2
    ;;
esac

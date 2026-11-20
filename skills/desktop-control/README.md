# desktop-control

Makes an agent's use of your Mac's desktop impossible to miss: a spoken
"Hands off" and a notification when it starts, and "Desktop released" when it
ends.

## Setup

macOS only; uses `say`, `osascript`, `caffeinate` and `ioreg`, all part of the
system. Symlink or copy this directory into your skills directory. Allow
notifications for Script Editor (`osascript` posts as it) in System Settings,
or you will hear the voice but see nothing.

## Use

```sh
bin/desktop.sh take "Claude, for my app" "a visible test run" 2
bin/desktop.sh release
bin/desktop.sh status
```

The hold is one file under `${XDG_STATE_HOME:-~/.local/state}/desktop-control/`,
so agents in different sessions see each other's holds.
`DESKTOP_CONTROL_QUIET=1` turns the voice off.

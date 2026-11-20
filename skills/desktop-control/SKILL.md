---
name: desktop-control
description: Announce out loud and with a notification that an agent is taking the Mac's desktop, and when it releases it. Use before anything that shows windows, steals focus, or drives the real mouse or keyboard (visible UI tests, screenshots or recordings of a live app, browser or app automation on the person's own screen), and again the moment it ends. Not for headless or hidden runs.
---

# Desktop control

The person at this Mac is usually working while you are. Anything that opens
visible windows, takes focus, or moves the pointer or types for them interrupts
that work, and their own input breaks your run. So say when you take the
desktop and when you give it back, in a way they can't miss: a spoken line and
a notification, both from one script.

```sh
bin/desktop.sh take "Claude, for Tide" "a visible test run" 2   # WHO, WHAT, minutes
# … the visible work …
bin/desktop.sh release
```

`take` says "Hands off. WHO is taking the desktop for WHAT. About N minutes.",
shows a notification, keeps the display awake and records the hold. `release`
says "Desktop released. It's yours again." Write WHO and WHAT as words to be
heard: no paths, ids or abbreviations.

## Rules

1. **Ask first unless you already have a go for this run.** Taking the desktop
   needs the person's consent; the announcement tells them it is starting, it
   is not the permission. A go covers one hold.
2. **Prefer not needing it.** If the work can run hidden, headless or in its
   own browser profile, do that and skip this skill.
3. **Take as late and as briefly as you can.** Build, compile and prepare
   before `take`. Give an honest estimate; batch what needs the desktop into
   one hold instead of several short ones.
4. **Honor a refusal.** Exit 3 means the screen is locked: nothing visible
   will work and keystrokes would land in the password field. Exit 4 means
   another agent holds the desktop: wait for it, don't take over. Report
   either instead of working around it.
5. **Always release**, also when the work fails or you abort. Run `release`
   in the same command as the work (`take && { work; rc=$?; release; }`), so an
   error can't leave the desktop marked as held. Then say in the session that
   it is released, and whether any window was left open on purpose.
6. **Recheck before late keystrokes.** In a long hold, check
   `bin/desktop.sh status` and the lock again right before synthetic typing.
7. **Say the same thing in the session**: one line when taken, one when
   released, so the transcript matches what the person heard.

`DESKTOP_CONTROL_QUIET=1` skips the voice and keeps the notification; use it
only when the person asked for silence. A hold that outlives its estimate by
ten minutes is treated as abandoned and the next `take` replaces it.

# Device test checklist

Build and run on a phone (USB debugging on, `adb devices` shows it):

```bash
bash tool/copy_rootfs.sh arm64-v8a
cd app && flutter run -d <serial>
```

Nothing below has been run on a device yet. Items marked **assumption** rely on OpenCode API details taken from its
published server API, not yet checked against the running server (see `docs/opencode-api.md`).

## 1. First run
- [ ] Disclosure screen shows; nothing installs until "I understand, continue".
- [ ] "Allow notifications" asks on Android 13+. Deny it: onboarding still continues, the server still runs.
- [ ] Setup unpacks (progress counter moves), self-test shows `aarch64`, Node, Python, OpenCode.
- [ ] Home opens, banner shows "Starting the OpenCode server…" then disappears. Record the start time.

## 2. Home: history and search
- [ ] **assumption** Empty state says "No sessions yet". Create a session ("New session" → new project folder `demo`).
- [ ] **assumption** The chat opens inside the app on that session (not on the OpenCode project picker).
- [ ] Send a message with a provider key (log in from OpenCode's own screen). Markdown, code blocks, tool calls render.
- [ ] Back to Home: the session is listed under "Today" with its title and folder.
- [ ] **assumption** Search by a word from the title: list filters after ~0.3 s. Clear the search: full list returns.
- [ ] Rename and delete a session from the ⋮ menu.
- [ ] Sessions made in two different project folders both appear.

## 3. Files
- [ ] `/root`, `projects/demo` visible. Files OpenCode created in chat show up (Refresh / switching tabs reloads).
- [ ] New folder, new file, rename, copy → paste, cut → paste, multi-select delete.
- [ ] Open a text file, edit, Save; leaving with unsaved changes asks. A binary file says it cannot be edited.
- [ ] "New session here" starts a chat in that folder.

## 4. Terminal
- [ ] Shell opens lazily on first visit. `uname -m`, `node -v`, `python3 -V`, `pip install requests`.
- [ ] Extra keys: Esc, Tab, Ctrl (sticky) + `c` stops `sleep 100`; arrows move history; `vim`/`htop` redraw after rotating.
- [ ] Two tabs; close one; `exit` shows "[process exited]" and Restart works.

## 5. Lifecycle (the important part)
- [ ] Swipe the app away with the server running. The "OpenCode is running" notification stays. Reopen: same server, no restart.
- [ ] `pkill -f opencode` in the terminal: Home shows "restarting…", then the chat works again (new port).
- [ ] Settings → idle 5 min, leave the app with no terminal open: the service stops after ~5 min and the notification goes.
  Repeat with a terminal open: it stays up. Repeat while OpenCode is mid-task (**assumption**: busy check works).
- [ ] Reopen after an idle stop: the server comes back by itself.
- [ ] Notification "Stop" button stops the server and the notification disappears.
- [ ] Open many heavy apps: terminals are dropped first, the server last.
- [ ] 10 minutes in the background with the screen off (try Samsung / Xiaomi battery settings): did the server survive?

## 6. Settings and environment
- [ ] Config file opens (created from a template if missing); invalid JSON cannot be saved; saving offers "Restart".
- [ ] Linux environment page: versions and sizes. "Install build tools" runs `apk add` visibly in the Terminal tab.
- [ ] Reset environment: confirm text says `/root` is kept; files in `/root/projects` survive; setup runs again.
- [ ] "Restore extra packages" appears after reset if `/root/.apk-extra` has entries.

## What to send back if something fails
`adb logcat -d | grep -i -E "opencode|proot|flutter"`, the Settings → Server log text, and which step number.

# 04 App relaunch

Open question 4 of `docs/research.md`. Written 2026-11-21. All examples are made up.

Marks: [tested] ran read-only on this machine, [source] read from a file or script, [docs] from the app's documented behavior (from memory, not re-fetched), [search] not done.

## Summary

1. A window gives us a pid, a class and (maybe) a systemd scope. From those we can find the app's `.desktop` entry for most apps. We never need to store the raw command line for them.
2. The best relaunch recipe is "desktop entry id + a small, app-type specific extra" (a folder, a URL, a session name). Raw `/proc/<pid>/cmdline` is a last resort and the main privacy risk.
3. Apps split in three groups: we start them and place the window (native, web apps, terminals); the app restores itself and we only place windows (browsers, Electron, editors); and we cannot do much (apps that need a file or a login).
4. Matching a new window to a saved slot must use class plus a launch token (we start it, we know the pid or scope), not the title.
5. A per-app rule table (class pattern to strategy) is needed. Users extend it. Ship a default table for Omarchy's own apps.

## Table

| App type | Detect | Relaunch | Match new window | Reliability | Privacy risk |
|---|---|---|---|---|---|
| Native Wayland GUI (Slack-like, Nautilus-like) | class to `.desktop` id; scope `app-<id>-<pid>.scope` | `uwsm-app -- <desktop-id>` (or `gtk-launch`) | class, new address after launch | high | low (id only) |
| XWayland app | same, `xwayland=true`; class is `WM_CLASS` | same | class (instance too) | high | low |
| Flatpak | scope `app-flatpak-<appid>-<pid>.scope`; class often equals app id | `flatpak run <appid>` or the `.desktop` | class | high | low |
| AppImage | no `.desktop` (usually); `/proc/<pid>/exe` points into a mount; `$APPIMAGE` env | run the stored AppImage path | class | medium | medium (path) |
| Omarchy web app (Chromium `--app=`) | class `chrome-<host>_<path>-Default` | `omarchy-launch-webapp <url>` | exact class | high | medium (URL may hold ids) |
| Terminal, plain shell | terminal class; child shell cwd | `omarchy-launch-terminal` style: `xdg-terminal-exec --dir=<cwd>` | app id / class + new pid | high | high (folder) |
| Terminal with TUI (nvim, btop) | foreground process under the shell | `omarchy-launch-tui --app-id=<id> <cmd>` | app id (we set it) | medium | high (args, files) |
| tmux / zellij session | session name from the terminal's child command | `tmux attach -t <name>` in a new terminal | app id we set | high if session alive; low after reboot | medium (name) |
| Full browser (Chrome, Firefox) | class `google-chrome`, many windows, one pid | start once; browser restores its tabs; we only place windows | window order, address, not title | medium | very high (tabs) |
| Single-instance Electron (Slack, Obsidian, VS Code, Spotify) | one pid, many windows | start once, app restores its windows | class, count | medium | high for VS Code and Obsidian (folder, vault) |
| App needing a file or argument | cmdline has a path | store only if user opts in | class | low | very high |

## How we find the command

Order of trust, best first. Stop at the first hit.

1. **Rule table hit.** Class matches a user or default rule. The rule says how to relaunch. No process data is read.
2. **Desktop entry by class.** Look up `.desktop` files in the data dirs. Match the window class to the desktop id (lower case, with and without `.desktop`), or to `StartupWMClass`. This is exactly the chain omahop already uses for icons (`IconResolve.packPick`: desktop id, `StartupWMClass`, lower case, hyphenated, last part of a reverse DNS id) [source: `omahop/docs/research/launcher-icons.md` lines 62-66]. Reuse it, do not redo it. `StartupWMClass` is present in 31 of this machine's local entries plus many system ones, so it is not complete [tested: `grep -c`, counts only].
3. **systemd scope name.** uwsm and `uwsm-app` start each app in a scope. On this machine, apps started from a desktop entry have `app-<desktop-id>-<pid>.scope` (`app-slack-<pid>.scope`, `app-com.google.Chrome-<pid>.scope`) [tested: `systemctl --user list-units --type=scope`, `/proc/<pid>/cgroup`]. Apps started by a command have `app-Hyprland-<command>-<random>.scope` (`app-Hyprland-xdg-terminal-exec-<hex>.scope`, `app-Hyprland-herdr-<hex>.scope`) [tested]. So the scope gives a desktop id for entry launches and only a command name for the rest. Names use systemd escapes (`\x2d` for `-`), so unescape first.
4. **`GIO_LAUNCHED_DESKTOP_FILE` in `/proc/<pid>/environ`.** GLib sets it when an app is launched through GIO [docs]. On this machine the variable was absent from the three processes checked (Slack, a kitty terminal, Chrome) [tested: key names only, values not read]. So do not depend on it. Also, `environ` can hold secrets. Read only this one key, never log the rest.
5. **`/proc/<pid>/exe` and `cmdline`.** The exe path is fine to use for finding a matching entry (`Exec=` first word). The full `cmdline` is last resort, and must only be stored after the user agrees (see Privacy).
6. **Hyprland client `pid`.** Many windows can share one pid (Chrome showed 4 windows on one pid [tested: `hyprctl -j clients`, fields class and pid only]). So pid identifies the process, not the window.

Gotchas:

- Class is not stable between app versions. Keep a "class aliases" list in the rule.
- A window class of `org.omarchy.<cmd>` means Omarchy's TUI launcher started it [source: `omarchy-launch-tui`: `APP_ID="org.omarchy.$(basename $1)"`]. The command name is in the class itself. A user's `--app-id=` choice replaces it, so the rule table needs both.
- XWayland windows report `WM_CLASS` as class; the matching works the same.

## Per type

### Native Wayland and XWayland apps

- Detect: class to desktop entry (above).
- Relaunch: `uwsm-app -- <desktop-id>`; Omarchy launches everything through `uwsm-app` [source: `omarchy-launch-tui`, `-webapp`, `-or-focus`]. Keeping that wrapper means the new app also gets a scope, so session tools see it the same way.
- Match: new window with the same class whose address was not present before launch. A fast pre-launch snapshot of addresses is enough. Slow apps may take seconds, so use a timeout per rule (default about 15 s) and give up with a visible note.
- Reliability: high. Privacy: low, the desktop id is public knowledge.
- Do not store `Exec=` expanded with `%U`/`%F` arguments. Launch by id.

### Flatpak

- Detect: scope `app-flatpak-<appid>-<pid>.scope` is the usual shape [docs: Flatpak runs under a systemd scope named this way; flatpak installed here, no flatpak app was running, so not tested]. Class usually equals the app id, so the desktop entry in `/var/lib/flatpak/exports/share/applications` or `~/.local/share/flatpak/exports/share/applications` matches by name.
- Relaunch: the desktop entry id (works with `uwsm-app`), or `flatpak run <appid>`.
- Match: class. Reliability: high. Privacy: low.
- Caveat: sandbox can hide the real pid in `/proc` listing of the child. The client pid from Hyprland still works because it is the host pid [docs].

### AppImage

- Detect: no desktop entry unless the user used an integration tool. `/proc/<pid>/exe` points into a temporary mount; the `APPIMAGE` env var holds the real file path [docs]. Not tested, no AppImage open.
- Relaunch: only from a stored path. Store it as a user-approved rule (class to path), not guessed.
- Reliability: medium (file may move). Privacy: medium (home path). Use `~/` relative form, never log it.

### Omarchy web apps (Chromium `--app=`)

- Detect: class `chrome-<host>_<path>-Default`, for example `chrome-example.com__-Default`. Omarchy names it from the URL: host lower case, `/` replaced by `_` [source: `omarchy-webapp-window-class`]. This machine shows two such windows [tested].
- Relaunch: `omarchy-launch-webapp <url>` [source]. It picks the default Chromium family browser and calls `uwsm-app -- <browser> --app=<url>`. Omarchy also has `omarchy-launch-or-focus-webapp <pattern> <url>`, which focuses an existing window or launches [source].
- Problem: class to URL is lossy (`_` for `/`). Two different URLs can give one class. Better: read the `.desktop` file written by `omarchy-webapp-install`; its `StartupWMClass` is that class and its `Exec=` holds the URL [source: webapp-install header and window-class comment "a web app's launcher can name its window in StartupWMClass"]. So the desktop entry lookup (step 2) gives the exact URL. No entry with `app=` was found in `~/.local/share/applications` on this machine [tested: grep], so web apps here may be created some other way; the fallback is to rebuild the URL from the class (best effort) and ask the user.
- Match: exact class. High reliability.
- Privacy: the URL can hold ids or tokens. Store the desktop id when there is one, not the URL. If we must store a URL, strip query and fragment (Omarchy's own class builder does the same).
- Single-instance note: several web apps share one Chromium pid (all `pid 2932105` above [tested]). Do not use pid to tell them apart.

### Terminals (foot, kitty; alacritty and ghostty not installed here)

Omarchy's default terminal on this machine: kitty is running; foot is installed [tested: `which`]. Omarchy launches terminals through `xdg-terminal-exec` [source].

- Working folder:
  - Omarchy already solves "new terminal in the same folder": `omarchy-cmd-terminal-cwd`. For kitty it asks the kitty remote socket (`$XDG_RUNTIME_DIR/omarchy-kitty-<pid>`) with `kitten @ ls`; for others it finds the newest child shell and reads its cwd [source]. Reuse this logic. The shell's cwd is `readlink /proc/<shell-pid>/cwd` [docs].
  - Relaunch: `xdg-terminal-exec --dir=<cwd>` as `omarchy-launch-terminal` does [source]. Both foot and kitty support a working-directory flag [docs] but `xdg-terminal-exec` hides that.
- Running command (nvim, btop, a TUI):
  - Detect: the foreground process of the terminal's pty (`tpgid` in `/proc/<shell>/stat`, then its `/proc/<pid>/comm` and `cmdline`) [docs, not tested because it would read real command lines].
  - Relaunch: `omarchy-launch-tui --app-id=<id> <cmd> [args]` [source]. This gives a window class we control, so matching is easy.
  - Safe subset: store only the command name from an allow list (nvim, btop, lazygit, lazydocker, tuios ...), plus args only when the rule says so. Never store args by default: for an editor the args are file names.
  - We cannot restore the inside of a TUI (scroll back, unsaved buffer, shell history in memory). Say so in the UI.
- Terminal multiplexers:
  - tmux: `tmux attach -t <name>`. Omarchy ships `omarchy-launch-terminal-tmux` doing `tmux attach || tmux new -s Work` [source]. Best case: the session lives on, so we only start a terminal that attaches. After a reboot the server is gone. tmux restore needs a plugin (tmux-resurrect) [docs], out of scope.
  - zellij: `zellij attach <name>` [docs]. Same rules. Not installed here.
  - tuios: this workspace uses it; its sessions are separate from this problem. Not researched.
  - Detect: the pty's foreground process is `tmux: client`; read `tmux display -p '#S'` per client [docs]. Session names can be private, store with user consent.
- Match: set our own app id (`--app-id`) on every terminal we restore, so we match by class, not title. Terminal titles change all the time and hold folders and commands.
- Reliability: high for folder, medium for a command, low after reboot for anything stateful. Privacy: high. Folder paths show projects and clients. Store them in the scene file only if the user turns on "remember folders", and prefer `~/`-relative form.

### Full browsers (Chrome, Firefox)

- Detect: class `google-chrome` or `firefox`, many windows, one pid [tested for Chrome].
- Relaunch: start the browser once. Browsers restore their own windows and tabs when "continue where you left off" is on [docs]. Starting more than one process is wrong: a second start passes control to the first (single instance).
- What omaplace does: start the browser (if no window of that class exists), wait for N windows, then place windows by order (Hyprland address order, or by the saved size). Matching windows to saved slots is a guess; sort by size or by creation order.
- Never store: tab titles, URLs, profile names, window titles. Browser window titles are tab titles. This is the biggest leak in the whole feature.
- Reliability: medium (counts differ). Offer a rule option "place only" and a rule option "N windows expected".
- Option for later: Chromium `--restore-last-session` and profile flags [docs]. Do not rely on it.

### Single-instance apps (Electron and friends)

Slack, Obsidian, VS Code, Spotify, Discord: one process tree, often many windows [docs]. On this machine Slack has one scope and one pid [tested].

- Relaunch: start the app once from its desktop entry. A second call usually sends "open window" to the first process.
- Self-restore: Slack, Spotify, Discord reopen the last window state [docs]. Obsidian reopens the last vault(s). VS Code reopens last folders when `window.restoreWindows` is on (default) [docs]. We should let them, then place windows.
- To force a specific folder (VS Code `code <folder>`, Obsidian `obsidian://open?vault=<name>` [docs]) we would store a private name. Make it a rule field with default off.
- Match: class, and for multi-window apps a count plus order. VS Code windows share a class, so match by saved geometry only if the title is not used. A title hint (folder name) is allowed in memory for matching but not stored.
- Reliability: medium. Privacy: high for editors and notes (folder or vault names).
- A new window on an already-running app: a launch may only create a window if the app was told to; the new window comes from the old pid. So "new address with same class after launch" is the right match, not pid.

### Apps needing a file or argument

- Detect: cmdline has a path or URL after the program. Typical: PDF viewer, image viewer, media player.
- Relaunch: only with explicit user consent per rule. Default is to start the app without its argument and say "this app was open on a file".
- Reliability low, privacy very high. File names are the most private thing here.

## Matching a new window

Order of preference:

1. **Window address that was not there before** plus class. Needs a snapshot just before launch. Fast and exact for one launch at a time.
2. **Launch-time pid or scope.** We start via `uwsm-app` so we know the scope; the new window's pid is in that scope. Works for one app per process; fails for single-instance apps and browsers (window belongs to the old pid).
3. **Our own app id** (`--app-id=<scene>-<n>`) for terminals. The strongest match, and free.
4. **`initialClass` and class** to catch apps that rename the class after start (compare `initialClass` too, as `hyprctl -j clients` exposes both [tested]).
5. **Title.** Last resort, only held in memory, never stored. Do not rely on it (changes, private).

Race: slow apps map late. Rules need `timeout` and `max_windows`. Hyprland offers events (`openwindow`) and `exec` rules with workspace and monitor; those are the job of research 02, not here.

## Privacy rules (must never be stored or logged)

- Window titles. Browser tab URLs. Full `cmdline` and `environ`.
- File names, folder names, vault names, tmux session names, URL query and fragment: only if a rule has an explicit `remember: true` flag, shown in the scene editor, stored in the scene file with user-only permissions (mode 600), never in logs, never in crash reports, never in public demos.
- Logs: log class, desktop id and a count. Never log an argument list. If a debug log needs one, hash it.
- Paths under home: store as `~/...`, not `/home/<user>/...`.
- Tests: use made-up fixtures (`/home/test/projects/demo`, `chrome-example.com__-Default`).

## What this means for omaplace

- A scene entry is: `{ rule_id, class, strategy, geometry, optional extras }`. The strategy is one of: `desktop-entry`, `webapp`, `terminal` (+ folder), `tui` (+ command), `multiplexer` (+ session), `place-only` (browser, self-restoring apps), `command` (user-written).
- Build a **per-app rule table** (TOML, user file overrides defaults). Fields: class patterns, aliases, strategy, `timeout`, `max_windows`, `remember` flags, `match` order. Default rows for Omarchy's own apps: terminal, TUIs (`org.omarchy.*`), web apps, browser, Files, editor.
- Prefer ids over commands. Store desktop id, not `Exec=`. Raw cmdline only through a user-approved `command` rule.
- Reuse omahop's class to desktop entry resolver and Omarchy's `omarchy-cmd-terminal-cwd` and `omarchy-launch-*`. Do not write new launchers. Start everything through `uwsm-app`.
- Own the terminal app id: restore every terminal with `--app-id`, so matching is by class.
- "Place only" is a first-class mode. For browsers and Electron apps, scenes should not try to rebuild their insides.
- Session restore after reboot works best for web apps, native apps and plain terminals. It is weak for tmux, TUIs with state, and file-based apps; the UI must show this per entry (traffic light: restored, started only, skipped).
- Maintenance: every strategy must be a small module with a fixture test (fake desktop entries, fake `/proc`). Class names change between app releases, so keep alias lists in data, not code.

## Open questions left

1. Alacritty and ghostty: not installed here. Do `--working-directory`, `--class` and `--app-id` behave through `xdg-terminal-exec` the same way as for kitty and foot? [search]
2. Where does `omarchy-webapp-install` write its `.desktop`, and is `Exec=` always the URL? No web app entry was found locally. Need one more check on a machine that created a web app.
3. Foreground-process detection in terminals reads real command lines. Needs a safe design (read only `comm`, allow list) and a test that uses a fake `/proc`.
4. Does `uwsm-app` keep the scope name `app-<id>-<pid>` for Flatpak desktop entries, and does `GIO_LAUNCHED_DESKTOP_FILE` appear when launched from the Omarchy launcher? Neither was seen.
5. Single-instance apps: how does each decide to open an extra window on a second launch? Test per app on a spare machine, with the user's approval (it starts apps).
6. Browser window count and order after self-restore: is there a stable order to place windows by?
7. Should a scene record how an app was started originally (launcher entry vs keybinding), to avoid starting twice?

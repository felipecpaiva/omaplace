# WP7s live checks (session restore). Ask Felipe before each; made-up scenes only, no synthetic input.

Run `omarchy restart shell` first (the shell caches plugin JavaScript). Needs a session file from a previous login.

1. [ ] Fresh login with no previous session: `omaplace restore` exits 3.
2. [ ] After a login that left a session file: `omaplace restore` starts the apps, each on its own monitor and desktop;
   the notification shows `N placed (M started)`.
3. [ ] `omaplace restore 2` restores the second previous session; `omaplace restore <instance>` a named one.
4. [ ] `omaplace restore` while a run is going answers busy (exit 5).
5. [ ] Unplug a monitor first: its windows land on the focused one.

# WP12b live checks (desktop plans, service side)

Ask Felipe right before each check. No synthetic input, no virtual monitor. Harmless apps only. Needs WP12a's Lua side
and `omarchy restart shell` after the plugin update (the shell caches plugin JS).

1. [ ] After the shell restart `~/.local/state/omaplace/plans.lua` exists and lists the plan scenes; the shell log has no
   `reload_plans` warning.
2. [ ] Edit a plan's layout in `scenes.toml` by hand and save: plans.lua changes within a second.
3. [ ] `omaplace open <plan>` on a zone plan whose desktop is tiled: the desktop turns floating (set command, or the
   toggle after focusing it), then the apps land in their zones. A tiled plan on a tiled desktop presses nothing.
4. [ ] First move after a fresh login (Lua sends the notification): move a planned window
   to another desktop by hand: one notification with an "Update plan" button. Press it:
   `scenes.toml` has the new desktop (single-window plan) and a notification says `plan <name> updated`.
5. [ ] Move a planned window to another zone, then focus another window: one notification; pressing it writes the zone.
6. [ ] A second and third move in a row each give one notification (Lua sends each).
7. [ ] Tick "open at login" on one plan, log out and in: that plan opens once. `omarchy restart shell`: it does not
   open again (`login-done-<sig>` is in the runtime folder).

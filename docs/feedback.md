# Feedback from daily use

Things Felipe finds while using omaplace. One row per item. New items go at the bottom. When an item is done, set
its status to the version that fixes it.

| # | Date | Where | What Felipe saw | What we know | Status |
|---|------|-------|-----------------|--------------|--------|
| 1 | 2026-11-22 | App pickers (Desktops page, scenes) | Two apps with the same name (the Herdr terminal UI and the Herdr app) look the same in the list. You cannot tell which one is which. | The two launcher entries have the same `Name` but a different icon, comment and window class. Idea: when two apps share a name, show a short hint after the name (for example "Herdr, terminal" and "Herdr, app", from the class or the comment), and show each app's own icon | open |
| 2 | 2026-11-22 | Desktops page, plans, scene runs | Omarchy already has a layout per desktop (here desktop 1 is floating, the others tiled, the Omarchy default). omaplace should read that and fit the apps to it. | omaplace reads a desktop's mode only from its windows (Omarchy's floating tag on them). An empty desktop reads as "no mode", so its card badge and a run use the plan's layout instead. Omarchy keeps the real mode per desktop (`omarchy-hyprland-workspace-layout-current <n>`, and its saved layout files). Idea: read that for every desktop (async, never a blocking hyprctl), show it on the card, offer layouts that fit it first, and never switch a desktop's mode without asking | open |
| 3 | 2026-11-22 | Settings window | A click outside the settings window closes it, and you have to open it again. It should stay open, like a normal floating window. | The settings are an Omarchy shell panel, and a shell panel closes when it loses focus. omadials solved this with its own settings app (a real window). Idea: the same for omaplace: a normal window that stays open, floats, and can sit next to the apps you arrange | open |

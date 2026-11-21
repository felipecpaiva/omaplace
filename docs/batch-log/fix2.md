# fix2 batch log: review findings in the scene engine

## What changed
- `omaplace.lua`: `plan.expiry_s` is clamped to 1..600 s.
- A put is counted as pending only after its settle timer exists. Each run also has one deadline (expiry + settle + 2 s) that gives up what is left and ends the run as partial (`timeout`).
- A tiled run with two or more placed windows waits `settle_ms` before it reads positions to reorder (Omarchy re-arranges about 1 s after the last window opens). The reorder only runs on workspaces whose `tiled_layout` is `dwindle`; scrolling or unknown layouts are left alone.
- A put timer for a run that already ended moves nothing.
- Plan files over 1 MB are refused (`bad_plan`).
- With no `XDG_RUNTIME_DIR`, one log line, and `open`, `open_file` and `capture` return `nil, "no_runtime"` (no /tmp fallback).
- `shellquote.join({})` returns `nil, "empty"`; the slot fails as `bad_launch`.
- `tickets.claim` expires late slots first, so a late window cannot take an expired slot.

## Side effect
A tiled run now ends about `settle_ms` later than before (only when it placed two or more windows).

## Not checked live
The scrolling-layout skip and the `tiled_layout` field value `"dwindle"` come from the Hyprland stubs and the fake, not a live session.

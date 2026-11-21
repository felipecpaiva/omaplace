-- Put one window on a workspace and at a rect (design 4.3, research 02 (e)). Thin hl layer: it decides nothing
-- about where a window goes. Pattern from omagnet's `put`: leave fullscreen first, resize before move (a floating
-- resize is centre anchored), check the size after 40 ms, set it again at most twice, stop when the app refuses.
-- Every wait is a one-shot hl.timer; nothing repeats.
local M = {}

M.verify_ms = 40
M.unfullscreen_ms = 60
M.max_retries = 2

local function round(v) return math.floor(v + 0.5) end

local function find(address)
  for _, w in ipairs(hl.get_windows()) do
    if w.address == address then return w end
  end
end
M.find = find

-- Hyprland's window selector, the form Omarchy's own dispatches use.
local function sel(w) return "address:" .. tostring(w.address) end
M.sel = sel

local function xy(v)
  if type(v) ~= "table" then return 0, 0 end
  return tonumber(v.x or v[1]) or 0, tonumber(v.y or v[2]) or 0
end

-- Send `window` to workspace `id`. silent = true keeps the view where it is; false follows the window there
-- (and focuses the workspace when the window is already on it). Returns true when the window was moved.
function M.to_workspace(window, id, silent)
  local here = window.workspace and window.workspace.id
  if here == id then
    if not silent then hl.dispatch(hl.dsp.focus({ workspace = tostring(id) })) end
    return false
  end
  hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = not silent, window = sel(window) }))
  return true
end

-- omagnet's shadow fix, if omagnet is loaded (looked up now, never at load).
function M.fit_shadow_if_present(window)
  local om = rawget(_G, "omagnet")
  if type(om) == "table" and type(om.fit_shadow) == "function" then pcall(om.fit_shadow, window) end
end

-- A timer body that raises would be lost inside Hyprland; turn it into done(false, "error").
local function later(ms, fn, done)
  hl.timer(function()
    local ok, err = pcall(fn)
    if not ok then print("omaplace: place failed: " .. tostring(err)); done(false, "error") end
  end, { type = "oneshot", timeout = ms })
end

local function attempt(address, r, tries, last, done)
  local w = find(address)
  if not (w and w.floating) then return done(false, "not_floating") end
  local want_w, want_h = round(r.w), round(r.h)
  hl.dispatch(hl.dsp.window.resize({ x = want_w, y = want_h, relative = false, window = sel(w) }))
  hl.dispatch(hl.dsp.window.move({ x = round(r.x), y = round(r.y), relative = false, window = sel(w) }))
  later(M.verify_ms, function()
    local now = find(address)
    if not now then return done(false, "gone") end
    local got_w, got_h = xy(now.size)
    got_w, got_h = round(got_w), round(got_h)
    if got_w == want_w and got_h == want_h then
      M.fit_shadow_if_present(now)
      return done(true)
    end
    -- unchanged since the last try: the app refuses this size, so stop
    if tries >= M.max_retries or (last and last[1] == got_w and last[2] == got_h) then return done(false, "size_refused") end
    attempt(address, r, tries + 1, { got_w, got_h }, done)
  end, done)
end

-- Put `window` at rect_px {x, y, w, h} (logical pixels). done(ok, reason) is called once, later.
function M.put(window, rect_px, done)
  done = done or function() end
  local once = false
  local function finish(ok, reason)
    if once then return end
    once = true
    local fine, err = pcall(done, ok, reason)
    if not fine then print("omaplace: place callback failed: " .. tostring(err)) end
  end
  local address = window.address
  local fs = math.tointeger(window.fullscreen) or 0
  if fs ~= 0 then
    -- a maximized or fullscreen window refuses a move
    hl.dispatch(hl.dsp.window.fullscreen({ mode = fs == 1 and "maximized" or "fullscreen", action = "unset", window = sel(window) }))
    later(M.unfullscreen_ms, function() attempt(address, rect_px, 0, nil, finish) end, finish)
    return
  end
  attempt(address, rect_px, 0, nil, finish)
end

return M

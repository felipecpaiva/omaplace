-- omaplace: placement rules for Omarchy (design 6.1). The only file that calls hl or reads files.
-- Load:  pcall(dofile, <plugin folder>/lua/omaplace.lua)   Settings: ~/.config/omaplace/config.toml
-- Idle cost: no timer is armed until a monitor event arrives, and then only one one-shot (500 ms debounce).
-- shortcut: Hyprland's timer handle may have no cancel, so a re-armed debounce is a generation number: the old
-- timer still fires once and does nothing. Upgrade if hl.timer gets a documented stop.
local M = { version = "0.1.0" }

local dir = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
local Config = dofile(dir .. "/config.lua")
local Monitors = dofile(dir .. "/monitors.lua")
local Slots = dofile(dir .. "/slots.lua")
local Rules = dofile(dir .. "/rules.lua")

M.debounce_ms = 500
M.applied = {} -- spec names declared so far, so a vanished rule can be switched off
M.enabled = {} -- spec name -> enabled flag, for status()
M.settings = Config.load("").settings
M.rules = {}

-- The previous load of this file (a config reload runs it again in the same Lua state) hands over what it declared.
local old = rawget(_G, "omaplace")
local bound = type(old) == "table" and old._bound == true
if type(old) == "table" and type(old._m) == "table" and type(old._m.applied) == "table" then M.applied = old._m.applied end

local function log(text) print("omaplace: " .. tostring(text)) end

local function config_path() return (os.getenv("HOME") or "") .. "/.config/omaplace/config.toml" end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function load_config()
  local cfg = Config.load(read_file(config_path()) or "")
  for _, w in ipairs(cfg.warnings) do log("config: " .. w) end
  M.settings, M.rules = cfg.settings, cfg.rules
end

local function focused_of(live)
  for _, m in ipairs(live) do
    if m.focused then return m end
  end
end

-- Declare every rule again under its own name (hl.window_rule replaces in place) and switch off the ones that went.
function M.rebuild()
  local ok, live = pcall(hl.get_monitors)
  if not ok or type(live) ~= "table" then return nil, "no monitors" end
  local slots = Slots.with(rawget(_G, "o"))
  local specs, vanished = Rules.build(
    M.rules, live, Monitors.resolve, slots.workspace_id, focused_of(live), M.applied, M.settings.missing_monitor_rule)
  M.enabled = {}
  M.applied = {}
  for _, spec in ipairs(specs) do
    hl.window_rule(spec)
    M.enabled[spec.name] = spec.enabled
    M.applied[#M.applied + 1] = spec.name
  end
  for _, name in ipairs(vanished) do hl.window_rule({ name = name, enabled = false }) end
  return true
end

function M.reload_config()
  local ok, err = pcall(function() load_config(); assert(M.rebuild()) end)
  if not ok then log("reload failed: " .. tostring(err)); return nil, tostring(err) end
  return true
end

function M.status()
  local rules = {}
  for _, name in ipairs(M.applied) do rules[#rules + 1] = { name = name, enabled = M.enabled[name] == true } end
  return { version = M.version, rules = rules }
end

-- Many monitor events in a row (plugging a dock sends several) become one rebuild, 500 ms after the last.
M.debounce_gen = 0
local function rebuild_soon()
  M.debounce_gen = M.debounce_gen + 1
  local gen = M.debounce_gen
  if M.timer and M.timer.cancel then pcall(M.timer.cancel) end
  M.timer = hl.timer(function()
    M.timer = nil
    if gen ~= M.debounce_gen then return end
    local ok, err = pcall(M.rebuild)
    if not ok then log("rebuild failed: " .. tostring(err)) end
  end, { type = "oneshot", timeout = M.debounce_ms })
end
M.rebuild_soon = rebuild_soon

-- _m and _bound are internal: the next load of this file reads them (see above).
_G.omaplace = { version = M.version, reload_config = M.reload_config, status = M.status, _m = M, _bound = true,
  _rebuild_soon = rebuild_soon }

local ok, err = pcall(function() load_config(); assert(M.rebuild()) end)
if not ok then log("load failed: " .. tostring(err)) end

-- Handlers go on once per Lua state; they call through _G.omaplace so a reloaded copy of this file is the one that runs.
if not bound then
  for _, event in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed", "monitor.focused" }) do
    hl.on(event, function()
      local handled, e = pcall(function() _G.omaplace._rebuild_soon() end)
      if not handled then log(event .. " handler failed: " .. tostring(e)) end
    end)
  end
end

return M

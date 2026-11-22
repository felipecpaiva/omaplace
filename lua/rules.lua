-- Turn the [rule.<name>] tables into window rule specs for hl.window_rule (design 6.1). Pure: no hl, no files.
local R = {}

local PREFIX = "omaplace-rule-"

-- The workspace text for a rule: a plain id switches to it, "silent" opens the window there without switching.
local function workspace_text(id, follow)
  return follow and tostring(id) or (tostring(id) .. " silent")
end

-- One rule to one spec. A rule that cannot be placed (no app, monitor not found, no workspace id) is disabled,
-- never an error: the app then opens where Omarchy would open it.
local function spec_for(name, rule, live, resolve, ws_id, focused, policy)
  local spec = { name = PREFIX .. name, match = { initial_class = rule.app }, enabled = false }
  if rule.enabled == false or (rule.app or "") == "" then return spec end

  local monitor
  if (rule.monitor or "") == "" then
    monitor = focused
  else
    monitor = resolve({ identity = rule.monitor }, live, policy)
  end
  if not monitor then return spec end

  local id = ws_id(monitor, rule.slot)
  if not id then return spec end
  spec.workspace = workspace_text(id, rule.follow)
  spec.enabled = true
  return spec, id, monitor.name
end

-- build(cfg_rules, live_monitors, resolve, ws_id, focused, previous, policy)
--   cfg_rules  name -> rule table, as config.load returns
--   resolve    monitors.resolve; ws_id(monitor, slot) from slots.with(o).workspace_id
--   focused    the focused monitor now (used when a rule has no monitor), or nil
--   previous   optional list of spec names from the last build
--   policy     missing_monitor_rule, "skip" (default) or "focused"
-- Returns specs sorted by name, the names in `previous` that are not in `specs` any more, and homes: workspace id ->
-- monitor name of every enabled rule (the glue moves a rule's desktop to its monitor, Place.home).
function R.build(cfg_rules, live, resolve, ws_id, focused, previous, policy)
  local names = {}
  for name in pairs(cfg_rules or {}) do names[#names + 1] = name end
  table.sort(names)

  local specs, current, homes = {}, {}, {}
  for _, name in ipairs(names) do
    local spec, id, mon_name = spec_for(name, cfg_rules[name], live, resolve, ws_id, focused, policy or "skip")
    if id then homes[id] = mon_name end
    specs[#specs + 1] = spec
    current[spec.name] = true
  end

  local vanished = {}
  for _, old in ipairs(previous or {}) do
    if not current[old] then vanished[#vanished + 1] = old end
  end
  table.sort(vanished)
  return specs, vanished, homes
end

return R

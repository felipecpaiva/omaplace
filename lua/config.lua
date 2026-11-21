-- omaplace config.toml: parse the small subset (comments, [sections], key = true | 123 | 1.5 | "text"),
-- apply defaults (design 7.5), read [rule.<name>] and [strategy.<name>]. Pure: no hl, no files.
-- shortcut: no arrays, no inline tables, no escaped quotes inside a string. Upgrade if a setting needs them.
local C = {}

-- The one defaults table for the top level. kind: bool, int (min), enum (list), string.
C.settings_spec = {
  schema = { default = 1, kind = "int", min = 1 },
  missing_monitor_scene = { default = "focused", kind = "enum", values = { "focused", "skip" } },
  missing_monitor_rule = { default = "skip", kind = "enum", values = { "focused", "skip" } },
  existing_default = { default = "move", kind = "enum", values = { "move", "new" } },
  expiry_seconds = { default = 20, kind = "int", min = 1 },
  settle_ms = { default = 1100, kind = "int", min = 0 },
  launch_tick_ms = { default = 150, kind = "int", min = 10 },
  session = { default = "on", kind = "enum", values = { "on", "off" } },
  session_debounce_s = { default = 15, kind = "int", min = 1 },
  session_keep = { default = 5, kind = "int", min = 1 },
  request_timeout_s = { default = 60, kind = "int", min = 1 },
  restore_at_login = { default = "off", kind = "enum", values = { "off", "ask", "auto" } },
  app_memory = { default = "scene", kind = "enum", values = { "scene", "last_place", "auto" } },
  context_quiet_ms = { default = 2000, kind = "int", min = 0 },
  tiled_order = { default = true, kind = "bool" },
  ignore = { default = "", kind = "string" },
}

C.rule_spec = {
  app = { default = "", kind = "string" },
  monitor = { default = "", kind = "string" },
  slot = { default = 1, kind = "int", min = 1, max = 10 },
  follow = { default = false, kind = "bool" },
  enabled = { default = true, kind = "bool" },
}

C.strategy_names = { "desktop", "webapp", "terminal", "tui", "context", "place_only", "command", "skip" }

C.strategy_spec = {
  match = { default = "", kind = "string" },
  use = { default = "desktop", kind = "enum", values = C.strategy_names },
  launch_context = { default = "", kind = "string" },
  context = { default = "none", kind = "enum", values = { "profile", "folder", "none" } },
}

local function value(v)
  if v == "true" then return true elseif v == "false" then return false end
  local s = v:match('^"(.*)"$')
  if s then
    if s:find('"', 1, true) then return nil end -- the subset has no escapes, so an inner quote is unreadable
    return s
  end
  -- plain decimals only: tonumber alone would also accept 0x10 and 1e999 (infinity)
  if v:match("^-?%d+%.?%d*$") then return tonumber(v) end
  return nil -- not a value we know
end

-- Cut a trailing comment: a `#` starts one only outside a double quoted string, so "Make Model #2" survives.
function C.strip_comment(line)
  local in_string = false
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == '"' then in_string = not in_string
    elseif ch == "#" and not in_string then return (line:sub(1, i - 1):gsub("%s+$", "")) end
  end
  return line
end

-- Returns a list of { section = <header text or "">, key =, value =, line = } and a list of warnings.
-- The header text is kept raw; `rule.x` and `strategy.x` are split later.
function C.parse(text)
  local entries, warnings = {}, {}
  local section, valid = "", true
  local n = 0
  for raw in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local line = C.strip_comment(raw)
    if line:match("%S") then
      local name = line:match("^%s*%[([^%[%]]*)%]%s*$")
      if name then
        section, valid = name, name:match("^[%w_%-]+$") ~= nil or name:match("^[%w_%-]+%.[%w_%-]+$") ~= nil
        if not valid then warnings[#warnings + 1] = string.format("line %d: section [%s] is not a valid name, its keys are ignored", n, name) end
      else
        local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
        local parsed = k and value(v)
        if parsed == nil then
          warnings[#warnings + 1] = string.format("line %d: cannot read this line, ignored", n)
        elseif valid then
          entries[#entries + 1] = { section = section, key = k, value = parsed, line = n }
        end
      end
    end
  end
  return entries, warnings
end

-- Check one value against its spec. Returns the value, or the default plus a warning text.
local function check(spec, v)
  if spec.kind == "bool" then
    if type(v) == "boolean" then return v end
  elseif spec.kind == "string" then
    if type(v) == "string" then return v end
  elseif spec.kind == "int" then
    if math.type(v) == "float" and v == math.floor(v) then v = math.tointeger(v) end
    if math.type(v) == "integer" and v >= spec.min and (not spec.max or v <= spec.max) then return v end
  elseif spec.kind == "enum" then
    for _, allowed in ipairs(spec.values) do
      if v == allowed then return v end
    end
  end
  local shown = type(spec.default) == "string" and string.format("%q", spec.default) or tostring(spec.default)
  return spec.default, "bad value, using " .. shown
end

local function fresh(spec)
  local t = {}
  for k, s in pairs(spec) do t[k] = s.default end
  return t
end

-- Fill `target` from `entries` using `spec`. Unknown keys go to `extra` (created on first use).
local function apply(target, spec, entries, label, warnings)
  local extra
  for _, e in ipairs(entries) do
    local s = spec[e.key]
    if s then
      local v, bad = check(s, e.value)
      if bad then warnings[#warnings + 1] = string.format("line %d: %s %s: %s", e.line, label, e.key, bad) end
      target[e.key] = v
    else
      extra = extra or {}
      extra[e.key] = e.value
    end
  end
  return extra
end

-- Text to config. Always returns a complete table; problems are in `warnings`.
function C.load(text)
  local entries, warnings = C.parse(text)
  local by_section, order = {}, {}
  for _, e in ipairs(entries) do
    if not by_section[e.section] then by_section[e.section] = {}; order[#order + 1] = e.section end
    local list = by_section[e.section]
    list[#list + 1] = e
  end
  local cfg = { schema = 1, settings = fresh(C.settings_spec), rules = {}, strategies = {}, warnings = warnings }
  local extra = apply(cfg.settings, C.settings_spec, by_section[""] or {}, "setting", warnings)
  cfg.schema = cfg.settings.schema
  for _, sec in ipairs(order) do
    local kind, name = sec:match("^(%a+)%.(.+)$")
    if sec == "" then
      -- done above
    elseif kind == "rule" or kind == "strategy" then
      local spec = kind == "rule" and C.rule_spec or C.strategy_spec
      local item = fresh(spec)
      local item_extra = apply(item, spec, by_section[sec], kind .. " " .. name, warnings)
      if item_extra then item.extra = item_extra end
      if kind == "rule" and item.app == "" then
        warnings[#warnings + 1] = "rule " .. name .. " has no app, it matches nothing"
      elseif kind == "strategy" and item.match == "" then
        warnings[#warnings + 1] = "strategy " .. name .. " has no match, it matches nothing"
      end
      cfg[kind == "rule" and "rules" or "strategies"][name] = item
    else
      extra = extra or {}
      for _, e in ipairs(by_section[sec]) do extra[sec .. "." .. e.key] = e.value end
    end
  end
  if extra then cfg.extra = extra end
  return cfg
end

return C

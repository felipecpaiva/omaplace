-- Desktop plans (design 14.7, 14.8): the checked contents of ~/.local/state/omaplace/plans.lua (written by the service,
-- js/PlansFile.js), the lookup a new window goes through, the zone drift check (D23), the login list and the desktops
-- answer. Pure: no hl, no files, no clock. The glue loads the file text and passes the table in.
local M = {}

M.MAX_PLANS = 100
M.MAX_WINDOWS = 64
M.TOLERANCE = 0.02 -- D23: 2 percent of the usable area
local SCENE_RE = "^[a-z0-9_%-]+$" -- js/SceneStore.js SCENE_NAME_RE

local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end

local function clean_rect(r)
  if type(r) ~= "table" then return nil end
  for i = 1, 4 do
    if not finite(r[i]) then return nil end
  end
  if r[3] <= 0 or r[4] <= 0 then return nil end
  return { r[1], r[2], r[3], r[4] }
end

local function key(class, context)
  local ctx = type(context) == "string" and context or ""
  return ctx == "" and class or (class .. "\n" .. ctx)
end

-- A bad window keeps its place in the list (window i is scene.windows[i]) but never snaps.
local function clean_window(w)
  local bad = type(w) ~= "table" -- plain table: a plan window from the file
  if bad or type(w.class) ~= "string" or w.class == "" then return { class = "", context = "", snap = false } end
  local rect = clean_rect(w.rect)
  return { class = w.class, context = type(w.context) == "string" and w.context or "", rect = rect,
    floating = w.floating == true, snap = w.snap == true and rect ~= nil, fullscreen = math.tointeger(w.fullscreen) or 0 }
end

local function clean_plan(p)
  if type(p) ~= "table" then return nil, "not a table" end
  if type(p.scene) ~= "string" or #p.scene > 40 or not p.scene:match(SCENE_RE) then return nil, "bad scene name" end
  local slot = math.tointeger(p.home_slot)
  if not slot or slot < 1 or slot > 10 then return nil, "home_slot must be 1 to 10" end
  if p.home_monitor ~= nil and type(p.home_monitor) ~= "string" then return nil, "bad home_monitor" end
  if type(p.windows) ~= "table" or #p.windows > M.MAX_WINDOWS then return nil, "bad windows" end
  local out = { scene = p.scene, home_monitor = p.home_monitor or "", home_slot = slot,
    layout = type(p.layout) == "string" and p.layout or "", mode = type(p.mode) == "string" and p.mode or "",
    open_at_login = p.open_at_login == true, windows = {} }
  for i, w in ipairs(p.windows) do out.windows[i] = clean_window(w) end
  return out
end

-- validate(t): { plans, skipped = { reason, ... }, keys } from the table plans.lua returned, or nil and a reason.
-- keys[class + context] = { plan, index } for the first window of that key, or false when two plans hold it.
function M.validate(t)
  if type(t) ~= "table" or type(t.plans) ~= "table" then return nil, "not a plans table" end
  local out = { plans = {}, skipped = {}, keys = {} }
  for i, p in ipairs(t.plans) do
    if #out.plans >= M.MAX_PLANS then
      out.skipped[#out.skipped + 1] = "plans after " .. M.MAX_PLANS .. ": too many"
      break
    end
    local plan, why = clean_plan(p)
    if plan then out.plans[#out.plans + 1] = plan else out.skipped[#out.skipped + 1] = "plan " .. i .. ": " .. why end
  end
  for _, plan in ipairs(out.plans) do
    local seen = {}
    for i, w in ipairs(plan.windows) do
      local k = w.class ~= "" and key(w.class, w.context)
      if k and not seen[k] then
        seen[k] = true
        if out.keys[k] == nil then out.keys[k] = { plan = plan, index = i } else out.keys[k] = false end
      end
    end
  end
  return out
end

-- True when some plan holds this class and context (snapped or not): app memory then stays out of the way (D20).
function M.held(set, class, context)
  return type(set) == "table" and type(class) == "string" and set.keys[key(class, context)] ~= nil
end

-- The plan, window index and window a new window of this class and context snaps to, or nil: not held, held by two
-- plans (ambiguous, 14.7), or snap = false.
function M.lookup(set, class, context)
  if type(set) ~= "table" or type(class) ~= "string" then return nil end
  local e = set.keys[key(class, context)]
  if not e then return nil end
  local w = e.plan.windows[e.index]
  if not w.snap then return nil end
  return e.plan, e.index, w
end

-- Scene names of the plans ticked "open at login".
function M.login_plans(set)
  local out = {}
  for _, p in ipairs(type(set) == "table" and set.plans or {}) do
    if p.open_at_login then out[#out + 1] = p.scene end
  end
  return out
end

-- D23: is `rect` (fractions of the usable area) more than `tol` away from `want` on any edge or size?
function M.drifted(rect, want, tol)
  if type(rect) ~= "table" or type(want) ~= "table" then return false end
  tol = tol or M.TOLERANCE
  for i = 1, 4 do
    if math.abs((tonumber(rect[i]) or 0) - (tonumber(want[i]) or 0)) > tol then return true end
  end
  return false
end

-- The desktops answer (14.8): { monitors = { { identity, name, focused, slots = { { slot, workspace } } } } }, mirrors
-- left out, by connector name. workspace_id(monitor, slot) and identity_of(monitor, all) come from slots and monitors.
function M.desktops(live, workspace_id, identity_of)
  local mons = {}
  for _, m in ipairs(live or {}) do
    if not m.is_mirror then
      local slots = {}
      for s = 1, 10 do
        local ok, id = pcall(workspace_id, m, s)
        if ok and math.type(id) == "integer" then slots[#slots + 1] = { slot = s, workspace = id } end
      end
      mons[#mons + 1] = { identity = identity_of(m, live), name = m.name, focused = m.focused == true, slots = slots }
    end
  end
  table.sort(mons, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return { monitors = mons }
end

return M

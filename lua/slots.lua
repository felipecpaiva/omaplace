-- The only code that knows how desktops are numbered (D50). Three models, in this order:
--   rules        Hyprland's workspace rules bind workspaces to monitors (hyprmoncfg writes them, or the user does):
--                desktop N of a monitor is the Nth workspace its rules name (laptop 1 to 3, HDMI 4 to 6, ...).
--                `plan` = { monitors = { [rule monitor] = { ids, sorted } } }, read by the service from
--                `hyprctl workspacerules -j`; a rule monitor is a name ("DP-1") or "desc:<description>".
--   per_monitor  Omarchy's own model: 10 slots per monitor block (only while Omarchy's workspaces are on).
--   global       plain ids 1..10.
-- `o` is Omarchy's module table, passed in; nothing is read from globals.
local M = {}

local SLOTS = 10

-- Returns { mode, workspace_id, slot_of } bound to `o` and `plan` (both may be nil).
function M.with(o, plan)
  local ws = type(o) == "table" and o.workspaces or nil
  -- hyprmoncfg turns Omarchy's numbering off (enabled = false) and leaves workspace_id in place: not per monitor then
  local per_monitor = type(ws) == "table" and type(ws.workspace_id) == "function" and ws.enabled ~= false -- plain table: Omarchy module
  local lists = type(plan) == "table" and type(plan.monitors) == "table" and plan.monitors or {}
  local has_rules = next(lists) ~= nil
  local S = {}

  local function list_of(monitor)
    local tm = type(monitor)
    if tm ~= "table" and tm ~= "userdata" then return nil end -- Hyprland hands monitors over as userdata
    return lists[monitor.name] or lists["desc:" .. tostring(monitor.description or "")]
  end

  function S.mode() return has_rules and "rules" or per_monitor and "per_monitor" or "global" end

  -- The workspace id of `slot` (1..10) on `monitor`. Returns nil and a reason when it cannot say.
  function S.workspace_id(monitor, slot)
    if math.type(slot) ~= "integer" or slot < 1 or slot > SLOTS then return nil, "slot must be 1 to 10" end
    local list = has_rules and list_of(monitor)
    if list then
      if math.type(list[slot]) == "integer" then return list[slot] end
      return nil, "that monitor has " .. #list .. " desktops"
    end
    if not per_monitor then return slot end
    local ok, id = pcall(ws.workspace_id, monitor, slot)
    if not ok then return nil, "workspace_id failed: " .. tostring(id) end
    if math.type(id) ~= "integer" then return nil, "workspace_id gave no id" end
    return id
  end

  -- The slot (1..10) of a workspace id. Ids outside the model (below 1) give nil.
  function S.slot_of(id)
    if math.type(id) ~= "integer" or id < 1 then return nil end
    for _, list in pairs(lists) do
      for i, x in ipairs(list) do if x == id then return i end end
    end
    if not per_monitor then return id <= SLOTS and id or ((id - 1) % SLOTS) + 1 end
    return ((id - 1) % SLOTS) + 1
  end

  return S
end

return M

-- The only code that knows Omarchy's workspace model: 10 slots per monitor block (per-monitor mode),
-- or plain ids 1..10 (global mode). `o` is Omarchy's module table, passed in; nothing is read from globals.
local M = {}

local SLOTS = 10

-- Returns { mode, workspace_id, slot_of } bound to `o` (nil is allowed and means global mode).
function M.with(o)
  local ws = type(o) == "table" and o.workspaces or nil
  local per_monitor = type(ws) == "table" and type(ws.workspace_id) == "function"
  local S = {}

  function S.mode() return per_monitor and "per_monitor" or "global" end

  -- The workspace id of `slot` (1..10) on `monitor`. Returns nil and a reason when it cannot say.
  function S.workspace_id(monitor, slot)
    if math.type(slot) ~= "integer" or slot < 1 or slot > SLOTS then return nil, "slot must be 1 to 10" end
    if not per_monitor then return slot end
    local ok, id = pcall(ws.workspace_id, monitor, slot)
    if not ok then return nil, "workspace_id failed: " .. tostring(id) end
    if math.type(id) ~= "integer" then return nil, "workspace_id gave no id" end
    return id
  end

  -- The slot (1..10) of a workspace id. Ids outside the model (below 1) give nil.
  function S.slot_of(id)
    if math.type(id) ~= "integer" or id < 1 then return nil end
    if not per_monitor then return id end
    return ((id - 1) % SLOTS) + 1
  end

  return S
end

return M

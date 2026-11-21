-- Plain Lua check:  lua lua/tests/test_monitors.lua
local dir = arg[0]:match("^(.*)/") or "."
local M = dofile(dir .. "/../monitors.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local function mon(name, extra)
  local m = { name = name, description = "Example Corp EX27 SN1", make = "Example Corp", model = "EX27", serial = "SN1",
    width = 2560, height = 1440, scale = 1, transform = 0, is_mirror = false, focused = false }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end
local function panel(name)
  return mon(name or "eDP-1", { description = "Example Panel LP1", make = "Example Panel", model = "LP1",
    serial = "", width = 2880, height = 1800, scale = 2 })
end
-- a monitor that matches nothing else by make, model or description
local function loner(name, tag, extra)
  local m = mon(name, { make = tag, model = tag, serial = "", description = tag })
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- fingerprint: identity, hash, internal
local a = mon("DP-1")
local fp = M.fingerprint(a, { a })
eq(fp.identity, "Example Corp EX27 SN1", "identity is the description")
eq(fp.serial_hash ~= "" and fp.serial_hash ~= "SN1", true, "hash is not the serial")
eq(#fp.serial_hash, 8, "hash is 8 hex digits")
eq(fp.serial_hash:match("^%x+$") ~= nil, true, "hash is hex")
eq(M.fingerprint(mon("DP-1"), {}).serial_hash, fp.serial_hash, "same serial, same hash")
eq(M.fingerprint(mon("DP-1", { serial = "SN2" }), {}).serial_hash ~= fp.serial_hash, true, "other serial, other hash")
eq(fp.internal, false, "external")
eq(fp.last_connector, "DP-1", "connector kept")
eq(M.fingerprint(mon("DP-1", { description = "" }), {}).identity, "DP-1", "no description: the connector")
local p = M.fingerprint(panel(), { panel() })
eq(p.internal, true, "eDP is internal")
eq(p.serial_hash, "", "empty serial, empty hash")
eq(M.fingerprint(mon("LVDS-1"), {}).internal, true, "LVDS")
eq(M.fingerprint(mon("DSI-1"), {}).internal, true, "DSI")
eq(M.fingerprint(mon("HDMI-A-1"), {}).internal, false, "HDMI")

-- twins: numbered by connector order whatever the list order; a mirror is not counted
local t1, t2 = mon("DP-2", { serial = "" }), mon("DP-1", { serial = "" })
local list = { t1, t2 }
eq(M.fingerprint(t2, list).identity, "Example Corp EX27 SN1", "first twin is plain")
eq(M.fingerprint(t1, list).identity, "Example Corp EX27 SN1 #2", "second twin gets #2")
local mirror = mon("DP-0", { is_mirror = true })
eq(M.fingerprint(t1, { t1, t2, mirror }).identity, "Example Corp EX27 SN1 #2", "a mirror is not counted")

-- step 1: identity, for a twin and across a port change
local m, how = M.resolve(M.fingerprint(t1, list), list, "skip")
eq(m, t1, "twin found by identity")
eq(how, "identity", "how: identity")
local at_dp5 = mon("DP-5", { serial = "" })
m, how = M.resolve(M.fingerprint(at_dp5, { at_dp5 }), { mon("HDMI-A-2", { serial = "" }) }, "skip")
eq(how, "identity", "port change keeps identity")

-- step 2: serial, when only the description changed (a firmware rename)
local renamed = mon("DP-1", { description = "Example Corp EX27 (new firmware)" })
m, how = M.resolve(fp, { renamed, mon("DP-2", { serial = "OTHER", description = "x" }) }, "skip")
eq(how, "serial", "how: serial")
eq(m, renamed, "serial picks the right one")

-- an empty serial never matches by serial
local blank = M.fingerprint(mon("DP-1", { serial = "", description = "old" }), {})
m, how = M.resolve(blank, { mon("DP-1", { serial = "", description = "new" }), mon("DP-2", { serial = "", description = "new" }) }, "skip")
eq(how ~= "serial", true, "never serial for blank")
eq(how ~= "model", true, "two of that model are not step 3")

-- step 3: model, only when exactly one monitor of that model is live
local other_serial = mon("DP-1", { serial = "SN9", description = "Example Corp EX27 SN9" })
m, how = M.resolve(fp, { other_serial, panel() }, "skip")
eq(how, "model", "how: model")
eq(m, other_serial, "model picks the only one")
m, how = M.resolve(fp, { other_serial, mon("DP-2", { serial = "SN8", description = "Example Corp EX27 SN8" }) }, "skip")
eq(how ~= "model", true, "two of that model: not step 3")

-- step 4: internal, even when the panel model changed (a swapped panel)
local old_panel = M.fingerprint(panel(), {})
local new_panel = panel("eDP-1")
new_panel.description, new_panel.model = "Other Panel", "LP2"
m, how = M.resolve(old_panel, { mon("DP-1"), new_panel }, "skip")
eq(how, "internal", "how: internal")
eq(m, new_panel, "internal picks the laptop panel")
local wants_panel = M.fingerprint(loner("DP-1", "Q"), {})
wants_panel.internal = true
m, how = M.resolve(wants_panel, { loner("DP-1", "Z", { width = 800, height = 600 }) }, "skip")
eq(how, "skip", "internal fingerprint, no panel live, nothing else like it")

-- step 5: shape (aspect within 2 percent, size within 10 percent), closest wins, rotation understood
local shaped = M.fingerprint(loner("DP-1", "A"), {})
local exact = loner("DP-1", "B")
local close = loner("DP-2", "C", { width = 2600, height = 1460 })
m, how = M.resolve(shaped, { close, exact }, "skip")
eq(how, "shape", "how: shape")
eq(m, exact, "closest shape wins")
m, how = M.resolve(shaped, { loner("DP-3", "D", { transform = 1, width = 1440, height = 2560 }) }, "skip")
eq(how, "shape", "a rotated monitor has the same shape")
m, how = M.resolve(shaped, { loner("DP-4", "E", { width = 1920, height = 1200 }) }, "skip")
eq(how, "skip", "16:10 is not 16:9")
m, how = M.resolve(shaped, { loner("DP-4", "E", { width = 1280, height = 720 }) }, "skip")
eq(how, "skip", "same aspect, half the size: no match")

-- step 6: policy
local odd = loner("DP-9", "F", { width = 800, height = 600, focused = true })
local idle = loner("DP-8", "G", { width = 800, height = 600 })
m, how = M.resolve(shaped, { idle, odd }, "focused")
eq(how, "focused", "how: focused")
eq(m, odd, "the focused monitor")
m, how = M.resolve(shaped, { idle, odd }, "skip")
eq(m, nil, "skip: no monitor")
eq(how, "skip", "how: skip")
m, how = M.resolve(shaped, { idle }, "focused")
eq(how, "skip", "focused policy but none focused")

-- missing monitor: nothing live, or only a mirror, whatever the policy
for _, policy in ipairs({ "skip", "focused" }) do
  m, how = M.resolve(fp, {}, policy)
  eq(m, nil, "empty live list " .. policy)
  eq(how, "skip", "empty live list how " .. policy)
  m, how = M.resolve(fp, { mon("DP-1", { is_mirror = true, focused = true }) }, policy)
  eq(m, nil, "mirror only " .. policy)
end
m, how = M.resolve(nil, { mon("DP-1") }, "focused")
eq(how, "skip", "no fingerprint")

-- order matters: identity beats serial
m, how = M.resolve(fp, { mon("DP-1", { description = "renamed" }), mon("DP-2", { serial = "ZZ" }) }, "skip")
eq(how, "identity", "identity first")
eq(m.name, "DP-2", "identity monitor chosen over a serial match")

print("test_monitors ok (" .. checks .. " checks)")

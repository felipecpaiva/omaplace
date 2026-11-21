.pragma library
// One `hyprctl eval` call into the omaplace Lua module, written so its printed answer says what happened (WP8 fix).
// Pure: builds the Lua text and reads the answer. `hyprctl eval` prints what the chunk returns.

const CODES = ["ok", "no_lua", "busy", "bad_plan", "no_monitor", "no_runtime", "bad_path", "failed"]

// method: a name on _G.omaplace; args: Lua literals already encoded (LuaLiteral.encode); replyPath: a file in the runtime
// folder (encoded too). `hyprctl eval` prints only "ok", never what the chunk returns (checked live 2026-11-21), so the
// chunk writes its answer "omaplace:<code>" to replyPath: no_lua when the module is missing, ok when the call returned
// a value, else the error it returned. The service reads that file after hyprctl exits.
function wrap(method, args, replyPath) {
  if (!/^[a-z_]+$/.test(method)) throw new Error("LuaCall: bad method name")
  if (typeof replyPath !== "string" || replyPath === "") throw new Error("LuaCall: reply path needed")
  return "(function() local o = rawget(_G, \"omaplace\"); local a; " +
    "if type(o) ~= \"table\" then a = \"omaplace:no_lua\" else " +
    "local r, e = o." + method + "(" + (args || []).join(", ") + "); a = r and \"omaplace:ok\" or (\"omaplace:\" .. tostring(e)) end; " +
    "local f = io.open(" + replyPath + ", \"w\"); if f then f:write(a); f:close() end end)()"
}

// The code in the reply file's text, or "" when the output says nothing we know (then the caller waits as before).
// An error code Lua may add later reads as "failed".
function code(output) {
  const m = /omaplace:([a-z_]+)/.exec(String(output || ""))
  if (!m) return ""
  return CODES.indexOf(m[1]) === -1 ? "failed" : m[1]
}

// Like wrap(), for a call that returns data (WP12b, `desktops()`): the reply file holds "omaplace:ok", a line break, then
// the returned table as JSON, from a small encoder inside the chunk (the Lua module needs no export for it). A table with
// item 1, or an empty one, is an array. A call that returns no table writes its error. Read it back with code() and data().
const ENCODER = String.raw`local function enc(v) local t = type(v)
if t == "table" then local p = {}
if next(v) == nil or v[1] ~= nil then for i = 1, #v do p[i] = enc(v[i]) end return "[" .. table.concat(p, ",") .. "]" end
for k, x in pairs(v) do p[#p + 1] = enc(tostring(k)) .. ":" .. enc(x) end return "{" .. table.concat(p, ",") .. "}"
elseif t == "string" then return '"' .. (v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) .. '"'
elseif t == "number" and v == v and v ~= math.huge and v ~= -math.huge then return tostring(v)
elseif t == "boolean" then return tostring(v) end
return "null" end `

function wrapData(method, args, replyPath) {
  if (!/^[a-z_]+$/.test(method)) throw new Error("LuaCall: bad method name")
  if (typeof replyPath !== "string" || replyPath === "") throw new Error("LuaCall: reply path needed")
  return "(function() " + ENCODER + "local o = rawget(_G, \"omaplace\"); local a; " +
    "if type(o) ~= \"table\" then a = \"omaplace:no_lua\" else " +
    "local r, e = o." + method + "(" + (args || []).join(", ") + "); " +
    "if type(r) == \"table\" then a = \"omaplace:ok\\n\" .. enc(r) else a = \"omaplace:\" .. tostring(e or \"failed\") end end; " +
    "local f = io.open(" + replyPath + ", \"w\"); if f then f:write(a); f:close() end end)()"
}

// The JSON after the code line of a wrapData() reply, or null.
function data(output) {
  const text = String(output || "")
  const nl = text.indexOf("\n")
  if (code(text) !== "ok" || nl === -1) return null
  try { const v = JSON.parse(text.slice(nl + 1)); return v !== null && typeof v === "object" ? v : null } catch (e) { return null }
}

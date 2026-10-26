-- Pure: the crewswap.state payload. entries = {{id=<entity id>, controller=<name or ''>, free=bool}}.
-- Layout: UInt16 count, then per entry UInt16 id, String controller, Boolean free.
local M = {}

function M.encode(w, entries)
  w:WriteUInt16(#entries)
  for _, e in ipairs(entries) do
    w:WriteUInt16(e.id)
    w:WriteString(e.controller or '')
    w:WriteBoolean(e.free == true)
  end
end

function M.decode(r)
  local out = {}
  local n = r:ReadUInt16()
  for i = 1, n do
    local id = r:ReadUInt16()
    local controller = r:ReadString()
    local free = r:ReadBoolean()
    out[i] = { id = id, controller = controller, free = free }
  end
  return out
end

return M

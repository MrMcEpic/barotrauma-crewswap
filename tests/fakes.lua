-- Shared test doubles used across the test files.
local F = {}

-- A free, eligible crew bot. Override any field via `o`.
function F.view(o)
  local v = { id = 1, sid = 's1', alive = true, conscious = true, removed = false,
              crew = true, isAI = true, controller = nil, homeOf = nil, owner = nil, name = 'Bot' }
  for k, x in pairs(o or {}) do v[k] = x end
  return v
end

-- An eligible requester (in game, synced, has a campaign character, no blockers, never switched).
function F.requester(o)
  local r = { key = 'acct:A', inGame = true, synced = true, voluntarySpectator = false,
              traitor = false, inDialogue = false, lastSwitchAt = nil, hasHome = true }
  for k, x in pairs(o or {}) do r[k] = x end
  return r
end

-- A network message double: Write*/Read* for UInt16, String, Boolean and Single, backed by an array
-- of {t=type, v=value}. A read of the wrong type, or past the end, raises.
function F.buffer()
  local b = { data = {}, pos = 0 }
  local function writer(ty) return function(self, v) self.data[#self.data + 1] = { t = ty, v = v } end end
  local function reader(ty)
    return function(self)
      self.pos = self.pos + 1
      local e = self.data[self.pos]
      if e == nil then error('read past end (' .. ty .. ')', 2) end
      if e.t ~= ty then error('read ' .. ty .. ' but next is ' .. e.t, 2) end
      return e.v
    end
  end
  for _, ty in ipairs({ 'UInt16', 'String', 'Boolean', 'Single' }) do
    b['Write' .. ty] = writer(ty)
    b['Read' .. ty] = reader(ty)
  end
  return b
end

return F

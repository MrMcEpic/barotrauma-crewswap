-- core/grace.lua: the crew-down grace timer. While vanilla would end the round (everyone is down)
-- but Free crew still exists, the round is held open for GRACE seconds so someone can switch in.
local grace = {}

grace.GRACE = 120
grace.WARN_AT = 90

grace.MSG_START = '[CrewSwap] Everyone is down. Pick a crew member from the crew list within 2 minutes or the round ends.'
grace.MSG_WARN = '[CrewSwap] 30 seconds left to pick a crew member.'
grace.MSG_END = '[CrewSwap] Nobody switched in \xe2\x80\x94 the round will end.'

local G = {}
G.__index = G

function grace.new()
  return setmetatable({ elapsed = 0, active = false, said = {} }, G)
end

-- Returns mask (hold the round open this tick), announce (a chat line or nil).
function G:step(dt, vanillaDown, anyFree)
  if not (vanillaDown and anyFree) then
    self.elapsed, self.active, self.said = 0, false, {}
    return false, nil
  end
  local announce
  if not self.active then
    self.active = true
    self.said.start = true
    announce = grace.MSG_START
  end
  self.elapsed = self.elapsed + dt
  if self.elapsed >= grace.GRACE then
    if not self.said.fin then self.said.fin = true; announce = grace.MSG_END end
    return false, announce
  end
  if self.elapsed >= grace.WARN_AT and not self.said.warn then
    self.said.warn = true
    announce = grace.MSG_WARN
  end
  return true, announce
end

return grace

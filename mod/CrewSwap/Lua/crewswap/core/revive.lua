-- Pure: which dead crew members are kept in the roster instead of the vanilla removal, and what
-- reviving them involves on each round-end path (non-home crew respawn next round instead
-- of being deleted).
-- info = {cause='none'|'disconnected'|'other', permadeath=bool, inCCD=bool, inRoster=bool}
-- path = 'transition' (level transition save) | 'saveandquit' | 'unsaved' (round ended unsaved)
local M = {}

local CAUSES = { none = true, disconnected = true, other = true }
local PATHS = { transition = true, saveandquit = true, unsaved = true }

function M.plan(info, path)
  if not CAUSES[info.cause] then error('revive.plan: unknown cause ' .. tostring(info.cause)) end
  if not PATHS[path] then error('revive.plan: unknown path ' .. tostring(path)) end
  local keep = info.inRoster == true and not info.inCCD and not info.permadeath and info.cause ~= 'none'
  return {
    keep = keep,
    -- vanilla penalises a player death only when the round saves; a disconnect is no death
    penalty = keep and path ~= 'unsaved' and info.cause == 'other',
    clearHealth = keep,
    -- on a transition the body was despawned, so its items are already in a duffel bag
    clearInventory = keep and path == 'transition',
    clearOrders = keep,
    pendingSpawn = keep,
  }
end

-- Whether vanilla SavePlayers removes this body's info from the roster itself (server
-- MultiPlayerCampaign.SavePlayers, inventory loop: a dead bot not killed by a disconnect).
-- body = {isBot=, isDead=, disconnected=, hasInfo=, hasInventory=}
function M.dropsAtSave(b)
  return b.hasInventory == true and b.hasInfo == true and b.isBot == true and b.isDead == true
    and b.disconnected ~= true
end

return M

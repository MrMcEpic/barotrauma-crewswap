-- Pure placement: where a player should end up at round start or on rejoin.
-- players = { {key=, homeId=<entity id|nil>, last=<sid|nil>} }; views carry sid, id and the
-- fields rules.isFree reads. Protect on means nobody moves.
local rules = require('crewswap.core.rules')

local M = {}

-- A player's last-played character: the sid whose record.last == key with the greatest lastAt
-- (nil if none). lastAt makes "last played" deterministic across sessions without a new store.
function M.lastPlayed(chars, key)
  local best, bestAt
  for sid, rec in pairs(chars) do
    if rec.last == key then
      local at = rec.lastAt or -1
      if bestAt == nil or at > bestAt or (at == bestAt and sid < best) then best, bestAt = sid, at end
    end
  end
  return best
end

local function pick(player, views, toggles, claimed)
  if toggles.protect or player.last == nil then return nil end
  for _, v in ipairs(views) do
    if v.sid == player.last then
      if v.id == player.homeId or claimed[v.id] then return nil end
      if rules.isFree(v, toggles, player.key) then return v.id end
      return nil
    end
  end
  return nil
end

function M.roundStart(players, views, toggles)
  local moves, claimed = {}, {}
  for _, p in ipairs(players) do
    local id = pick(p, views, toggles, claimed)
    if id ~= nil then
      claimed[id] = true
      moves[#moves + 1] = { key = p.key, targetId = id }
    end
  end
  return moves
end

function M.rejoin(player, views, toggles)
  return pick(player, views, toggles, {})
end

-- A rejoiner whose body was handed back has no character: if rejoin() has nowhere to send them,
-- fall back to their own home body when it is Free for them.
function M.rejoinTarget(player, views, toggles)
  local id = M.rejoin(player, views, toggles)
  if id ~= nil or player.homeId == nil then return id end
  for _, v in ipairs(views) do
    if v.id == player.homeId and rules.isFree(v, toggles, player.key) then return v.id end
  end
  return nil
end

return M

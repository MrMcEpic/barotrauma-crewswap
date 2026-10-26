-- core/revive.lua: which dead crew are kept, and what reviving them does on each round-end path.
local revive = require('crewswap.core.revive')

local function info(o)
  local i = { cause = 'other', permadeath = false, inCCD = false, inRoster = true }
  for k, v in pairs(o or {}) do i[k] = v end
  return i
end

local function none(t, a, what)
  for _, k in ipairs({ 'keep', 'penalty', 'clearHealth', 'clearInventory', 'clearOrders', 'pendingSpawn' }) do
    t.eq(a[k], false, what .. ' ' .. k)
  end
end

return {
  ['permadeath never kept'] = function(t)
    for _, path in ipairs({ 'transition', 'saveandquit', 'unsaved' }) do
      none(t, revive.plan(info{ permadeath = true }, path), path)
    end
  end,
  ['home (CCD) never kept'] = function(t)
    for _, path in ipairs({ 'transition', 'saveandquit', 'unsaved' }) do
      none(t, revive.plan(info{ inCCD = true }, path), path)
    end
  end,
  ['not in the roster: never kept'] = function(t)
    none(t, revive.plan(info{ inRoster = false }, 'transition'), 'transition')
  end,
  ['transition death: penalty + clear inventory'] = function(t)
    local a = revive.plan(info(), 'transition')
    t.eq(a.keep, true); t.eq(a.penalty, true); t.eq(a.clearInventory, true)
    t.eq(a.clearHealth, true); t.eq(a.clearOrders, true); t.eq(a.pendingSpawn, true)
  end,
  ['save-and-quit death: penalty, keep inventory'] = function(t)
    local a = revive.plan(info(), 'saveandquit')
    t.eq(a.keep, true); t.eq(a.penalty, true); t.eq(a.clearInventory, false)
    t.eq(a.clearHealth, true); t.eq(a.clearOrders, true); t.eq(a.pendingSpawn, true)
  end,
  ['unsaved end: no penalty'] = function(t)
    local a = revive.plan(info(), 'unsaved')
    t.eq(a.keep, true); t.eq(a.penalty, false); t.eq(a.clearInventory, false)
    t.eq(a.clearHealth, true); t.eq(a.clearOrders, true); t.eq(a.pendingSpawn, true)
  end,
  ['disconnected death: kept, no penalty'] = function(t)
    for _, path in ipairs({ 'transition', 'saveandquit', 'unsaved' }) do
      local a = revive.plan(info{ cause = 'disconnected' }, path)
      t.eq(a.keep, true, path); t.eq(a.penalty, false, path)
      t.eq(a.clearInventory, path == 'transition', path)
      t.eq(a.pendingSpawn, true, path)
    end
  end,
  ['alive info: not kept'] = function(t)
    for _, path in ipairs({ 'transition', 'saveandquit', 'unsaved' }) do
      none(t, revive.plan(info{ cause = 'none' }, path), path)
    end
  end,
  -- vanilla SavePlayers drops a dead bot itself (server MPC.cs:350); mirror its condition
  ['dropsAtSave: only a dead bot with info and inventory, not a disconnect'] = function(t)
    local function b(o)
      local x = { isBot = true, isDead = true, disconnected = false, hasInfo = true, hasInventory = true }
      for k, v in pairs(o or {}) do x[k] = v end
      return x
    end
    t.eq(revive.dropsAtSave(b()), true, 'dead bot')
    t.eq(revive.dropsAtSave(b{ isDead = false }), false, 'alive')
    t.eq(revive.dropsAtSave(b{ isBot = false }), false, 'player')
    t.eq(revive.dropsAtSave(b{ disconnected = true }), false, 'disconnected')
    t.eq(revive.dropsAtSave(b{ hasInfo = false }), false, 'no info')
    t.eq(revive.dropsAtSave(b{ hasInventory = false }), false, 'no inventory: vanilla skips the body')
  end,
  ['unknown path or cause is an error'] = function(t)
    t.err(function() revive.plan(info(), 'reload') end)
    t.err(function() revive.plan(info{ cause = 'drowned' }, 'transition') end)
  end,
}

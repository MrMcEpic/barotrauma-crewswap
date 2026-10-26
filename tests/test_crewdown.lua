-- server/crewdown.lua with stubbed game helpers; patch callbacks are called as Hook.Patch would.
local F = require('fakes')
local W

local function world(views, clients)
  W = { patches = {}, hooks = {}, said = {}, viewCalls = 0 }
  _G.SERVER = true
  _G.CS = { active = true }
  _G.Hook = { Add = function(ev, id, fn) W.hooks[ev .. '/' .. id] = fn end,
              Patch = function(id, _, _, _, fn, when) W.patches[id] = { fn = fn, when = when } end,
              HookMethodType = { Before = 'B', After = 'A' } }
  _G.Game = { Server = { GameStarted = true } }
  package.loaded['crewswap.server.patch'] = nil
  package.loaded['crewswap.server.crewdown'] = nil
  package.loaded['crewswap.server.game'] = {
    clients = function() return clients end,
    accountKey = function(c) return c.key end,
    toggles = function() return {} end,
    crewViews = function() W.viewCalls = W.viewCalls + 1; return views end,
    announce = function(s) W.said[#W.said + 1] = s end,
  }
  local realPrint = print; print = function() end
  local P = require('crewswap.server.patch')
  _G.CS.fail = function(r) error(r) end
  local D = require('crewswap.server.crewdown')
  print = realPrint
  return D
end

local function dead(key) return { key = key, InGame = true, UsingFreeCam = false, Character = { IsDead = true, IsIncapacitated = false } } end
local function alive(key) return { key = key, InGame = true, UsingFreeCam = false, Character = { IsDead = false, IsIncapacitated = false } } end

local function tick(dt)
  local seen
  W.patches['crewswap.crewdown.pre'].fn(nil, { deltaTime = dt })
  return function() W.patches['crewswap.crewdown.post'].fn(nil, {}) end
end

return {
  ['masks every client while down with free crew, restores after Update'] = function(t)
    local a, b = dead('a'), dead('b')
    world({ F.view() }, { a, b })
    local post = tick(0.1)
    t.eq(a.UsingFreeCam, true); t.eq(b.UsingFreeCam, true)
    post()
    t.eq(a.UsingFreeCam, false); t.eq(b.UsingFreeCam, false)
    t.eq(#W.said, 1)
  end,
  ['someone alive: no mask and crewViews never scanned'] = function(t)
    local a, b = dead('a'), alive('b')
    world({ F.view() }, { a, b })
    tick(0.1)
    t.eq(a.UsingFreeCam, false)
    t.eq(W.viewCalls, 0)
  end,
  ['real freecam client keeps vanilla semantics'] = function(t)
    local a = dead('a'); a.UsingFreeCam = true
    world({ F.view() }, { a })
    tick(0.1)
    t.eq(W.viewCalls, 0)
    t.eq(a.UsingFreeCam, true)   -- not ours to clear
  end,
  ['down but no free crew: no mask'] = function(t)
    local a = dead('a')
    world({ F.view{ controller = {} } }, { a })
    tick(0.1)
    t.eq(a.UsingFreeCam, false)
  end,
  ['no clients: nothing masked'] = function(t)
    world({ F.view() }, {})
    tick(0.1)
    t.eq(#W.said, 0)
  end,
  ['grace over: unmasked so vanilla ends the round'] = function(t)
    local a = dead('a')
    world({ F.view() }, { a })
    tick(60); tick(60.5)
    t.eq(a.UsingFreeCam, false)
    t.eq(W.said[#W.said]:find('will end', 1, true) ~= nil, true)
  end,
  ['inactive: nothing happens'] = function(t)
    local a = dead('a')
    world({ F.view() }, { a })
    CS.active = false
    tick(0.1)
    t.eq(a.UsingFreeCam, false)
  end,
  ['think safety clears a stranded flag'] = function(t)
    local a = dead('a')
    world({ F.view() }, { a })
    tick(0.1)            -- no post: Update "threw"
    W.hooks['think/crewswap.crewdown.safety']()
    t.eq(a.UsingFreeCam, false)
  end,
  ['Lua error in pre clears the flags and does not raise'] = function(t)
    local a = dead('a')
    world({ F.view() }, { a })
    package.loaded['crewswap.server.game'].crewViews = function() error('boom') end
    tick(0.1)
    t.eq(a.UsingFreeCam, false)
  end,
}

-- The round doesn't end while Free crew exists. Vanilla's GameServer.Update ends
-- the round when every connected client is `!UsingFreeCam and (no/dead/incapacitated character)`.
-- While the mod's grace window is open we set UsingFreeCam on the clients inside Update (prefix) and
-- clear it afterwards (postfix + think safety), so vanilla sees "someone is up" and resets its timers.
if not SERVER then return end
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')
local rules = require('crewswap.core.rules')
local grace = require('crewswap.core.grace')

local D = {}
local gr = grace.new()
local masked = {}   -- clients whose UsingFreeCam we set during this Update

local function log(s) print('[CrewSwap] crewdown: ' .. s) end

-- Vanilla's isCrewDown, term for term (including UsingFreeCam so a real admin freecam keeps
-- vanilla semantics). No connected clients: vanilla ends the round, unchanged.
local function vanillaWouldBeDown(clients)
  if #clients == 0 then return false end
  for _, c in ipairs(clients) do
    if c.UsingFreeCam then return false end
    local ch = c.Character
    if ch ~= nil and not ch.IsDead and not ch.IsIncapacitated then return false end
  end
  return true
end

-- Free crew that at least one connected in-game client could take right now.
local function anyFree(clients)
  local toggles = G.toggles()
  local keys = {}
  for _, c in ipairs(clients) do
    if c.InGame then keys[#keys + 1] = G.accountKey(c) end
  end
  if #keys == 0 then return false end
  for _, v in ipairs(G.crewViews()) do
    for _, k in ipairs(keys) do
      if rules.isFree(v, toggles, k) then return true end
    end
  end
  return false
end

local function unmask()
  for _, c in ipairs(masked) do c.UsingFreeCam = false end
  masked = {}
end

function D.pre(dt)
  unmask()
  if not CS.active or not Game.Server.GameStarted then
    gr = grace.new()
    return
  end
  local clients = G.clients()
  local down = vanillaWouldBeDown(clients)   -- cheap client test first
  local free = down and anyFree(clients)     -- crewViews only when vanilla would end the round
  local mask, say = gr:step(dt, down, free)
  if say then G.announce(say); print(say) end
  if mask then
    for _, c in ipairs(clients) do
      if not c.UsingFreeCam then c.UsingFreeCam = true; masked[#masked + 1] = c end
    end
  end
end

local function safePre(server, p)
  local ok, err = pcall(D.pre, p['deltaTime'])
  if not ok then
    unmask()
    log('pre error: ' .. tostring(err))
  end
end

P.patch('crewswap.crewdown.pre', 'Barotrauma.Networking.GameServer', 'Update', { 'System.Single' },
  safePre, Hook.HookMethodType.Before)
P.patch('crewswap.crewdown.post', 'Barotrauma.Networking.GameServer', 'Update', { 'System.Single' },
  function() pcall(unmask) end, Hook.HookMethodType.After)
-- If Update threw, Harmony skipped the postfix: never leave the flag set past the tick.
Hook.Add('think', 'crewswap.crewdown.safety', function() pcall(unmask) end)

D.step = function() return gr end
D.reset = function() gr = grace.new(); unmask() end
return D

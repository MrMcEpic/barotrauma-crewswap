-- Joining, leaving and round-start placement. The pure rules live in core/placement.
-- Disconnect: the Hook.Add event client.disconnected is a PREFIX on DisconnectClient,
-- so client.Character is still set; releasing there makes DisconnectClient skip
-- ClientDisconnected=true and the body reverts to AI). Join: a reliable "this client finished
-- joining" signal.
if not SERVER then return end
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')
local SW = require('crewswap.server.switch')
local placement = require('crewswap.core.placement')

local Pr = {}

Pr.JOIN_WINDOW = 180   -- seconds to wait for a joiner to be in game and synced

local pending = {}     -- [accountKey] = { client =, since = }

local function log(s) print('[CrewSwap] presence: ' .. s) end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log(name .. ' error: ' .. tostring(err)) end
  end
end

local function playerFor(client)
  local key = G.accountKey(client)
  local home = G.homeBodyOf(client)
  return { key = key, homeId = home and home.ID or nil, last = placement.lastPlayed(CS.reg.chars, key) }
end

local function move(client, targetId, why)
  local target = targetId and Entity.FindEntityByID(targetId)
  if target == nil then return end
  if SW.switch(client, target) then log(why .. ': ' .. tostring(client.Name) .. ' -> ' .. tostring(target.Name)) end
end

local function recordLast(client)
  local ch = client.Character
  if ch == nil or ch.Info == nil then return end
  local rec = CS.reg:record(CS.sidOfInfo(ch.Info))
  rec.last = G.accountKey(client)
  rec.lastAt = os.time()
end

-- ---------- leaving ----------

Hook.Add('client.disconnected', 'crewswap.presence.leave', safe('leave', function(client)
  pending[G.accountKey(client)] = nil
  if not CS.active or client.Character == nil then return end
  recordLast(client)
  SW.release(client)
  log(tostring(client.Name) .. ' left; body handed back to the AI')
end))

-- ---------- joining ----------

P.patch('crewswap.join', 'Barotrauma.Networking.GameServer', 'OnInitializationComplete',
  { 'Barotrauma.Networking.NetworkConnection', 'System.String' },
  safe('join', function(instance, p)
    if not CS.active then return end
    local conn = p['connection']
    for _, c in ipairs(G.list(instance.ConnectedClients)) do
      if c.Connection == conn then
        pending[G.accountKey(c)] = { client = c, since = G.now() }
      end
    end
  end), Hook.HookMethodType.After)

local nextPoll = 0
Hook.Add('think', 'crewswap.presence.join', safe('joinpoll', function()
  if next(pending) == nil then return end
  local now = G.now()
  if now < nextPoll then return end
  nextPoll = now + 0.5
  for key, e in pairs(pending) do
    local c = e.client
    if not CS.active or now - e.since > Pr.JOIN_WINDOW then
      pending[key] = nil
    elseif c.InGame and not c.NeedsMidRoundSync and not CS.roundEnding then   -- no moves mid-save
      pending[key] = nil
      local player = playerFor(c)
      move(c, placement.rejoinTarget(player, G.crewViews(), G.toggles()), 'rejoin')
    end
  end
end))

-- ---------- round start ----------

Hook.Add('roundStart', 'crewswap.presence.rs', safe('roundStart', function()
  pending = {}   -- everyone present is placed below
  if not CS.active then return end
  local players, byKey = {}, {}
  for _, c in ipairs(G.clients()) do
    if c.Character ~= nil then
      local p = playerFor(c)
      players[#players + 1] = p
      byKey[p.key] = c
    end
  end
  for _, m in ipairs(placement.roundStart(players, G.crewViews(), G.toggles())) do
    move(byKey[m.key], m.targetId, 'round start')
  end
end))

local ST = require('crewswap.server.selftest')
ST.add('join-patch-resolves', function()
  if P.errors['crewswap.join'] ~= nil then return false, P.errors['crewswap.join'] end
  return true
end)

return Pr

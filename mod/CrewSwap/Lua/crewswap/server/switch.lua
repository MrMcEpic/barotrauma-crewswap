-- Switch requests, the switch routine (release the old body to the AI, then take the new one)
-- and the crewswap.* network messages.
if not SERVER then return end
local rules = require('crewswap.core.rules')
local codec = require('crewswap.core.statecodec')
local build = require('crewswap.shared.build')
local G = require('crewswap.server.game')

local SW = {}

SW.NO_HELLO_AFTER = 90
SW.TEXT_OUTDATED = "[CrewSwap] Your copy of CrewSwap is out of date or didn't start properly — rejoin to update."
SW.TEXT_NO_LUACS = '[CrewSwap] This server uses CrewSwap. Turn on client-side LuaCs (LuaCs settings), then rejoin to switch between crew.'

CS.lastSwitch = CS.lastSwitch or {}     -- [accountKey] = G.now() of the last switch
CS.clientBuild = CS.clientBuild or {}   -- [accountKey] = BUILD the client said hello with
CS.clientBad = CS.clientBad or {}       -- [accountKey] = true: stale copy or failed probes
CS.joinedAt = CS.joinedAt or {}         -- [accountKey] = G.now() when first seen InGame
CS.noHelloTold = CS.noHelloTold or {}   -- [accountKey] = true once the no-LuaCs notice went out
-- Hellos carried over a Lua reload (server/main.lua) from another build are stale copies.
for key, b in pairs(CS.clientBuild) do
  if b ~= build.BUILD then CS.clientBad[key] = true end
end

local function log(s) print('[CrewSwap] switch: ' .. s) end

-- A lobby (voluntary) spectator, as opposed to one a permadeath kill set.
function CS.isVoluntarySpectator(c)
  if not c.SpectateOnly then return false end
  if not (Game.ServerSettings.AllowSpectating or c.Connection == Game.Server.OwnerConnection) then return false end
  local campaign = G.campaign()
  local ccd = campaign and campaign:GetClientCharacterData(c)
  if ccd ~= nil and ccd.CharacterInfo ~= nil and ccd.CharacterInfo.PermanentlyDead then return false end
  return true
end

local function isTraitor(client)
  local ch = client.Character
  local tm = Game.Server.TraitorManager
  return ch ~= nil and tm ~= nil and tm:IsTraitor(ch) == true
end

local function hasHome(client)
  local campaign = G.campaign()
  return campaign ~= nil and campaign:GetClientCharacterData(client) ~= nil
end

local function requester(client)
  local key = G.accountKey(client)
  return {
    hasHome = hasHome(client),
    key = key, inGame = client.InGame == true, synced = not client.NeedsMidRoundSync,
    voluntarySpectator = CS.isVoluntarySpectator(client), traitor = isTraitor(client),
    inDialogue = client.Character ~= nil and client.Character.ActiveConversation ~= nil,
    lastSwitchAt = CS.lastSwitch[key],
  }
end

local function context()
  local gs = Game.GameSession
  return {
    now = G.now(), active = CS.active == true, mpCampaign = G.campaign() ~= nil,
    roundRunning = gs ~= nil and gs.IsRunning and Game.Server.GameStarted,
    roundEnding = CS.roundEnding == true,
  }
end

local function sendDenied(client, reason, extra)
  if CS.clientBuild[G.accountKey(client)] == nil then
    G.tell(client, rules.message(reason, extra))
    return
  end
  local m = Networking.Start('crewswap.denied')
  m:WriteString(reason)
  m:WriteSingle(extra or 0)
  Networking.Send(m, client.Connection)
end

function SW.deny(client, reason, source, extra)
  sendDenied(client, reason, extra)
  log(tostring(client.Name) .. ' denied (' .. tostring(source) .. '): ' .. reason)
end

-- Validate a request, then switch. source is a tag for the log ('net', 'takeover', ...).
function SW.request(client, ch, source)
  local req = requester(client)
  local ctx = context()
  local ok, reason
  if CS.clientBad[req.key] then
    ok, reason = false, 'inactive'
  else
    ok, reason = rules.validate(req, G.view(ch), G.toggles(), ctx)
  end
  if ok and not SW.switch(client, ch) then ok, reason = false, 'unavailable' end
  if not ok then
    local extra
    if reason == 'cooldown' then
      extra = math.ceil(rules.COOLDOWN - (ctx.now - req.lastSwitchAt))
    end
    SW.deny(client, reason, source, extra)
  end
  return ok, reason
end

local function releaseBody(old)
  old:ClearInputs()
  if old.AIController ~= nil then old.AIController:Reset() end
end

-- Permadeath: a player whose home is permanently dead makes the next crew member
-- they take, if it is nobody's home, their new home. Its info then lives in exactly one store.
local function adoptHome(client, target)
  if not G.isPermadeath() or target.Info == nil then return end
  local campaign = G.campaign()
  if campaign == nil then return end
  local ccd = campaign:GetClientCharacterData(client)
  if ccd == nil or ccd.CharacterInfo == nil or not ccd.CharacterInfo.PermanentlyDead then return end
  if campaign:GetCharacterData(target.Info) ~= nil then return end
  local new = campaign:SetClientCharacterData(client)   -- from client.CharacterInfo = target.Info
  new.HasSpawned = true
  local guard = CS.keepGuard
  CS.keepGuard = false
  local ok, err = pcall(function() campaign.CrewManager:RemoveCharacterInfo(target.Info) end)
  CS.keepGuard = guard
  if not ok then error(err) end
  CS.reg:record(CS.sidOfInfo(target.Info)).home = G.accountKey(client)
  if CS.noteLegit then CS.noteLegit('adopted', target.Info.ID) end   -- roster -> CCD: tell the integrity check this move is expected
  log(tostring(client.Name) .. ' has a new home: ' .. tostring(target.Name))
end

-- The routine itself; callers have validated. Two SetClientCharacter calls so every client
-- sees Control(null) for the body left; never TryTakeOverBot / RenamingEnabled.
-- A client with no CCD is refused here too (placement calls this directly): SetClientCharacter
-- points client.CharacterInfo at the target, and only a CCD ever points it back.
function SW.switch(client, target)
  if target == nil then return false end
  if not hasHome(client) then
    log(tostring(client.Name) .. ' has no campaign character yet: not switched')
    return false
  end
  if client.SpectateOnly then
    if CS.isVoluntarySpectator(client) then return false end
    client.SpectateOnly = false   -- permadeath-set: would get the new body killed at once
  end
  local old = client.Character
  if old == target then return false end
  local ok, err = pcall(function()
    if old ~= nil then
      Game.Server:SetClientCharacter(client, nil)
      releaseBody(old)
    end
    Game.Server:SetClientCharacter(client, target)
  end)
  if not ok then
    log('switch failed for ' .. tostring(client.Name) .. ': ' .. tostring(err))
    SW.broadcastState()
    return false
  end
  local key = G.accountKey(client)
  CS.lastSwitch[key] = G.now()
  if target.Info ~= nil then
    local rec = CS.reg:record(CS.sidOfInfo(target.Info))
    rec.last = key
    rec.lastAt = os.time()   -- orders "last played" across characters (core/placement)
    -- Own-crew mode: the first player to take an unclaimed character claims it (never a player's home).
    if G.toggles().pool == 'own' and rec.owner == nil and G.homeOf(target) == nil then
      rec.owner = key
      log(tostring(client.Name) .. ' claimed ' .. tostring(target.Name))
    end
  end
  log(tostring(client.Name) .. ' -> ' .. tostring(target.Name))
  local okA, errA = pcall(adoptHome, client, target)
  if not okA then log('new home failed for ' .. tostring(client.Name) .. ': ' .. tostring(errA)) end
  SW.broadcastState()
  return true
end

-- Hand the client's body back to the AI; the client is left with no character.
function SW.release(client)
  local old = client.Character
  if old == nil then return end
  local ok, err = pcall(function()
    Game.Server:SetClientCharacter(client, nil)
    releaseBody(old)
  end)
  if not ok then log('release failed for ' .. tostring(client.Name) .. ': ' .. tostring(err)) end
  SW.broadcastState()
end

-- ---------- state ----------

-- Per-client: Free depends on the requester (protect / own pool).
local function entriesFor(views, key)
  local toggles, active = G.toggles(), CS.active == true
  local out = {}
  for _, v in ipairs(views) do
    out[#out + 1] = { id = v.id, controller = v.controllerName or '',
                      free = active and rules.isFree(v, toggles, key) }
  end
  return out
end

local function send(client, views)
  local key = G.accountKey(client)
  if CS.clientBuild[key] == nil then return end   -- no client Lua: nothing would read it
  local m = Networking.Start('crewswap.state')
  codec.encode(m, entriesFor(views, key))
  Networking.Send(m, client.Connection)
end

function SW.sendState(client)
  local ok, err = pcall(function() send(client, G.crewViews()) end)
  if not ok then log('sendState failed: ' .. tostring(err)) end
end

function SW.broadcastState()
  local ok, err = pcall(function()
    local views = G.crewViews()
    for _, c in ipairs(G.clients()) do send(c, views) end
  end)
  if not ok then log('broadcastState failed: ' .. tostring(err)) end
end

-- ---------- messages ----------

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log(name .. ' error: ' .. tostring(err)) end
  end
end

Networking.Receive('crewswap.hello', safe('hello', function(msg, client)
  local clientBuild = msg:ReadString()
  local probesOk = msg:ReadBoolean()
  local key = G.accountKey(client)
  CS.clientBuild[key] = clientBuild
  if clientBuild ~= build.BUILD or not probesOk then
    CS.clientBad[key] = true
    G.tell(client, SW.TEXT_OUTDATED)
    log(tostring(client.Name) .. ' hello: build ' .. tostring(clientBuild) .. ', probes ' .. tostring(probesOk))
  else
    CS.clientBad[key] = nil
  end
  SW.sendState(client)
end))

Networking.Receive('crewswap.request', safe('request', function(msg, client)
  local id = msg:ReadUInt16()
  SW.request(client, Entity.FindEntityByID(id), 'net')
end))

-- No hello within 90 s of being in game = no client-side LuaCs. Tell once, don't kick.
-- Until then, ask every HELLO_ASK_EVERY s (at most HELLO_ASKS times): a hello sent before the
-- client was in ConnectedClients is lost, and a server Lua reload forgets every hello. LuaCs
-- itself sends its net-id packets to every client, so this message is no new risk.
SW.HELLO_ASK_EVERY = 5
SW.HELLO_ASKS = 12
CS.helloAsked = CS.helloAsked or {}   -- [accountKey] = {n=, at=}
local function askHello(c, key, now)
  local a = CS.helloAsked[key]
  if a == nil then a = { n = 0, at = -math.huge }; CS.helloAsked[key] = a end
  if a.n >= SW.HELLO_ASKS or now - a.at < SW.HELLO_ASK_EVERY then return end
  a.n, a.at = a.n + 1, now
  Networking.Send(Networking.Start('crewswap.hello?'), c.Connection)
end

local nextCheck = 0
Hook.Add('think', 'crewswap.hellowatch', safe('hellowatch', function()
  local now = G.now()
  if now < nextCheck then return end
  nextCheck = now + 1
  for _, c in ipairs(G.clients()) do
    if c.InGame then
      local key = G.accountKey(c)
      if CS.joinedAt[key] == nil then CS.joinedAt[key] = now end
      if CS.clientBuild[key] == nil then askHello(c, key, now) end
      if CS.active and CS.clientBuild[key] == nil and not CS.noHelloTold[key]
          and now - CS.joinedAt[key] >= SW.NO_HELLO_AFTER then
        CS.noHelloTold[key] = true
        G.tell(c, SW.TEXT_NO_LUACS)
        log(tostring(c.Name) .. ' sent no hello (no client-side LuaCs?)')
      end
    end
  end
end))

-- A rejoin starts over: the client sends a fresh hello from its new Lua state.
Hook.Add('client.disconnected', 'crewswap.hello.forget', safe('forget', function(client)
  local key = G.accountKey(client)
  CS.clientBuild[key], CS.clientBad[key], CS.joinedAt[key], CS.noHelloTold[key] = nil, nil, nil, nil
  CS.helloAsked[key] = nil
end))

Hook.Add('roundStart', 'crewswap.state.rs', safe('roundStart', function() SW.broadcastState() end))
Hook.Add('character.death', 'crewswap.state.death', safe('death', function(ch)
  if G.isCrew(ch) then SW.broadcastState() end
end))

local ST = require('crewswap.server.selftest')
ST.add('state-encode', function()
  local m = Networking.Start('crewswap.state')
  codec.encode(m, { { id = 1, controller = 'x', free = true } })
  return true
end)
ST.add('ccd-api', function()
  local d = LuaUserData.RegisterType('Barotrauma.MultiPlayerCampaign')
  for _, m in ipairs({ 'SetClientCharacterData', 'GetClientCharacterData' }) do
    if not LuaUserData.HasMember(d, m) then return false, 'MultiPlayerCampaign has no ' .. m end
  end
  if not LuaUserData.HasMember(LuaUserData.RegisterType('Barotrauma.CrewManager'), 'RemoveCharacterInfo') then
    return false, 'CrewManager has no RemoveCharacterInfo'
  end
  return true
end)
ST.add('crew-views', function()
  local views = G.crewViews()
  if type(views) ~= 'table' then return false, 'crewViews gave ' .. type(views) end
  return true
end)

return SW

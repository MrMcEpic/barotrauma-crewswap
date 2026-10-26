-- server/game.lua + server/switch.lua against fake game globals.
local registry = require('crewswap.core.registry')
local codec = require('crewswap.core.statecodec')
local F = require('fakes')

local W   -- the current fake world

local function ai(o)
  local ch = { ID = o.id, Name = o.name or ('c' .. o.id), IsHuman = true, Removed = false, IsDead = false,
               IsIncapacitated = false, IsRemotePlayer = false, TeamID = 1, ActiveConversation = nil,
               Info = { ID = 1000 + o.id }, inputsCleared = 0,
               types = { ['Barotrauma.Character'] = true, ['Barotrauma.AICharacter'] = true } }
  ch.AIController = { types = { ['Barotrauma.HumanAIController'] = true }, resets = 0 }
  function ch.AIController:Reset() self.resets = self.resets + 1 end
  function ch:ClearInputs() self.inputsCleared = self.inputsCleared + 1 end
  for k, v in pairs(o) do if k ~= 'id' and k ~= 'name' then ch[k] = v end end
  return ch
end

local function client(name, acct)
  local c = { Name = name, AccountId = { StringRepresentation = acct }, InGame = true,
              NeedsMidRoundSync = false, SpectateOnly = false, Character = nil,
              Connection = { name = name } }
  function c:HasPermission(p) return self.admin == true end
  return c
end

local function world()
  package.loaded['crewswap.server.game'] = nil
  package.loaded['crewswap.server.switch'] = nil
  package.loaded['crewswap.server.spawn'] = nil
  package.loaded['crewswap.server.patch'] = nil
  package.loaded['crewswap.server.selftest'] = nil
  W = { hooks = {}, recv = {}, sent = {}, told = {}, calls = {}, now = 100, ccd = {}, bots = {} }
  _G.SERVER = true
  _G.CharacterTeamType = { Team1 = 1, FriendlyNPC = 3 }
  _G.ChatMessageType = { Server = 3 }
  _G.ClientPermissions = { ManageSettings = 8 }
  _G.Hook = { Add = function(ev, id, fn) W.hooks[ev .. '/' .. id] = fn end,
              Patch = function() end, HookMethodType = { Before = 'B', After = 'A' } }
  _G.LuaUserData = {
    IsTargetType = function(o, ty) return type(o) == 'table' and o.types ~= nil and o.types[ty] == true end,
    CreateStatic = function() return setmetatable({}, { __index = function(_, k) if k == 'TotalTime' then return W.now end end }) end,
    CreateEnumTable = function() return { None = 0, MidRound = 1, BetweenRounds = 2, Permadeath = 3 } end,
  }
  local campaign = { types = { ['Barotrauma.MultiPlayerCampaign'] = true } }
  campaign.CrewManager = { GetCharacterInfos = function(self, bench) return W.bots end }
  function campaign:GetCharacterData(info) for _, d in pairs(W.ccd) do if d.CharacterInfo == info then return d end end end
  function campaign:GetClientCharacterData(c) return W.ccd[c.Name] end
  W.campaign = campaign
  _G.Game = {
    GameSession = { Campaign = campaign, IsRunning = true },
    ServerSettings = { AllowSpectating = true, RespawnMode = 1 },
    Server = { GameStarted = true, OwnerConnection = nil, TraitorManager = nil },
    SendDirectChatMessage = function(_, text, _, _, c) W.told[#W.told + 1] = { c = c, text = text } end,
    SendMessage = function(text) W.announced = text end,
  }
  function Game.Server:SetClientCharacter(c, ch)
    W.calls[#W.calls + 1] = ch or 'nil'
    if c.Character ~= nil then c.Character.IsRemotePlayer = false end
    c.Character = ch
    if ch ~= nil then ch.IsRemotePlayer = true end
  end
  _G.Client = { ClientList = {} }
  _G.Character = { CharacterList = {} }
  _G.Entity = { FindEntityByID = function(id)
    for _, ch in ipairs(Character.CharacterList) do if ch.ID == id then return ch end end
  end }
  _G.Networking = {
    Start = function(name) local b = F.buffer(); b.name = name; return b end,
    Send = function(m, conn) W.sent[#W.sent + 1] = { m = m, conn = conn } end,
    Receive = function(name, fn) W.recv[name] = fn end,
  }
  local reg = registry.new()
  _G.CS = { active = true, reg = reg, fail = function() end }
  function CS.sidOfInfo(info)
    local sid = reg:sidOf(info.ID)
    if sid == nil then sid = 'sid' .. info.ID; reg:bind(info.ID, sid); reg:record(sid) end
    return sid
  end
  local realPrint = print
  print = function() end
  local okG, G = pcall(require, 'crewswap.server.game')
  local okS, SW = pcall(require, 'crewswap.server.switch')
  print = realPrint
  assert(okG, G); assert(okS, SW)
  return G, SW
end

-- Two bots (ids 1, 2), Ann's home body (id 3, driven by Ann), an outpost NPC (id 9).
local function crew()
  local b1, b2 = ai{ id = 1, name = 'Bot1' }, ai{ id = 2, name = 'Bot2' }
  local home = ai{ id = 3, name = 'AnnHome' }
  local npc = ai{ id = 9, name = 'Guard', TeamID = 3 }
  local ann = client('Ann', 'STEAM_A')
  W.bots = { b1.Info, b2.Info }
  W.ccd.Ann = { CharacterInfo = home.Info, AccountId = { StringRepresentation = 'STEAM_A' } }
  Character.CharacterList = { b1, b2, home, npc }
  Client.ClientList = { ann }
  ann.Character = home; home.IsRemotePlayer = true
  return { b1 = b1, b2 = b2, home = home, npc = npc, ann = ann }
end

local function hello(c, buildStr, probes)
  local m = F.buffer(); m:WriteString(buildStr); m:WriteBoolean(probes)
  W.recv['crewswap.hello'](m, c)
end

local function lastSent(name)
  for i = #W.sent, 1, -1 do if W.sent[i].m.name == name then return W.sent[i] end end
end

local BUILD = require('crewswap.shared.build').BUILD

return {
  ['list converts tables and enumerables'] = function(t)
    local G = world()
    t.eq(#G.list({ 'a', 'b', 'c' }), 3)
    t.eq(#G.list(nil), 0)
    local i, src = 0, { 'x', 'y' }
    local enum = function() i = i + 1; return src[i] end   -- stands in for a CLR enumerable
    t.eq(#G.list(enum), 2)
  end,
  ['list: a non-iterable enumerable falls back to GetEnumerator/MoveNext/Current'] = function(t)
    local G = world()
    local src = { 'p', 'q', 'r' }
    local enumerable = { GetEnumerator = function()
      local i = 0
      return { MoveNext = function(self) i = i + 1; self.Current = src[i]; return i <= #src end }
    end }
    -- a plain table can't be the subject of `for v in x`, like an unregistered CLR enumerable
    local got = G.iterate(enumerable)
    t.eq(#got, 3); t.eq(got[1], 'p'); t.eq(got[3], 'r')
    local called = setmetatable({}, { __call = (function()
      local i = 0
      return function() i = i + 1; return src[i] end
    end)() })
    t.eq(#G.iterate(called), 3, 'for-in used when it works')
    t.err(function() G.iterate({}) end, 'neither works: raises')
  end,
  ['live list check: PASS line once, FAIL turns the mod off'] = function(t)
    local G = world(); local w = crew()
    w.b1.Info.types = { ['Barotrauma.CharacterInfo'] = true }
    w.b2.Info.types = { ['Barotrauma.CharacterInfo'] = true }
    local lines, realPrint = {}, print
    print = function(s) lines[#lines + 1] = s end
    W.hooks['roundStart/crewswap.game.listcheck']()
    W.hooks['roundStart/crewswap.game.listcheck']()
    print = realPrint
    t.eq(#lines, 1); t.eq(lines[1], '[CrewSwap] SELFTEST PASS live-crew-list')
    G = world(); crew()
    local failed
    CS.fail = function(r) failed = r end
    W.campaign.CrewManager.GetCharacterInfos = function() return { 'not an info' } end
    print = function(s) lines[#lines + 1] = s end
    W.hooks['roundStart/crewswap.game.listcheck']()
    print = realPrint
    t.ok(lines[#lines]:find('SELFTEST FAIL live%-crew%-list'), lines[#lines])
    t.ok(failed ~= nil, 'CS.fail called')
  end,
  ['a client with no campaign character yet is refused (nohome), and SW.switch refuses it'] = function(t)
    local _, SW = world(); local w = crew()
    local cy = client('Cy', 'STEAM_C')   -- joined mid-round, not spawned yet: no CCD
    Client.ClientList[#Client.ClientList + 1] = cy
    hello(cy, BUILD, true)
    local ok, reason = SW.request(cy, w.b1, 'net')
    t.eq(ok, false); t.eq(reason, 'nohome')
    t.eq(cy.Character, nil); t.eq(#W.calls, 0, 'no SetClientCharacter')
    t.eq(SW.switch(cy, w.b2), false, 'direct switch (placement) refused too')
    t.eq(#W.calls, 0)
  end,
  ['crew views: bots and homes, not NPCs; controller and home filled'] = function(t)
    local G = world(); local w = crew()
    local views = G.crewViews()
    t.eq(#views, 3)
    local byId = {}
    for _, v in ipairs(views) do byId[v.id] = v end
    t.ok(byId[9] == nil, 'npc excluded')
    t.eq(byId[3].controller, 'STEAM_A'); t.eq(byId[3].controllerName, 'Ann'); t.eq(byId[3].homeOf, 'STEAM_A')
    t.eq(byId[1].controller, nil); t.eq(byId[1].homeOf, nil); t.eq(byId[1].isAI, true)
    t.eq(G.isCrew(w.npc), false); t.eq(G.isCrew(w.b1), true)
  end,
  ['homeBodyOf finds the live body of the client CCD'] = function(t)
    local G = world(); local w = crew()
    t.eq(G.homeBodyOf(w.ann), w.home)
    W.ccd.Ann = nil
    t.eq(G.homeBodyOf(w.ann), nil)
  end,
  ['isPermadeath compares the enum number'] = function(t)
    local G = world()
    t.eq(G.isPermadeath(), false)
    Game.ServerSettings.RespawnMode = 3
    t.eq(G.isPermadeath(), true)
  end,
  ['toggles default to shared + protect'] = function(t)
    local G = world()
    local tg = G.toggles(); t.eq(tg.pool, 'shared'); t.eq(tg.protect, true)
  end,
  ['request switches: nil then target, old body reset, records kept'] = function(t)
    local _, SW = world(); local w = crew()
    hello(w.ann, BUILD, true)
    local ok, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(ok, true); t.eq(reason, 'ok')
    t.eq(W.calls[1], 'nil'); t.eq(W.calls[2], w.b1); t.eq(#W.calls, 2)
    t.eq(w.ann.Character, w.b1)
    t.eq(w.home.inputsCleared, 1); t.eq(w.home.AIController.resets, 1)
    t.eq(CS.lastSwitch.STEAM_A, 100)
    local rec = CS.reg.chars['sid1001']
    t.eq(rec.last, 'STEAM_A'); t.eq(type(rec.lastAt), 'number')
  end,
  ['switch broadcasts per-client state: own home Free for Ann after leaving it'] = function(t)
    local _, SW = world(); local w = crew()
    hello(w.ann, BUILD, true)
    SW.request(w.ann, w.b1, 'net')
    local st = lastSent('crewswap.state')
    t.eq(st.conn, w.ann.Connection)
    local entries = codec.decode(st.m)
    local byId = {}
    for _, e in ipairs(entries) do byId[e.id] = e end
    t.eq(byId[1].controller, 'Ann'); t.eq(byId[1].free, false)
    t.eq(byId[3].free, true); t.eq(byId[2].free, true)
  end,
  ['request over the network decodes the entity id'] = function(t)
    world(); local w = crew()
    local m = F.buffer(); m:WriteUInt16(2)
    W.recv['crewswap.request'](m, w.ann)
    t.eq(w.ann.Character, w.b2)
  end,
  ['denied request sends reason and remaining cooldown'] = function(t)
    local _, SW = world(); local w = crew()
    hello(w.ann, BUILD, true)
    SW.request(w.ann, w.b1, 'net')
    W.now = 101
    local ok, reason = SW.request(w.ann, w.b2, 'net')
    t.eq(ok, false); t.eq(reason, 'cooldown')
    local d = lastSent('crewswap.denied').m
    t.eq(d:ReadString(), 'cooldown'); t.eq(d:ReadSingle(), 2)
    t.eq(w.ann.Character, w.b1)
  end,
  ['taken target is denied'] = function(t)
    local _, SW = world(); local w = crew()
    local bob = client('Bob', 'STEAM_B'); Client.ClientList[2] = bob
    bob.Character = w.b2; w.b2.IsRemotePlayer = true
    local ok, reason = SW.request(w.ann, w.b2, 'net')
    t.eq(ok, false); t.eq(reason, 'taken')
    t.eq(#W.calls, 0)
  end,
  ['protect: another player home is not-yours'] = function(t)
    local _, SW = world(); local w = crew()
    local bob = client('Bob', 'STEAM_B'); Client.ClientList[2] = bob
    bob.Character = w.b2; w.b2.IsRemotePlayer = true
    W.ccd.Bob = { CharacterInfo = w.b1.Info, AccountId = { StringRepresentation = 'STEAM_B' } }
    W.bots = { w.b2.Info }
    local _, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(reason, 'not-yours')
  end,
  ['voluntary spectator is refused; permadeath-set spectate is cleared'] = function(t)
    local _, SW = world(); local w = crew()
    w.ann.SpectateOnly = true
    local _, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(reason, 'spectating')
    w.home.Info.PermanentlyDead = true
    local ok = SW.request(w.ann, w.b1, 'net')
    t.eq(ok, true); t.eq(w.ann.SpectateOnly, false)
  end,
  ['denial without hello goes to chat'] = function(t)
    local _, SW = world(); local w = crew()
    Game.GameSession.IsRunning = false
    SW.request(w.ann, w.b1, 'net')
    t.eq(lastSent('crewswap.denied'), nil)
    t.ok(W.told[1].text:find('^%[CrewSwap%]'), 'chat text')
  end,
  ['stale hello: told, marked inactive, still gets state'] = function(t)
    local _, SW = world(); local w = crew()
    hello(w.ann, 'old', true)
    t.eq(W.told[1].text, SW.TEXT_OUTDATED)
    t.ok(lastSent('crewswap.state') ~= nil, 'state sent')
    local _, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(reason, 'inactive')
    hello(w.ann, BUILD, false)
    _, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(reason, 'inactive')
    hello(w.ann, BUILD, true)
    t.eq((SW.request(w.ann, w.b1, 'net')), true)
  end,
  ['no hello within 90 s: told once'] = function(t)
    local _, SW = world(); local w = crew()
    local think = W.hooks['think/crewswap.hellowatch']
    think()
    W.now = 189; think(); t.eq(#W.told, 0)
    W.now = 190; think(); t.eq(#W.told, 1); t.eq(W.told[1].text, SW.TEXT_NO_LUACS)
    W.now = 300; think(); t.eq(#W.told, 1)
  end,
  ['server asks in-game clients with no hello for one every 5 s, at most 12 times'] = function(t)
    local _, SW = world(); local w = crew()
    local bob = client('Bob', 'STEAM_B'); Client.ClientList[#Client.ClientList + 1] = bob
    hello(bob, BUILD, true)
    local think = W.hooks['think/crewswap.hellowatch']
    local function asks(c)
      local n = 0
      for _, s in ipairs(W.sent) do if s.m.name == 'crewswap.hello?' and s.conn == c.Connection then n = n + 1 end end
      return n
    end
    think()
    t.eq(asks(w.ann), 1, 'asked at once (e.g. right after a server Lua reload)')
    t.eq(asks(bob), 0, 'Bob already said hello')
    W.now = 102; think(); t.eq(asks(w.ann), 1)
    W.now = 105; think(); t.eq(asks(w.ann), 2)
    for i = 1, 20 do W.now = W.now + 5; think() end
    t.eq(asks(w.ann), 12, 'capped')
    hello(w.ann, BUILD, true)
    W.hooks['client.disconnected/crewswap.hello.forget'](w.ann)
    W.now = W.now + 5; think()
    t.eq(asks(w.ann), 13, 'a rejoin starts the count again')
  end,
  ['release hands the body back to the AI'] = function(t)
    local _, SW = world(); local w = crew()
    SW.release(w.ann)
    t.eq(w.ann.Character, nil); t.eq(W.calls[1], 'nil')
    t.eq(w.home.AIController.resets, 1); t.eq(w.home.IsRemotePlayer, false)
  end,
  ['own pool: first switch into an unowned bot claims it'] = function(t)
    local _, SW = world(); local w = crew()
    CS.config = { toggles = { pool = 'own', protect = true } }
    t.ok(SW.request(w.ann, w.b1, 'net'))
    t.eq(CS.reg.chars[CS.sidOfInfo(w.b1.Info)].owner, 'STEAM_A')
  end,
  ['own pool: a bot owned by someone else is refused, owner unchanged'] = function(t)
    local _, SW = world(); local w = crew()
    CS.config = { toggles = { pool = 'own', protect = true } }
    CS.reg:record(CS.sidOfInfo(w.b1.Info)).owner = 'STEAM_B'
    local ok, reason = SW.request(w.ann, w.b1, 'net')
    t.eq(ok, false); t.eq(reason, 'not-yours')
    t.eq(CS.reg.chars[CS.sidOfInfo(w.b1.Info)].owner, 'STEAM_B')
  end,
  ['shared pool: switching does not set an owner'] = function(t)
    local _, SW = world(); local w = crew()
    t.ok(SW.request(w.ann, w.b1, 'net'))
    t.eq(CS.reg.chars[CS.sidOfInfo(w.b1.Info)].owner, nil)
  end,
}

-- server/death.lua (and the permadeath home adoption in server/switch.lua) against fake game
-- globals, with patch callbacks called the way Hook.Patch would call them.
local registry = require('crewswap.core.registry')
local F = require('fakes')

local W   -- the current fake world
local SW

local function body(o)
  local ch = { ID = o.id, Name = o.name or ('c' .. o.id), IsHuman = true, Removed = false, IsDead = false,
               IsIncapacitated = false, IsRemotePlayer = false, TeamID = 1, ActiveConversation = nil,
               Info = { ID = 1000 + o.id, PermanentlyDead = false }, inputsCleared = 0,
               types = { ['Barotrauma.Character'] = true, ['Barotrauma.AICharacter'] = true } }
  ch.AIController = { types = { ['Barotrauma.HumanAIController'] = true }, resets = 0 }
  function ch.AIController:Reset() self.resets = self.resets + 1 end
  function ch:ClearInputs() self.inputsCleared = self.inputsCleared + 1 end
  ch.Wallet = { Balance = 0 }
  function ch.Wallet:Deduct(n) self.Balance = self.Balance - n end
  for k, v in pairs(o) do if k ~= 'id' and k ~= 'name' then ch[k] = v end end
  return ch
end

local function client(name, acct)
  return { Name = name, AccountId = { StringRepresentation = acct }, InGame = true,
           NeedsMidRoundSync = false, SpectateOnly = false, Character = nil, CharacterInfo = nil,
           Connection = { name = name } }
end

local function ccd(info, acct)
  local d = { CharacterInfo = info, AccountId = { StringRepresentation = acct }, applied = 0, HasSpawned = true }
  function d:ApplyPermadeath() self.applied = self.applied + 1; self.CharacterInfo.PermanentlyDead = true end
  return d
end

local function world()
  for _, m in ipairs({ 'game', 'switch', 'spawn', 'patch', 'selftest', 'death' }) do
    package.loaded['crewswap.server.' .. m] = nil
  end
  W = { hooks = {}, patches = {}, calls = {}, now = 100, ccd = {}, bots = {}, flags = {}, chats = {},
        removed = {}, broadcasts = 0, sent = {} }
  _G.SERVER = true
  _G.CharacterTeamType = { Team1 = 1, FriendlyNPC = 3 }
  _G.ChatMessageType = { Server = 3, ServerMessageBoxInGame = 11 }
  _G.ClientPermissions = { ManageSettings = 8 }
  _G.CauseOfDeathType = { Damage = 0, Disconnected = 4 }
  _G.Hook = { Add = function(ev, id, fn) W.hooks[ev .. '/' .. id] = fn end,
              Patch = function(id, class, method, a, b, c)
                local types, fn, when = a, b, c
                if type(a) == 'function' then types, fn, when = nil, a, b end
                W.patches[id] = { class = class, method = method, types = types, fn = fn, when = when }
              end,
              HookMethodType = { Before = 'B', After = 'A' } }
  _G.LuaUserData = {
    IsTargetType = function(o, ty) return type(o) == 'table' and o.types ~= nil and o.types[ty] == true end,
    CreateStatic = function() return setmetatable({}, { __index = function(_, k) if k == 'TotalTime' then return W.now end end }) end,
    CreateEnumTable = function() return { None = 0, MidRound = 1, BetweenRounds = 2, Permadeath = 3, CharacterInfo = 7 } end,
    RegisterType = function(name) return { name = name } end,
  }
  local campaign = { types = { ['Barotrauma.MultiPlayerCampaign'] = true }, Bank = { given = 0 } }
  function campaign.Bank:Give(n) self.given = self.given + n end
  campaign.CrewManager = { GetCharacterInfos = function(self, bench) return W.bots end }
  function campaign.CrewManager:RemoveCharacterInfo(info)
    W.removed[#W.removed + 1] = { info = info, guard = CS.keepGuard }
  end
  function campaign:GetCharacterData(info) for _, d in pairs(W.ccd) do if d.CharacterInfo == info then return d end end end
  function campaign:GetClientCharacterData(c) return W.ccd[c.Name] end
  function campaign:IncrementLastUpdateIdForFlag(f) W.flags[#W.flags + 1] = f end
  function campaign:SetClientCharacterData(c)
    local d = ccd(c.CharacterInfo, c.AccountId.StringRepresentation)
    d.HasSpawned = false
    W.ccd[c.Name] = d
    W.newCCD = d
    return d
  end
  W.campaign = campaign
  _G.Game = {
    GameSession = { Campaign = campaign, IsRunning = true },
    ServerSettings = { AllowSpectating = true, RespawnMode = 1 },
    Server = { GameStarted = true, OwnerConnection = nil, TraitorManager = nil },
    overrideTraitors = false,
    SendDirectChatMessage = function() end,
    SendMessage = function() end,
  }
  function Game.Server:SetClientCharacter(c, ch)
    W.calls[#W.calls + 1] = ch or 'nil'
    if c.Character ~= nil then c.Character.IsRemotePlayer = false end
    c.Character = ch
    if ch ~= nil then ch.IsRemotePlayer = true; c.CharacterInfo = ch.Info end
  end
  function Game.Server:SendDirectChatMessage(text, c, ty) W.chats[#W.chats + 1] = { text = text, c = c, ty = ty } end
  _G.Client = { ClientList = {} }
  _G.Character = { CharacterList = {} }
  _G.Entity = { FindEntityByID = function(id)
    for _, ch in ipairs(Character.CharacterList) do if ch.ID == id then return ch end end
  end }
  _G.Networking = { Start = function(name) local b = F.buffer(); b.name = name; return b end,
                    Send = function(m, conn) W.sent[#W.sent + 1] = { m = m, conn = conn } end,
                    Receive = function() end }
  local reg = registry.new()
  _G.CS = { active = true, lockdown = false, reg = reg, failed = {}, pending = {}, keepGuard = false }
  function CS.fail(r) CS.failed[#CS.failed + 1] = r; CS.active = false; CS.lockdown = true end
  function CS.sidOfInfo(info)
    local sid = reg:sidOf(info.ID)
    if sid == nil then sid = 'sid' .. info.ID; reg:bind(info.ID, sid); reg:record(sid) end
    return sid
  end
  local realPrint = print
  W.log = {}
  print = function(s) W.log[#W.log + 1] = s end
  local okS, sw = pcall(require, 'crewswap.server.switch')
  local okD, D = pcall(require, 'crewswap.server.death')
  print = realPrint
  assert(okS, sw); assert(okD, D)
  SW = sw
  local realBroadcast = SW.broadcastState
  SW.broadcastState = function() W.broadcasts = W.broadcasts + 1; return realBroadcast() end
  return D
end

local function quiet(fn, ...)
  local realPrint = print
  print = function(s) W.log[#W.log + 1] = s end
  local r = table.pack(pcall(fn, ...))
  print = realPrint
  assert(r[1], r[2])
  return table.unpack(r, 2, r.n)
end

-- Ann (home 3) drives bot 1; Bob (home 4) drives his own home; bot 2 idle.
local function crew()
  local b1, b2 = body{ id = 1, name = 'Bot1' }, body{ id = 2, name = 'Bot2' }
  local annHome, bobHome = body{ id = 3, name = 'AnnHome' }, body{ id = 4, name = 'BobHome' }
  local ann, bob = client('Ann', 'STEAM_A'), client('Bob', 'STEAM_B')
  W.bots = { b1.Info, b2.Info }
  W.ccd.Ann = ccd(annHome.Info, 'STEAM_A')
  W.ccd.Bob = ccd(bobHome.Info, 'STEAM_B')
  Character.CharacterList = { b1, b2, annHome, bobHome }
  Client.ClientList = { ann, bob }
  ann.Character, ann.CharacterInfo = b1, b1.Info; b1.IsRemotePlayer = true
  bob.Character, bob.CharacterInfo = bobHome, bobHome.Info; bobHome.IsRemotePlayer = true
  return { b1 = b1, b2 = b2, annHome = annHome, bobHome = bobHome, ann = ann, bob = bob }
end

-- Runs KillProjSpecific the way the game does: prefix, (vanilla body), postfix. `during` sees
-- the state vanilla sees.
local function kill(ch, cause, during)
  ch.IsDead = true
  ch.CauseOfDeath = ch.CauseOfDeath or { Type = cause or CauseOfDeathType.Damage }
  local p = { causeOfDeath = cause or CauseOfDeathType.Damage, causeOfDeathAffliction = nil, log = true }
  quiet(W.patches['crewswap.kill.pre'].fn, ch, p)
  if during then during() end
  quiet(W.patches['crewswap.kill.post'].fn, ch, p)
end

local function setPermadeath() Game.ServerSettings.RespawnMode = 3 end

-- A TAKEOVERBOT message holding one UInt16 (a CharacterInfo id), with a bit position.
local function takeoverMsg(infoId)
  local m = { BitPosition = 0, reads = 0 }
  function m:ReadUInt16() self.reads = self.reads + 1; self.BitPosition = self.BitPosition + 16; return infoId end
  return m
end

local function takeover(sender, infoId)
  local p = { inc = takeoverMsg(infoId), sender = sender }
  quiet(W.patches['crewswap.takeover'].fn, Game.Server, p)
  return p
end

local function lastDenied()
  for i = #W.sent, 1, -1 do if W.sent[i].m.name == 'crewswap.denied' then return W.sent[i].m:ReadString() end end
end

return {
  ['death patches: Kill pre/post, respawn detach, RetainXP, takeover'] = function(t)
    world()
    local pre, post = W.patches['crewswap.kill.pre'], W.patches['crewswap.kill.post']
    t.eq(pre.class, 'Barotrauma.Character'); t.eq(pre.method, 'KillProjSpecific'); t.eq(pre.types, nil); t.eq(pre.when, 'B')
    t.eq(post.method, 'KillProjSpecific'); t.eq(post.when, 'A')
    local r = W.patches['crewswap.respawn.detach']
    t.eq(r.class, 'Barotrauma.Networking.RespawnManager'); t.eq(r.method, 'RespawnCharacters')
    t.eq(r.types[1], 'Barotrauma.Networking.RespawnManager+TeamSpecificState'); t.eq(r.when, 'B')
    local xs, xg = W.patches['crewswap.retainxp.save'], W.patches['crewswap.retainxp.get']
    t.eq(xs.class, 'Barotrauma.MultiPlayerCampaign'); t.eq(xs.method, 'SaveExperiencePoints'); t.eq(xs.when, 'B')
    t.eq(xg.method, 'GetSavedExperiencePoints'); t.eq(xg.when, 'B')
    local tk, tp = W.patches['crewswap.takeover'], W.patches['crewswap.takeover.post']
    t.eq(tk.class, 'Barotrauma.Networking.GameServer'); t.eq(tk.method, 'ReadTakeOverBotMessage')
    t.eq(tk.types, nil, 'IReadMessage is an interface: no type list'); t.eq(tk.when, 'B')
    t.eq(tp.class, 'Barotrauma.Networking.Client'); t.eq(tp.method, 'TryTakeOverBot'); t.eq(tp.when, 'A')
    t.eq(#CS.failed, 0)
  end,
  ['kill (Permadeath): an undriven player home dies for good, its wallet is banked'] = function(t)
    world(); local w = crew()
    setPermadeath()
    w.annHome.Wallet.Balance = 200   -- Ann drives Bot1; her home is run by the AI
    kill(w.annHome)
    t.eq(W.ccd.Ann.applied, 1, 'ApplyPermadeath on the dead home\'s CCD')
    t.eq(w.annHome.Info.PermanentlyDead, true)
    t.eq(W.campaign.Bank.given, 200); t.eq(w.annHome.Wallet.Balance, 0)
    t.eq(W.flags[#W.flags], 7, 'CharacterInfo flag bumped')
    t.eq(w.ann.Character, w.b1, 'the owner keeps driving the bot'); t.eq(w.ann.SpectateOnly, false)
    t.eq(W.ccd.Bob.applied, 0)
  end,
  ['kill: undriven deaths outside Permadeath, by disconnect, or of a bot are not permadeath'] = function(t)
    world(); local w = crew()
    kill(w.annHome)
    t.eq(W.ccd.Ann.applied, 0, 'MidRound'); t.eq(w.annHome.Info.PermanentlyDead, false)
    world(); w = crew(); setPermadeath()
    kill(w.annHome, CauseOfDeathType.Disconnected)
    t.eq(W.ccd.Ann.applied, 0, 'disconnected')
    world(); w = crew(); setPermadeath()
    kill(w.b2)
    t.eq(w.b2.Info.PermanentlyDead, false, 'a bot is left to vanilla (End drops it)')
    t.eq(#W.flags, 0)
    -- already dead for good: not applied twice
    world(); w = crew(); setPermadeath()
    w.annHome.Info.PermanentlyDead = true
    kill(w.annHome)
    t.eq(W.ccd.Ann.applied, 0)
  end,
  ['kill: vanilla sees no driver; postfix restores it and re-points CharacterInfo at the home'] = function(t)
    world(); local w = crew()
    local seen = 'unset'
    kill(w.b1, nil, function() seen = w.ann.Character end)
    t.eq(seen, nil, 'driver hidden from vanilla')
    t.eq(w.ann.Character, w.b1, 'restored')
    t.eq(w.ann.CharacterInfo, w.annHome.Info, 'CharacterInfo = home CCD info')
    t.eq(w.ann.SpectateOnly, false)
    t.eq(w.b1.Info.PermanentlyDead, false, 'not permadeath')
    t.eq(#W.flags, 0)
    t.eq(W.broadcasts, 1, 'onDriverDeath broadcast state')
    t.eq(next(CS.deathCtx), nil)
  end,
  ['kill: an undriven bot, a non-crew body and the mod off are left to vanilla'] = function(t)
    world(); local w = crew()
    kill(w.b2)
    t.eq(W.broadcasts, 0)
    local npc = body{ id = 9, name = 'Guard', TeamID = 3 }
    Character.CharacterList[#Character.CharacterList + 1] = npc
    w.ann.Character = npc
    local seen
    kill(npc, nil, function() seen = w.ann.Character end)
    t.eq(seen, npc, 'driving a non-crew body: vanilla untouched')
    world(); w = crew()
    CS.active = false
    kill(w.b1, nil, function() seen = w.ann.Character end)
    t.eq(seen, w.b1)
    t.eq(w.ann.CharacterInfo, w.b1.Info)
  end,
  ['permadeath: a driven bot dies for good; the driver keeps their own home'] = function(t)
    world(); local w = crew()
    setPermadeath()
    kill(w.b1)
    t.eq(w.b1.Info.PermanentlyDead, true)
    t.eq(W.ccd.Ann.applied, 0); t.eq(w.annHome.Info.PermanentlyDead, false)
    t.eq(w.ann.SpectateOnly, false)
    t.eq(W.flags[1], 7, 'CharacterInfo net flag bumped')
    t.eq(W.campaign.Bank.given, 0)
  end,
  ['permadeath: a home dies for good; its balance goes to the bank'] = function(t)
    world(); local w = crew()
    setPermadeath()
    w.bobHome.Wallet.Balance = 250
    kill(w.bobHome)
    t.eq(W.ccd.Bob.applied, 1); t.eq(w.bobHome.Info.PermanentlyDead, true)
    t.eq(W.campaign.Bank.given, 250); t.eq(w.bobHome.Wallet.Balance, 0, 'not paid twice')
    t.eq(w.bob.Character, w.bobHome); t.eq(w.bob.SpectateOnly, false)
    -- someone else's home, driven by Ann (protect off)
    world(); w = crew()
    setPermadeath()
    w.ann.Character = w.bobHome; w.bob.Character = w.b2
    kill(w.bobHome)
    t.eq(W.ccd.Bob.applied, 1); t.eq(W.ccd.Ann.applied, 0)
  end,
  ['permadeath: a disconnect death is not permanent'] = function(t)
    world(); local w = crew()
    setPermadeath()
    kill(w.b1, CauseOfDeathType.Disconnected)
    t.eq(w.b1.Info.PermanentlyDead, false); t.eq(#W.flags, 0)
    t.eq(w.ann.Character, w.b1)
  end,
  ['traitor kill message goes to the driver, unless traitors are overridden'] = function(t)
    world(); local w = crew()
    local traitor = body{ id = 7, IsTraitor = true }
    w.b1.CauseOfDeath = { Type = CauseOfDeathType.Damage, Killer = traitor }
    kill(w.b1)
    t.eq(#W.chats, 1); t.eq(W.chats[1].c, w.ann)
    t.eq(W.chats[1].text, 'KilledByTraitorNotification~'); t.eq(W.chats[1].ty, ChatMessageType.ServerMessageBoxInGame)
    world(); w = crew()
    Game.overrideTraitors = true
    w.b1.CauseOfDeath = { Type = CauseOfDeathType.Damage, Killer = body{ id = 7, IsTraitor = true } }
    kill(w.b1)
    t.eq(#W.chats, 0)
    world(); w = crew()
    w.b1.CauseOfDeath = { Type = CauseOfDeathType.Damage, Killer = w.b1 }
    w.b1.IsTraitor = true
    kill(w.b1)
    t.eq(#W.chats, 0, 'suicide by a traitor')
  end,
  ['a failed effect still restores the driver; think restores a lost postfix'] = function(t)
    world(); local w = crew()
    setPermadeath()
    function W.campaign:IncrementLastUpdateIdForFlag() error('boom') end
    kill(w.b1)
    t.eq(w.ann.Character, w.b1)
    t.eq(W.broadcasts, 1)
    world(); w = crew()
    quiet(W.patches['crewswap.kill.pre'].fn, w.b1, { causeOfDeath = 0 })
    t.eq(w.ann.Character, nil)
    quiet(W.hooks['think/crewswap.death.safety'])
    t.eq(w.ann.Character, w.b1)
    t.eq(next(CS.deathCtx), nil)
  end,
  ['respawn detach: a dead borrowed corpse is let go, a dead home is not; off in permadeath'] = function(t)
    world(); local w = crew()
    w.b1.IsDead = true; w.bobHome.IsDead = true
    quiet(W.patches['crewswap.respawn.detach'].fn, {}, { teamSpecificState = {} })
    t.eq(w.ann.Character, nil); t.eq(w.bob.Character, w.bobHome)
    world(); w = crew()
    w.b1.IsDead = true
    setPermadeath()
    quiet(W.patches['crewswap.respawn.detach'].fn, {}, { teamSpecificState = {} })
    t.eq(w.ann.Character, w.b1)
    world(); w = crew()
    w.b1.IsDead = true
    CS.active = false
    quiet(W.patches['crewswap.respawn.detach'].fn, {}, { teamSpecificState = {} })
    t.eq(w.ann.Character, w.b1)
  end,
  ['RetainXP: save prevented, saved XP read as 0; vanilla while off'] = function(t)
    world()
    local ps = {}
    quiet(W.patches['crewswap.retainxp.save'].fn, W.campaign, ps)
    t.eq(ps.PreventExecution, true)
    local pg = {}
    t.eq(quiet(W.patches['crewswap.retainxp.get'].fn, W.campaign, pg), 0)
    t.eq(pg.PreventExecution, true)
    CS.active = false
    local pg2 = {}
    t.eq(select('#', quiet(W.patches['crewswap.retainxp.get'].fn, W.campaign, pg2)), 0, 'bare return')
    t.eq(pg2.PreventExecution, nil)
    local ps2 = {}
    quiet(W.patches['crewswap.retainxp.save'].fn, W.campaign, ps2)
    t.eq(ps2.PreventExecution, nil)
  end,
  ['takeover: a spawned crew id becomes a mod switch, message rewound'] = function(t)
    world(); local w = crew()
    w.ann.Character = w.annHome; w.b1.IsRemotePlayer = false
    local p = takeover(w.ann, w.b2.Info.ID)
    t.eq(p.PreventExecution, true)
    t.eq(w.ann.Character, w.b2)
    t.eq(p.inc.BitPosition, 0, 'rewound'); t.eq(p.inc.reads, 1)
    -- a taken one is denied through the mod
    local p2 = takeover(w.ann, w.bobHome.Info.ID)
    t.eq(p2.PreventExecution, true); t.eq(w.ann.Character, w.b2)
  end,
  ['takeover: hire/bench ids fall through only in permadeath with a dead home, re-pointed'] = function(t)
    world(); local w = crew()
    local p = takeover(w.ann, 5555)
    t.eq(p.PreventExecution, true, 'not permadeath: denied')
    t.eq(lastDenied() == nil, true, 'no hello: told in chat instead')
    setPermadeath()
    local p2 = takeover(w.ann, 5555)
    t.eq(p2.PreventExecution, true, 'home alive: denied')
    w.annHome.Info.PermanentlyDead = true
    local p3 = takeover(w.ann, 5555)
    t.eq(p3.PreventExecution, nil, 'vanilla hire/bench path')
    t.eq(w.ann.CharacterInfo, w.annHome.Info, 're-pointed at the dead home')
    t.eq(p3.inc.BitPosition, 0)
    W.ccd.Ann = nil
    local p4 = takeover(w.ann, 5555)
    t.eq(p4.PreventExecution, nil, 'no home CCD at all')
    CS.active = false
    local p5 = takeover(w.ann, w.b2.Info.ID)
    t.eq(p5.PreventExecution, nil); t.eq(p5.inc.reads, 0, 'mod off: untouched')
  end,
  ['takeover denial has its own Canadian-English text'] = function(t)
    local rules = require('crewswap.core.rules')
    t.eq(rules.message('takeover'),
      '[CrewSwap] You can only take on a new crew member once your own character is permanently dead.')
  end,
  ['takeover: an error fails closed'] = function(t)
    world(); local w = crew()
    local p = { inc = nil, sender = w.ann }
    quiet(W.patches['crewswap.takeover'].fn, Game.Server, p)
    t.eq(p.PreventExecution, true)
  end,
  ['TryTakeOverBot postfix records the new home on success only'] = function(t)
    world(); local w = crew()
    local fn = W.patches['crewswap.takeover.post'].fn
    t.eq(select('#', quiet(fn, w.ann, { botCharacter = w.b2, OriginalReturnValue = false })), 0)
    t.eq(CS.reg:sidOf(w.b2.Info.ID), nil)
    quiet(fn, w.ann, { botCharacter = w.b2, OriginalReturnValue = true })
    local rec = CS.reg.chars[CS.reg:sidOf(w.b2.Info.ID)]
    t.eq(rec.home, 'STEAM_A'); t.eq(rec.last, 'STEAM_A'); t.eq(type(rec.lastAt), 'number')
  end,
  ['permadeath switch: a dead home makes the next non-home crew member the new home'] = function(t)
    world(); local w = crew()
    setPermadeath()
    CS.keepGuard = true
    w.ann.Character = w.annHome; w.b1.IsRemotePlayer = false
    w.annHome.IsDead = true; w.annHome.Info.PermanentlyDead = true
    t.eq(SW.switch(w.ann, w.b2), true)
    local d = W.newCCD
    t.ok(d ~= nil, 'SetClientCharacterData called')
    t.eq(d.CharacterInfo, w.b2.Info); t.eq(d.HasSpawned, true)
    t.eq(W.ccd.Ann, d)
    t.eq(#W.removed, 1); t.eq(W.removed[1].info, w.b2.Info); t.eq(W.removed[1].guard, false, 'keep guard off')
    t.eq(CS.keepGuard, true, 'guard restored')
    t.eq(CS.reg.chars[CS.reg:sidOf(w.b2.Info.ID)].home, 'STEAM_A')
  end,
  ['permadeath switch: no adoption with a living home, into another home, or outside permadeath'] = function(t)
    world(); local w = crew()
    setPermadeath()
    SW.switch(w.ann, w.b2)
    t.eq(W.newCCD, nil, 'home alive')
    world(); w = crew()
    setPermadeath()
    w.annHome.Info.PermanentlyDead = true
    w.bob.Character = w.b2
    SW.switch(w.ann, w.bobHome)
    t.eq(W.newCCD, nil, "Bob's home is in a CCD")
    world(); w = crew()
    w.annHome.Info.PermanentlyDead = true
    SW.switch(w.ann, w.b2)
    t.eq(W.newCCD, nil, 'MidRound')
    t.eq(#W.removed, 0)
  end,
}

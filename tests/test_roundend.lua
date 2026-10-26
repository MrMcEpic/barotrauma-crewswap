-- server/roundend.lua against fake game globals: the SavePlayers restore, the GameOver
-- correction and the crew-set postfix, called the way Hook.Patch would call them.
local registry = require('crewswap.core.registry')

local W   -- the current fake world

local function body(o)
  local ch = { ID = o.id, Name = o.name or ('c' .. o.id), IsHuman = true, Removed = false, IsDead = false,
               IsIncapacitated = false, IsRemotePlayer = false, IsBot = true, TeamID = 1,
               Info = { ID = 1000 + o.id }, inputsCleared = 0, Wallet = { Balance = 0, RewardDistribution = 0 },
               types = { ['Barotrauma.Character'] = true, ['Barotrauma.AICharacter'] = true } }
  ch.AIController = { types = { ['Barotrauma.HumanAIController'] = true }, resets = 0 }
  function ch.AIController:Reset() self.resets = self.resets + 1 end
  function ch:ClearInputs() self.inputsCleared = self.inputsCleared + 1 end
  for k, v in pairs(o) do if k ~= 'id' and k ~= 'name' then ch[k] = v end end
  return ch
end

local function client(name, acct)
  return { Name = name, AccountId = { StringRepresentation = acct }, InGame = true,
           NeedsMidRoundSync = false, SpectateOnly = false, Character = nil, CharacterInfo = nil,
           Connection = { name = name } }
end

-- A fake ImmutableHashSet: Add returns a new set, the original is untouched.
local function set(items)
  local s = { items = {} }
  for i, v in ipairs(items or {}) do s.items[i] = v end
  function s:Contains(x) for _, v in ipairs(self.items) do if v == x then return true end end return false end
  function s:Add(x)
    if self:Contains(x) then return self end
    local copy = {}
    for i, v in ipairs(self.items) do copy[i] = v end
    copy[#copy + 1] = x
    return set(copy)
  end
  return s
end

local function world()
  for _, m in ipairs({ 'game', 'switch', 'spawn', 'patch', 'selftest', 'roundend' }) do
    package.loaded['crewswap.server.' .. m] = nil
  end
  W = { hooks = {}, patches = {}, calls = {}, now = 100, ccd = {}, bots = {}, accessible = {} }
  _G.SERVER = true
  _G.CharacterTeamType = { Team1 = 1, FriendlyNPC = 3 }
  _G.ChatMessageType = { Server = 3 }
  _G.ClientPermissions = { ManageSettings = 8 }
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
    CreateEnumTable = function() return { None = 0, MidRound = 1, BetweenRounds = 2, Permadeath = 3 } end,
    RegisterType = function(name) return { name = name } end,
    MakePropertyAccessible = function(d, prop) W.accessible[d.name .. '.' .. prop] = true end,
  }
  local campaign = { types = { ['Barotrauma.MultiPlayerCampaign'] = true }, GameOver = false }
  campaign.CrewManager = { GetCharacterInfos = function(self, bench) return W.bots end }
  function campaign.CrewManager:AddCharacterInfo(info)
    for _, ci in ipairs(W.bots) do if ci == info then error('added twice') end end
    W.bots[#W.bots + 1] = info
  end
  function campaign:GetCharacterData(info) for _, d in pairs(W.ccd) do if d.CharacterInfo == info then return d end end end
  function campaign:GetClientCharacterData(c) return W.ccd[c.Name] end
  W.campaign = campaign
  _G.Game = {
    GameSession = { Campaign = campaign, IsRunning = false },
    ServerSettings = { AllowSpectating = true, RespawnMode = 1 },
    Server = { GameStarted = true, OwnerConnection = nil, TraitorManager = nil },
    SendDirectChatMessage = function() end,
    SendMessage = function() end,
  }
  function Game.Server:SetClientCharacter(c, ch)
    W.calls[#W.calls + 1] = { c = c.Name, ch = ch or 'nil' }
    if c.Character ~= nil then c.Character.IsRemotePlayer = false; c.Character.IsBot = true end
    c.Character = ch
    if ch ~= nil then ch.IsRemotePlayer = true; ch.IsBot = false; c.CharacterInfo = ch.Info end
  end
  _G.Client = { ClientList = {} }
  _G.Character = { CharacterList = {} }
  _G.Entity = { FindEntityByID = function() end }
  _G.Networking = { Start = function() return {} end, Send = function() end, Receive = function() end }
  local reg = registry.new()
  _G.CS = { active = true, lockdown = false, reg = reg, failed = {}, pending = {} }
  _G.CauseOfDeathType = { Damage = 0, Disconnected = 4 }
  function CS.fail(r) CS.failed[#CS.failed + 1] = r; CS.active = false; CS.lockdown = true end
  function CS.sidOfInfo(info)
    local sid = reg:sidOf(info.ID)
    if sid ~= nil then return sid end
    local pend = CS.pending[info.ID]
    CS.pending[info.ID] = nil
    sid = pend and pend.sid or ('sid' .. info.ID)
    if pend and reg.chars[sid] == nil then reg.chars[sid] = pend.rec end
    reg:bind(info.ID, sid); reg:record(sid)
    return sid
  end
  local realPrint = print
  W.log = {}
  print = function(s) W.log[#W.log + 1] = s end
  local ok, R = pcall(require, 'crewswap.server.roundend')
  print = realPrint
  assert(ok, R)
  return R
end

local function quiet(fn, ...)
  local realPrint = print
  print = function(s) W.log[#W.log + 1] = s end
  local r = table.pack(pcall(fn, ...))
  print = realPrint
  assert(r[1], r[2])
  return table.unpack(r, 2, r.n)
end

-- Ann (home 3) drives bot 1, Bob (home 4) drives his own home; bot 2 is idle.
local function crew()
  local b1, b2 = body{ id = 1, name = 'Bot1' }, body{ id = 2, name = 'Bot2' }
  local annHome, bobHome = body{ id = 3, name = 'AnnHome' }, body{ id = 4, name = 'BobHome' }
  local ann, bob = client('Ann', 'STEAM_A'), client('Bob', 'STEAM_B')
  W.bots = { b1.Info, b2.Info }
  W.ccd.Ann = { CharacterInfo = annHome.Info, AccountId = { StringRepresentation = 'STEAM_A' } }
  W.ccd.Bob = { CharacterInfo = bobHome.Info, AccountId = { StringRepresentation = 'STEAM_B' } }
  Character.CharacterList = { b1, b2, annHome, bobHome }
  Client.ClientList = { ann, bob }
  ann.Character, ann.CharacterInfo = b1, b1.Info; b1.IsRemotePlayer = true; b1.IsBot = false
  bob.Character, bob.CharacterInfo = bobHome, bobHome.Info; bobHome.IsRemotePlayer = true; bobHome.IsBot = false
  return { b1 = b1, b2 = b2, annHome = annHome, bobHome = bobHome, ann = ann, bob = bob }
end

-- Give a fake body a CharacterInfo with the revive members and a Wallet.
local function full(ch)
  local info = ch.Info
  info.Name = ch.Name; info.Character = ch; info.CauseOfDeath = nil; info.PermanentlyDead = false
  info.HealthData = 'health'; info.InventoryData = 'inventory'; info.PendingSpawnToActiveService = false
  info.penalties, info.ordersCleared = 0, 0
  function info:ApplyDeathEffects() self.penalties = self.penalties + 1; self.CauseOfDeath = nil end
  function info:ClearCurrentOrders() self.ordersCleared = self.ordersCleared + 1 end
  ch.Wallet = { Balance = 0, RewardDistribution = 0, updates = 0 }
  function ch.Wallet:ForceUpdate() self.updates = self.updates + 1 end
  function ch.Wallet:SetRewardDistribution(v) self.RewardDistribution = v end
  return ch
end

local function kill(ch, cause)
  ch.IsDead = true
  ch.CauseOfDeath = { Type = cause or CauseOfDeathType.Damage }
  ch.Info.CauseOfDeath = ch.CauseOfDeath
end

-- Calls the RemoveCharacterInfo prefix; true when it prevented the removal.
local function remove(info)
  local p = { characterInfo = info }
  quiet(W.patches['crewswap.keepdead'].fn, W.campaign.CrewManager, p)
  return p.PreventExecution == true
end

local function savePlayers() return quiet(W.patches['crewswap.restore'].fn, W.campaign, {}) end
local function savePost() return quiet(W.patches['crewswap.restore.post'].fn, W.campaign, {}) end
local function campEnd() return quiet(W.patches['crewswap.endguard'].fn, W.campaign, {}) end
local function campEndPost() return quiet(W.patches['crewswap.endguard.post'].fn, W.campaign, {}) end
local function endGame(saved) return quiet(W.patches['crewswap.endgame'].fn, Game.Server, { wasSaved = saved }) end
local function mpcEnd() return quiet(W.patches['crewswap.gameover'].fn, W.campaign, {}) end
local function endRound() return quiet(W.patches['crewswap.endround'].fn, Game.GameSession, {}) end

return {
  ['patches: EndRound and SavePlayers prefixes, End and crew-set postfixes'] = function(t)
    world()
    local r, s, g, c = W.patches['crewswap.endround'], W.patches['crewswap.restore'],
      W.patches['crewswap.gameover'], W.patches['crewswap.crewset']
    t.eq(r.class, 'Barotrauma.GameSession'); t.eq(r.method, 'EndRound'); t.eq(r.when, 'B')
    t.eq(s.class, 'Barotrauma.MultiPlayerCampaign'); t.eq(s.method, 'SavePlayers'); t.eq(s.when, 'B')
    t.eq(g.method, 'End'); t.eq(g.types[1], 'Barotrauma.CampaignMode+TransitionType'); t.eq(g.when, 'A')
    t.eq(c.class, 'Barotrauma.GameSession'); t.eq(c.method, 'GetSessionCrewCharacters'); t.eq(c.when, 'A')
    t.ok(W.accessible['Barotrauma.MultiPlayerCampaign.GameOver'], 'GameOver made accessible')
    t.eq(#CS.failed, 0)
  end,
  ['roundEnding: set by the EndRound prefix, cleared on roundStart'] = function(t)
    world(); crew()
    t.eq(CS.roundEnding, false)
    endRound()
    t.eq(CS.roundEnding, true)
    W.hooks['roundStart/crewswap.roundend.rs']()
    t.eq(CS.roundEnding, false)
  end,
  ['restore: borrowed bot released and left a bot, player back in alive home'] = function(t)
    world(); local w = crew()
    savePlayers()
    t.eq(w.ann.Character, w.annHome); t.eq(w.ann.CharacterInfo, w.annHome.Info)
    t.eq(w.b1.IsRemotePlayer, false); t.eq(w.b1.AIController.resets, 1); t.eq(w.b1.inputsCleared, 1)
    t.eq(w.bob.Character, w.bobHome)
    t.eq(W.calls[1].ch, 'nil'); t.eq(W.calls[2].ch, w.annHome)
    for _, call in ipairs(W.calls) do t.ok(call.c ~= 'Bob', 'Bob untouched') end
    t.eq(CS.blockSave, nil)
  end,
  ['restore does not touch last-played or the switch cooldown'] = function(t)
    world(); local w = crew()
    local rec = CS.reg:record(CS.sidOfInfo(w.b1.Info)); rec.last = 'STEAM_A'; rec.lastAt = 5
    savePlayers()
    t.eq(rec.last, 'STEAM_A'); t.eq(rec.lastAt, 5)
    t.eq(CS.reg.chars['sid1003'] == nil or CS.reg.chars['sid1003'].last == nil, true)
    t.eq(next(CS.lastSwitch or {}), nil)
  end,
  ['restore: whoever drives a home is released before its owner gets it back'] = function(t)
    world(); local w = crew()
    w.bob.Character = w.annHome; w.annHome.IsRemotePlayer = true; w.annHome.IsBot = false
    w.bobHome.IsRemotePlayer = false; w.bobHome.IsBot = true
    savePlayers()
    t.eq(w.ann.Character, w.annHome); t.eq(w.bob.Character, w.bobHome)
    t.eq(w.b1.IsRemotePlayer, false)
  end,
  ['restore: dead borrowed body cleared raw, dead home bound raw (never nil)'] = function(t)
    world(); local w = crew()
    w.b1.IsDead = true; w.b1.Removed = true
    w.annHome.IsDead = true
    savePlayers()
    t.eq(w.ann.Character, w.annHome); t.eq(w.ann.CharacterInfo, w.annHome.Info)
    t.eq(#W.calls, 0, 'no SetClientCharacter for dead bodies')
  end,
  ['restore: home despawned by CampaignMode.End is still bound (EndRound snapshot)'] = function(t)
    world(); local w = crew()
    w.annHome.IsDead = true
    endRound()
    -- CampaignMode.End despawns the dead home: gone from CharacterList, Removed
    w.annHome.Removed = true
    Character.CharacterList = { w.b1, w.b2, w.bobHome }
    savePlayers()
    t.eq(w.ann.Character, w.annHome); t.eq(w.ann.CharacterInfo, w.annHome.Info)
  end,
  ['restore: no home body (never spawned / benched) leaves the client with none'] = function(t)
    world(); local w = crew()
    Character.CharacterList = { w.b1, w.b2, w.bobHome }
    savePlayers()
    t.eq(w.ann.Character, nil)
    t.eq(w.b1.IsRemotePlayer, false)
  end,
  ['restore error blocks the save; pre hooks run after the restore'] = function(t)
    world(); local w = crew()
    local seen
    CS.onSavePlayersPre[#CS.onSavePlayersPre + 1] = function() seen = w.ann.Character end
    savePlayers()
    t.eq(seen, w.annHome)
    t.eq(CS.blockSave, nil)
    world(); w = crew()
    function Game.Server:SetClientCharacter() error('boom') end
    savePlayers()
    t.eq(CS.blockSave, true)
  end,
  ['a failing pre or post hook blocks the save; post hooks run in the postfix'] = function(t)
    world(); crew()
    local ran = false
    CS.onSavePlayersPost[#CS.onSavePlayersPost + 1] = function() ran = true end
    CS.onSavePlayersPre[#CS.onSavePlayersPre + 1] = function() error('pre boom') end
    savePlayers()
    t.eq(CS.blockSave, true)
    quiet(W.patches['crewswap.restore.post'].fn, W.campaign, {})
    t.eq(ran, true)
    world(); crew()
    CS.onSavePlayersPost[#CS.onSavePlayersPost + 1] = function() error('post boom') end
    quiet(W.patches['crewswap.restore.post'].fn, W.campaign, {})
    t.eq(CS.blockSave, true)
  end,
  ['inactive mod: restore is a no-op'] = function(t)
    world(); local w = crew()
    CS.active = false
    savePlayers()
    t.eq(w.ann.Character, w.b1); t.eq(#W.calls, 0)
  end,
  ['GameOver: transition path leaves vanilla value alone'] = function(t)
    world(); crew()
    Game.GameSession.IsRunning = false
    savePlayers()
    t.eq(CS.restoredBeforeEnd, false)
    W.campaign.GameOver = true
    mpcEnd()
    t.eq(W.campaign.GameOver, true)
  end,
  ['GameOver: save-and-quit uses the pre-restore crew-alive value'] = function(t)
    world(); local w = crew()
    Game.GameSession.IsRunning = true
    w.annHome.IsDead = true; w.bobHome.IsDead = true   -- both homes dead, Ann alive in a bot
    savePlayers()
    t.eq(CS.preRestoreAlive, true); t.eq(CS.restoredBeforeEnd, true)
    W.campaign.GameOver = true   -- what vanilla End computes from the restored (dead) homes
    mpcEnd()
    t.eq(W.campaign.GameOver, false)
    t.eq(CS.restoredBeforeEnd, false)
    W.campaign.GameOver = true
    mpcEnd()
    t.eq(W.campaign.GameOver, true, 'correction applies once')
  end,
  ['GameOver: nobody alive before the restore stays game over'] = function(t)
    world(); local w = crew()
    Game.GameSession.IsRunning = true
    w.b1.IsDead = true; w.bobHome.IsDead = true
    savePlayers()
    t.eq(CS.preRestoreAlive, false)
    W.campaign.GameOver = false   -- Ann's alive home would make vanilla say "not over"
    mpcEnd()
    t.eq(W.campaign.GameOver, true)
  end,
  ['crew set: released alive home added for Both and Bot, not for Player'] = function(t)
    world(); local w = crew()
    w.ann.Character = w.b1   -- Ann's home 3 is idle as a bot
    local fn = W.patches['crewswap.crewset'].fn
    local base = set({ w.b1, w.bobHome, w.b2 })
    local p = { type = 3, ReturnValue = base }
    quiet(fn, nil, p)
    t.ok(p.ReturnValue:Contains(w.annHome), 'home added')
    t.eq(#p.ReturnValue.items, 4)
    t.eq(base:Contains(w.annHome), false, 'original set untouched')
    local pb = { type = 1, ReturnValue = set({ w.b2 }) }
    quiet(fn, nil, pb)
    t.ok(pb.ReturnValue:Contains(w.annHome), 'bot set gets it too')
    t.eq(pb.ReturnValue:Contains(w.bobHome), false, 'a driven home is not a bot')
    local pp = { type = 2, ReturnValue = set({ w.b1, w.bobHome }) }
    quiet(fn, nil, pp)
    t.eq(pp.ReturnValue:Contains(w.annHome), false, 'player set unchanged')
  end,
  ['crew set: dead homes, plain bots and the mod off are left alone'] = function(t)
    world(); local w = crew()
    local fn = W.patches['crewswap.crewset'].fn
    w.annHome.IsDead = true
    local p = { type = 3, ReturnValue = set({ w.b1, w.bobHome, w.b2 }) }
    local before = p.ReturnValue
    quiet(fn, nil, p)
    t.eq(p.ReturnValue, before, 'nothing to add: ReturnValue not reassigned')
    w.annHome.IsDead = false
    CS.active = false
    quiet(fn, nil, p)
    t.eq(p.ReturnValue, before)
  end,
  ['crew set: fn returns nothing'] = function(t)
    world(); local w = crew()
    local p = { type = 3, ReturnValue = set({}) }
    local n = select('#', quiet(W.patches['crewswap.crewset'].fn, nil, p))
    t.eq(n, 0)
  end,
  ['keep guard: patches on RemoveCharacterInfo, CampaignMode.End, EndGame, SaveGame, InitRound'] = function(t)
    world()
    local k, e, ep, g = W.patches['crewswap.keepdead'], W.patches['crewswap.endguard'],
      W.patches['crewswap.endguard.post'], W.patches['crewswap.endgame']
    t.eq(k.class, 'Barotrauma.CrewManager'); t.eq(k.method, 'RemoveCharacterInfo')
    t.eq(k.types[1], 'Barotrauma.CharacterInfo'); t.eq(k.when, 'B')
    t.eq(e.class, 'Barotrauma.CampaignMode'); t.eq(e.method, 'End'); t.eq(e.when, 'B')
    t.eq(e.types[1], 'Barotrauma.CampaignMode+TransitionType'); t.eq(ep.when, 'A')
    t.eq(g.class, 'Barotrauma.Networking.GameServer'); t.eq(g.method, 'EndGame'); t.eq(g.types, nil); t.eq(g.when, 'A')
    local s, i = W.patches['crewswap.wallets.save'], W.patches['crewswap.wallets.init']
    t.eq(s.class, 'Barotrauma.SaveUtil'); t.eq(s.types[1], 'Barotrauma.CampaignDataPath'); t.eq(s.types[2], 'System.Boolean')
    t.eq(s.when, 'B')
    t.eq(i.class, 'Barotrauma.CrewManager'); t.eq(i.method, 'InitRound'); t.eq(i.when, 'A')
    t.eq(#CS.failed, 0)
  end,
  ['keep guard: only a dead non-home roster member, only while the guard is up'] = function(t)
    world(); local w = crew()
    full(w.b2); full(w.annHome); full(w.b1)
    kill(w.b2)
    t.eq(remove(w.b2.Info), false, 'no guard: vanilla removal')
    campEnd()
    t.eq(CS.keepGuard, true)
    t.eq(remove(w.b2.Info), true, 'dead bot kept')
    t.eq(CS.keptDead[w.b2.Info.ID].cause, 'other')
    t.eq(remove(w.b1.Info), false, 'alive bot (fired/benched) removed as vanilla')
    kill(w.annHome)
    t.eq(remove(w.annHome.Info), false, 'dead home (in a CCD) removed as vanilla')
    t.eq(remove(nil), false, 'monster with no info')
    kill(w.b1); w.b1.Info.PermanentlyDead = true
    t.eq(remove(w.b1.Info), false, 'permanently dead removed')
    W.bots = { w.b1.Info }
    t.eq(remove(w.b2.Info), false, 'not in the roster')
    campEndPost()
    t.eq(CS.keepGuard, false)
  end,
  ['keep guard: permadeath campaigns never keep'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    Game.ServerSettings.RespawnMode = 3
    campEnd()
    t.eq(remove(w.b2.Info), false)
    t.eq(next(CS.keptDead), nil)
  end,
  ['keep guard: mod off keeps nothing'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    CS.active = false
    campEnd()
    t.eq(CS.keepGuard, false)
    CS.keepGuard = true
    t.eq(remove(w.b2.Info), false)
  end,
  ['revive on a transition: penalty, health/inventory/orders cleared, pending spawn'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    Game.GameSession.IsRunning = false
    campEnd(); t.eq(remove(w.b2.Info), true); campEndPost()
    -- End despawned the body: Character.Remove -> info.Remove()
    w.b2.Removed = true; w.b2.Info.Character = nil
    savePlayers()
    t.eq(CS.keepGuard, true, 'guard up during SavePlayers')
    savePost()
    local i = w.b2.Info
    t.eq(CS.keepGuard, false)
    t.eq(i.penalties, 1); t.eq(i.CauseOfDeath, nil)
    t.eq(i.HealthData, nil); t.eq(i.InventoryData, nil); t.eq(i.ordersCleared, 1)
    t.eq(i.PendingSpawnToActiveService, true)
    t.eq(CS.blockSave, nil)
    endGame(true)
    t.eq(i.penalties, 1, 'saved end: no second revive')
  end,
  ['revive on save-and-quit: penalty, inventory kept, dead body unlinked, End keeps it again'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    Game.GameSession.IsRunning = true
    savePlayers()
    t.eq(remove(w.b2.Info), true, "SavePlayers' dead-bot branch")
    w.b2.Info.HealthData = 'fresh health'; w.b2.Info.InventoryData = 'fresh inventory'
    savePost()
    local i = w.b2.Info
    t.eq(i.penalties, 1); t.eq(i.HealthData, nil); t.eq(i.InventoryData, 'fresh inventory')
    t.eq(i.Character, nil, 'dead body unlinked'); t.eq(i.PendingSpawnToActiveService, true)
    -- End runs after SavePlayers here: the dead body is still there, its info now has no cause
    campEnd()
    t.eq(remove(i), true, 'still kept')
    campEndPost()
    endGame(true)
    t.eq(i.penalties, 1)
  end,
  -- on save-and-quit the JIT inlined RemoveCharacterInfo into SavePlayers' replacement, so
  -- vanilla's dead-bot removal (MPC.cs:350) never reached the keepdead prefix.
  ['save-and-quit: a dead bot removed past the keepdead patch is put back and revived'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2); w.b2.Inventory = {}
    Game.GameSession.IsRunning = true
    savePlayers()
    t.ok(CS.keptDead[w.b2.Info.ID] ~= nil, 'kept before vanilla runs')
    W.bots = { w.b1.Info }   -- vanilla removed it without the prefix seeing the call
    w.b2.Info.InventoryData = 'fresh inventory'
    savePost()
    local i = w.b2.Info
    t.eq(W.bots[2], i, 'back in the roster')
    t.eq(i.penalties, 1); t.eq(i.InventoryData, 'fresh inventory'); t.eq(i.PendingSpawnToActiveService, true)
    t.eq(CS.blockSave, nil)
  end,
  ['save-and-quit: the pre-keep follows vanilla (permadeath, disconnect, alive, no inventory)'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2, CauseOfDeathType.Disconnected); w.b2.Inventory = {}
    Game.GameSession.IsRunning = true
    savePlayers(); savePost()
    t.eq(next(CS.keptDead), nil, 'disconnected: vanilla SavePlayers keeps it itself')
    world(); w = crew()
    full(w.b2); kill(w.b2)
    savePlayers(); savePost()
    t.eq(next(CS.keptDead), nil, 'no inventory: vanilla skips the body')
    world(); w = crew()
    full(w.b2); kill(w.b2); w.b2.Inventory = {}
    Game.ServerSettings.RespawnMode = 3
    savePlayers()
    W.bots = { w.b1.Info }
    savePost()
    t.eq(next(CS.keptDead), nil, 'permadeath'); t.eq(#W.bots, 1, 'permadeath: stays removed')
  end,
  ['save-and-quit: a bot the prefix already kept is not added twice'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2); w.b2.Inventory = {}
    Game.GameSession.IsRunning = true
    savePlayers()
    t.eq(remove(w.b2.Info), true, 'patched call site')
    savePost()
    t.eq(#W.bots, 2); t.eq(w.b2.Info.penalties, 1)
  end,
  ['revive on an unsaved end: no penalty, inventory kept; not when the save was blocked'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    campEnd(); remove(w.b2.Info); campEndPost()
    endGame(false)
    local i = w.b2.Info
    t.eq(i.penalties, 0); t.eq(i.CauseOfDeath, nil); t.eq(i.HealthData, nil)
    t.eq(i.InventoryData, 'inventory'); t.eq(i.PendingSpawnToActiveService, true)
    t.eq(next(CS.keptDead), nil, 'cleared after EndGame')
    world(); w = crew()
    full(w.b2); kill(w.b2)
    campEnd(); remove(w.b2.Info); campEndPost()
    CS.saveBlocked = true
    endGame(false)
    t.eq(w.b2.Info.HealthData, 'health', 'blocked save: the campaign reverts, no revive')
  end,
  ['revive: a disconnected death takes no penalty'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2, CauseOfDeathType.Disconnected)
    campEnd(); t.eq(remove(w.b2.Info), true); campEndPost()
    t.eq(CS.keptDead[w.b2.Info.ID].cause, 'disconnected')
    savePlayers(); savePost()
    t.eq(w.b2.Info.penalties, 0); t.eq(w.b2.Info.CauseOfDeath, nil); t.eq(w.b2.Info.InventoryData, nil)
  end,
  ['revive error blocks the save'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    campEnd(); remove(w.b2.Info); campEndPost()
    function w.b2.Info:ApplyDeathEffects() error('boom') end
    savePlayers(); savePost()
    t.eq(CS.blockSave, true)
  end,
  ['roundStart clears the kept list and the guard'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    campEnd(); remove(w.b2.Info)
    W.hooks['roundStart/crewswap.roundend.keep']()
    t.eq(CS.keepGuard, false); t.eq(next(CS.keptDead), nil)
  end,
  ['wallets: End only stages bot wallets; a real save commits them, save-on-load does not'] = function(t)
    world(); local w = crew()
    full(w.b1); full(w.b2); full(w.annHome); full(w.bobHome)
    w.b1.Wallet.Balance, w.b1.Wallet.RewardDistribution = 500, 20
    w.annHome.Wallet.Balance = 77
    campEnd()
    local s1 = CS.reg:sidOf(w.b1.Info.ID)
    t.eq(CS.reg.chars[s1].wbal, nil, 'nothing committed at End')
    t.eq(CS.walletStage[s1].wbal, 500); t.eq(CS.walletStage[s1].wrd, 20)
    t.eq(CS.reg:sidOf(w.annHome.Info.ID), nil, 'home wallet left to the CCD')
    w.b1.Wallet.Balance = 650
    quiet(W.patches['crewswap.wallets.save'].fn, nil, { isSavingOnLoading = true })
    t.eq(CS.reg.chars[s1].wbal, nil, 'save-on-load commits nothing')
    quiet(W.patches['crewswap.wallets.save'].fn, nil, { isSavingOnLoading = false })
    local r1 = CS.reg.chars[s1]
    t.eq(r1.wbal, 650, 'live value at the save wins'); t.eq(r1.wrd, 20)
    t.eq(CS.reg.chars[CS.reg:sidOf(w.b2.Info.ID)].wbal, 0)
    t.eq(next(CS.walletStage), nil, 'stage cleared once committed')
  end,
  ['wallets: an unsaved end discards the staged wallets'] = function(t)
    world(); local w = crew()
    full(w.b1); full(w.b2)
    CS.reg:bind(w.b1.Info.ID, 'sB1'); CS.reg:record('sB1').wbal = 100
    w.b1.Wallet.Balance = 900   -- earned in a round that is not saved
    campEnd(); campEndPost()
    endGame(false)
    t.eq(CS.reg.chars.sB1.wbal, 100, 'record keeps the last saved balance')
    t.eq(next(CS.walletStage), nil)
    -- a later real save only takes what the bodies hold then
    w.b1.Wallet.Balance = 120
    quiet(W.patches['crewswap.wallets.save'].fn, nil, { isSavingOnLoading = false })
    t.eq(CS.reg.chars.sB1.wbal, 120)
  end,
  ['wallets: a blocked save commits nothing; roundStart clears the stage'] = function(t)
    world(); local w = crew()
    full(w.b1); full(w.b2)
    CS.reg:bind(w.b1.Info.ID, 'sB1'); CS.reg:record('sB1').wbal = 100
    w.b1.Wallet.Balance = 900
    campEnd()
    CS.blockSave = true
    quiet(W.patches['crewswap.wallets.save'].fn, nil, { isSavingOnLoading = false })
    t.eq(CS.reg.chars.sB1.wbal, 100)
    W.hooks['roundStart/crewswap.roundend.keep']()
    t.eq(next(CS.walletStage), nil)
  end,
  ['wallets: one unreadable body does not stop the others, and blocks the save'] = function(t)
    world(); local w = crew()
    full(w.b1); full(w.b2)
    w.b2.Wallet.Balance = 40
    w.b1.Wallet = setmetatable({}, { __index = function() error('wallet broke') end })
    campEnd()
    t.eq(CS.walletStage[CS.reg:sidOf(w.b2.Info.ID)].wbal, 40)
    t.eq(CS.blockSave, true)
    -- at the save itself: the write is prevented
    world(); w = crew(); full(w.b1); full(w.b2)
    w.b1.Wallet = setmetatable({}, { __index = function() error('wallet broke') end })
    local p = { isSavingOnLoading = false }
    quiet(W.patches['crewswap.wallets.save'].fn, nil, p)
    t.eq(p.PreventExecution, true); t.eq(CS.blockSave, true); t.eq(CS.saveBlocked, true)
  end,
  ['a blocked save stops the unsaved revive whichever EndGame postfix runs first'] = function(t)
    world(); local w = crew()
    full(w.b2); kill(w.b2)
    campEnd(); remove(w.b2.Info); campEndPost()
    CS.saveBlocked, CS.lastSaveBlocked = false, true   -- safety's postfix already cleared saveBlocked
    endGame(false)
    t.eq(w.b2.Info.HealthData, 'health', 'no revive')
  end,
  ['wallets: restored once at InitRound and on character.created; homes and unknowns untouched'] = function(t)
    world(); local w = crew()
    full(w.b1); full(w.b2); full(w.annHome)
    CS.reg:bind(w.b1.Info.ID, 'sB1'); CS.reg:record('sB1').wbal = 500; CS.reg:record('sB1').wrd = 30
    CS.reg:bind(w.annHome.Info.ID, 'sA'); CS.reg:record('sA').wbal = 9
    quiet(W.patches['crewswap.wallets.init'].fn, W.campaign.CrewManager, {})
    t.eq(w.b1.Wallet.Balance, 500); t.eq(w.b1.Wallet.RewardDistribution, 30); t.eq(w.b1.Wallet.updates, 1)
    t.eq(w.annHome.Wallet.Balance, 0, 'home uses vanilla CCD wallet')
    t.eq(w.b2.Wallet.Balance, 0, 'no record'); t.eq(CS.reg:sidOf(w.b2.Info.ID), nil, 'no sid minted')
    quiet(W.hooks['character.created/crewswap.wallets.created'], w.b1)
    t.eq(w.b1.Wallet.updates, 1, 'once per body')
    -- first-round bot created inline: TeamID not set yet, sid pending from the XML ctor
    local b5 = full(body{ id = 5, name = 'Bot5', TeamID = 0 })
    W.bots[#W.bots + 1] = b5.Info
    CS.pending[b5.Info.ID] = { sid = 'sB5', rec = { wbal = 42, wrd = 10 } }
    quiet(W.hooks['character.created/crewswap.wallets.created'], b5)
    t.eq(b5.Wallet.Balance, 42); t.eq(b5.Wallet.RewardDistribution, 10)
  end,
}

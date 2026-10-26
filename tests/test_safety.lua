-- server/safety.lua against fake game globals: snapshot, the checks around SavePlayers, the
-- SaveGame block, the EndGame revert and the lobby lockdown, called the way Hook.Patch would.
local registry = require('crewswap.core.registry')

local W   -- the current fake world

local function info(id, name) return { ID = id, Name = name } end

local function world()
  for _, m in ipairs({ 'game', 'patch', 'selftest', 'spawn', 'safety' }) do
    package.loaded['crewswap.server.' .. m] = nil
  end
  W = { hooks = {}, patches = {}, statics = {}, chat = {}, loads = {}, files = {}, log = {} }
  _G.SERVER = true
  _G.CharacterTeamType = { Team1 = 1 }
  _G.ChatMessageType = { Server = 3 }
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
    CreateStatic = function(name)
      W.statics[name] = W.statics[name] or { TotalTime = 0 }
      return W.statics[name]
    end,
    CreateEnumTable = function(name)
      if name:find('TryStartGameResult', 1, true) then return { Success = 0, GameAlreadyStarted = 1 } end
      return { None = 0, MidRound = 1, BetweenRounds = 2, Permadeath = 3 }
    end,
    RegisterType = function(name) return { name = name } end,
  }
  _G.File = { Exists = function(p) return W.files[p] == true end }
  _G.Client = { ClientList = {} }
  _G.Character = { CharacterList = {} }

  W.ccd, W.roster = { info(1, 'Ann'), info(2, 'Bob') }, { info(11, 'Bot1'), info(12, 'Bot2') }
  local function campaign()
    local c = setmetatable({ types = { ['Barotrauma.MultiPlayerCampaign'] = true }, increments = 0 },
      { __index = function(_, k)   -- a copied list, read live like the real private field
          if k ~= 'characterData' then return nil end
          local out = {}
          for i, ci in ipairs(W.ccd) do
            out[i] = { CharacterInfo = ci, owner = ci.owner,
                       MatchesClient = function(self, cl) return self.owner ~= nil and self.owner == cl.Name end }
          end
          return out
        end })
    c.CrewManager = { GetCharacterInfos = function() return W.roster end }
    function c:GetCharacterData(ci) for _, ccdInfo in ipairs(W.ccd) do if ccdInfo == ci then return {} end end end
    function c:IncrementAllLastUpdateIds() self.increments = self.increments + 1 end
    return c
  end
  _G.Game = {
    SaveFolder = '/saves',
    GameSession = { Campaign = nil, DataPath = { SavePath = '/saves/Multiplayer/c.save' } },
    ServerSettings = { RespawnMode = 1, IronmanModeActive = false },
    SendMessage = function(text) W.chat[#W.chat + 1] = text end,
  }
  setmetatable(Game.GameSession, { __index = function(_, k) if k == 'Campaign' then return W.campaign end end })
  W.campaign = campaign()
  W.statics['Barotrauma.MultiPlayerCampaign'] = {
    -- as Harmony runs it: prefix, the load (whose save-on-load needs the mod active), postfix
    -- Inside the load, identity's MPC.Load postfix fills CS.dupes, then GameSession's ctor runs
    -- LoadNewLevel -> LoadInitialLevel -> GameServer.TryStartGame (server MPC.cs:166-171) before
    -- LoadCampaign returns: the lobby prefix sees that call.
    LoadCampaign = function(path, client)
      W.patches['crewswap.safety.load.pre'].fn(nil, {})
      CS.dupes = W.nextDupes or {}
      W.nextDupes = nil
      local tp = {}
      W.patches['crewswap.safety.lobby'].fn(nil, tp)
      W.loads[#W.loads + 1] = { path = path, client = client, lockdownDuring = CS.lockdown,
                                startRefused = tp.PreventExecution == true }
      W.campaign = campaign()
      W.patches['crewswap.safety.load'].fn(nil, {})
    end,
  }

  local reg = registry.new()
  _G.CS = { active = true, versionOk = true, lockdown = false, reg = reg, failed = {}, dupes = {},
            onSavePlayersPre = {}, onSavePlayersPost = {} }
  function CS.fail(r) CS.failed[#CS.failed + 1] = r; CS.active = false; CS.lockdown = true end
  function CS.recomputeActive() CS.active = CS.versionOk and not CS.lockdown; return CS.active end
  function CS.sidOfInfo(ci)
    local sid = reg:sidOf(ci.ID)
    if sid == nil then sid = 'sid' .. ci.ID; reg:bind(ci.ID, sid); reg:record(sid) end
    return sid
  end
  local realPrint = print
  print = function(s) W.log[#W.log + 1] = s end
  local ok, S = pcall(require, 'crewswap.server.safety')
  print = realPrint
  assert(ok, S)
  return S
end

local function quiet(fn, ...)
  local realPrint = print
  print = function(s) W.log[#W.log + 1] = s end
  local r = table.pack(pcall(fn, ...))
  print = realPrint
  assert(r[1], r[2])
  return table.unpack(r, 2, r.n)
end

local function logHas(s)
  for _, l in ipairs(W.log) do if tostring(l):find(s, 1, true) then return true end end
  return false
end

local function roundStart() quiet(W.hooks['roundStart/crewswap.safety.rs']) end
local function pre() for _, fn in ipairs(CS.onSavePlayersPre) do quiet(fn, W.campaign) end end
local function post() for _, fn in ipairs(CS.onSavePlayersPost) do quiet(fn, W.campaign) end end
local function call(id, instance, p)
  p = p or {}
  local r = quiet(W.patches[id].fn, instance, p)
  return p, r
end
local function save(onLoading)
  return (call('crewswap.safety.save', nil, { isSavingOnLoading = onLoading == true }))
end

return {
  ['safety: patches, signatures and 20 backups'] = function(t)
    world()
    t.eq(W.statics['Barotrauma.SaveUtil'].MaxBackupCount, 20)
    t.eq(#CS.failed, 0)
    local s = W.patches['crewswap.safety.save']
    t.eq(s.class, 'Barotrauma.SaveUtil'); t.eq(s.method, 'SaveGame'); t.eq(s.when, 'B')
    t.eq(table.concat(s.types, ','), 'Barotrauma.CampaignDataPath,System.Boolean')
    local r = W.patches['crewswap.safety.revert']
    t.eq(r.class, 'Barotrauma.Networking.GameServer'); t.eq(r.method, 'EndGame'); t.eq(r.types, nil); t.eq(r.when, 'A')
    local l = W.patches['crewswap.safety.lobby']
    t.eq(l.method, 'TryStartGame'); t.eq(l.types, nil); t.eq(l.when, 'B')
    local ld = W.patches['crewswap.safety.load']
    t.eq(ld.method, 'LoadCampaign'); t.eq(ld.when, 'A')
    t.eq(table.concat(ld.types, ','), 'Barotrauma.CampaignDataPath,Barotrauma.Networking.Client')
    local f = W.patches['crewswap.safety.fire']
    t.eq(f.class, 'Barotrauma.CrewManager'); t.eq(f.method, 'FireCharacter'); t.eq(f.when, 'B')
    t.eq(W.patches['crewswap.safety.kill'].method, 'KillProjSpecific')
    t.eq(#CS.onSavePlayersPre, 1); t.eq(#CS.onSavePlayersPost, 1)
  end,
  ['safety: clean round saves normally'] = function(t)
    world()
    roundStart()
    t.ok(CS.snap ~= nil)
    t.eq(#CS.snap.ccd, 2); t.eq(#CS.snap.roster, 2)
    W.roster[#W.roster + 1] = info(13, 'NewHire')
    pre(); post()
    t.eq(CS.blockSave, false)
    local p = save()
    t.eq(p.PreventExecution, nil); t.eq(CS.saveBlocked, false)
    call('crewswap.safety.revert')
    t.eq(#W.loads, 0); t.eq(CS.lockdown, false)
  end,
  ['safety: borrowed bot folded into a CCD blocks the save and reloads'] = function(t)
    world()
    roundStart()
    -- the restore failed: Ann's CCD now holds Bot1, which SavePlayers took out of the roster
    W.ccd[1] = W.roster[1]
    table.remove(W.roster, 1)
    post()
    t.eq(CS.blockSave, true)
    t.ok(logHas('INTEGRITY FAIL (post-save): missing sid1 (Ann)'), table.concat(W.log, '\n'))
    t.ok(logHas('INTEGRITY FAIL (post-save): moved sid11 (Bot1)'))
    t.eq(save(true).PreventExecution, nil, 'save-on-load is never blocked')
    t.eq(CS.saveBlocked, false)
    t.eq(save().PreventExecution, true)
    t.eq(CS.saveBlocked, true)
    call('crewswap.safety.revert')
    t.eq(#W.loads, 1)
    t.eq(W.loads[1].path, Game.GameSession.DataPath); t.eq(W.loads[1].client, nil)
    t.eq(W.loads[1].lockdownDuring, false, 'the reload\'s save-on-load runs unlocked')
    t.eq(W.campaign.increments, 1)
    t.eq(CS.lockdown, true); t.eq(CS.integrityLock, true); t.eq(CS.active, false)
    t.eq(CS.saveBlocked, false); t.eq(CS.blockSave, false)
    t.ok(logHas('INTEGRITY ALARM'))
    local alarmAt, noticeAt
    for i, c in ipairs(W.chat) do
      if c:find('^%[CrewSwap%] Integrity check failed: the round was not saved') then alarmAt = i end
      if c:find("can't start", 1, true) then noticeAt = i end
    end
    t.ok(alarmAt ~= nil, table.concat(W.chat, '\n'))
    t.ok(noticeAt ~= nil and noticeAt > alarmAt, 'the reload\'s round start is refused after the alarm')
  end,
  ['safety: lastSaveBlocked records the last real save, for order-independent EndGame postfixes'] = function(t)
    world()
    roundStart()
    CS.blockSave = true
    save(true)
    t.eq(CS.lastSaveBlocked, false, 'save-on-load does not count')
    save()
    t.eq(CS.lastSaveBlocked, true)
    call('crewswap.safety.revert')
    t.eq(CS.lastSaveBlocked, true, 'kept past the revert postfix')
    roundStart()
    t.eq(CS.lastSaveBlocked, false)
    save()
    t.eq(CS.lastSaveBlocked, false)
  end,
  ['safety: lockdown refuses round start until cleared'] = function(t)
    world()
    local p, r = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, nil); t.eq(r, nil)
    CS.lockdown, CS.integrityLock = true, true
    p, r = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, true); t.eq(r, 1)
    t.ok(W.chat[#W.chat]:find("can't start", 1, true))
    CS.lockdown = false   -- !crewswap check passed
    p, r = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, nil); t.eq(r, nil)
  end,
  ['safety: the revert reload cannot start a round (LoadCampaign calls TryStartGame)'] = function(t)
    world()
    roundStart()
    CS.blockSave = true
    save()
    call('crewswap.safety.revert')
    t.eq(#W.loads, 1)
    t.eq(W.loads[1].startRefused, true, 'the round the reload starts is refused')
    t.eq(W.loads[1].lockdownDuring, false, 'the save-on-load still runs unlocked')
    t.eq(CS.lockdown, true); t.eq(CS.integrityLock, true); t.eq(CS.active, false)
    t.ok(logHas('round start refused: integrity lockdown'), table.concat(W.log, '\n'))
    local p, r = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, true); t.eq(r, 1)
  end,
  ['safety: a load that finds duplicate ids cannot start a round'] = function(t)
    world()
    W.nextDupes = { 'sid1' }
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'dupes' }, nil)
    t.eq(W.loads[1].startRefused, true)
    t.eq(CS.lockdown, true); t.eq(CS.integrityLock, true)
    t.ok(logHas('INTEGRITY FAIL (load): duplicate sid1'))
    local p = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, true)
  end,
  ['safety: a clean load still starts its round'] = function(t)
    world()
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'clean' }, nil)
    t.eq(W.loads[1].startRefused, false)
    t.eq(CS.lockdown, false)
    -- the duplicate refusal ends with that load: the next clean load starts normally
    world()
    W.nextDupes = { 'sid1' }
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'dupes' }, nil)
    CS.lockdown, CS.integrityLock = false, false   -- !crewswap check passed
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'clean' }, nil)
    t.eq(W.loads[2].startRefused, false)
  end,
  ['safety: a round start never forgets an integrity lock still in force'] = function(t)
    world()
    CS.lockdown, CS.integrityLock = true, true
    roundStart()
    t.eq(CS.integrityLock, true, '!crewswap check must still be able to lift it')
    CS.lockdown = false
    roundStart()
    t.eq(CS.integrityLock, false)
  end,
  ['safety: a version/patch lockdown never holds the lobby'] = function(t)
    world()
    CS.fail('patch x')
    local p, r = call('crewswap.safety.lobby')
    t.eq(p.PreventExecution, nil); t.eq(r, nil)
  end,
  ['safety: fired and permadead removals pass, an unexplained one fails'] = function(t)
    world()
    roundStart()
    call('crewswap.safety.fire', nil, { characterInfo = W.roster[2] })
    table.remove(W.roster, 2)
    pre()
    t.eq(CS.blockSave, false, 'fired')
    Game.ServerSettings.RespawnMode = 3
    local bot = { Info = W.roster[1], IsHuman = true, TeamID = 1, Removed = false }
    call('crewswap.safety.kill', bot, { causeOfDeath = CauseOfDeathType.Damage })
    table.remove(W.roster, 1)
    post()
    t.eq(CS.blockSave, false, 'permadead')
    -- outside Permadeath a vanished bot is a failure
    world()
    roundStart()
    local bot2 = { Info = W.roster[1], IsHuman = true, TeamID = 1, Removed = false }
    call('crewswap.safety.kill', bot2, { causeOfDeath = CauseOfDeathType.Damage })
    table.remove(W.roster, 1)
    post()
    t.eq(CS.blockSave, true)
  end,
  ['safety: adopted home moves roster to CCD legitimately'] = function(t)
    world()
    roundStart()
    Game.ServerSettings.RespawnMode = 3
    call('crewswap.safety.kill', { Info = W.ccd[1], IsHuman = true, TeamID = 1, Removed = false },
      { causeOfDeath = CauseOfDeathType.Damage })
    CS.noteLegit('adopted', W.roster[1].ID)
    W.ccd[1] = W.roster[1]   -- vanilla keeps it in the roster until SavePlayers
    pre()
    t.eq(CS.blockSave, false)
    table.remove(W.roster, 1)
    post()
    t.eq(CS.blockSave, false)
    t.err(function() CS.noteLegit('bogus', 1) end)
  end,
  ['safety: a home left permanently dead by an earlier round may be replaced'] = function(t)
    world()
    Game.ServerSettings.RespawnMode = 3
    W.ccd[1].PermanentlyDead = true   -- Ann died for good last round; SavePlayers kept the CCD
    roundStart()
    -- round 2: Ann adopts Bot1 (SetClientCharacterData drops the dead CCD)
    CS.noteLegit('adopted', W.roster[1].ID)
    W.ccd[1] = table.remove(W.roster, 1)
    pre(); post()
    t.eq(CS.blockSave, false, table.concat(CS.lastProblems, '; '))
    -- the same state after a load (failed round / backup) is a fresh baseline too
    world()
    Game.ServerSettings.RespawnMode = 3
    W.ccd[1].PermanentlyDead = true
    call('crewswap.safety.load')
    W.ccd[1] = table.remove(W.roster, 1)
    CS.noteLegit('adopted', W.ccd[1].ID)
    pre()
    t.eq(CS.blockSave, false, table.concat(CS.lastProblems, '; '))
  end,
  ['safety: a CCD discarded by vanilla ("create new character") is legit'] = function(t)
    world()
    local d = W.patches['crewswap.safety.discard']
    t.eq(d.class, 'Barotrauma.MultiPlayerCampaign'); t.eq(d.method, 'DiscardClientCharacterData'); t.eq(d.when, 'B')
    W.ccd[1].owner = 'Ann'
    roundStart()
    call('crewswap.safety.discard', W.campaign, { client = { Name = 'Ann' } })
    table.remove(W.ccd, 1)
    pre(); post()
    t.eq(CS.blockSave, false, table.concat(CS.lastProblems, '; '))
    -- Bob's CCD was not discarded: removing it still fails
    world()
    W.ccd[1].owner = 'Ann'
    roundStart()
    call('crewswap.safety.discard', W.campaign, { client = { Name = 'Ann' } })
    table.remove(W.ccd, 2)
    pre()
    t.eq(CS.blockSave, true)
  end,
  ['safety: force-integrity-fail file makes runCheck fail'] = function(t)
    world()
    roundStart()
    t.eq(quiet(CS.runCheck, 'x'), true)
    W.files['/saves/CrewSwap/force-integrity-fail'] = true
    t.eq(quiet(CS.runCheck, 'x'), false)
    t.ok(logHas('INTEGRITY FAIL (x): forced by /CrewSwap/force-integrity-fail'))
  end,
  ['safety: duplicate ids at load lock down; a clean load re-baselines'] = function(t)
    world()
    roundStart()
    W.roster[#W.roster + 1] = info(13, 'Hire')   -- not in the round-start snapshot
    call('crewswap.safety.load')
    t.eq(CS.lockdown, false)
    t.eq(#CS.snap.roster, 3)
    CS.dupes = { 'sid1' }
    call('crewswap.safety.load')
    t.eq(CS.lockdown, true); t.eq(CS.integrityLock, true); t.eq(CS.active, false)
    t.ok(logHas('INTEGRITY FAIL (load): duplicate sid1 (Ann)'))
  end,
  ['safety: a backup load during a lockdown runs unlocked and stays locked'] = function(t)
    world()
    CS.lockdown, CS.integrityLock = true, true
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'backup' }, nil)
    t.eq(W.loads[1].lockdownDuring, false)
    t.eq(W.loads[1].startRefused, true, 'the backup load does not start a round while locked')
    t.eq(CS.lockdown, true); t.eq(CS.active, false)
    -- a CS.fail lockdown is not lifted for loads
    world()
    CS.fail('patch x')
    quiet(W.statics['Barotrauma.MultiPlayerCampaign'].LoadCampaign, { SavePath = 'backup' }, nil)
    t.eq(W.loads[1].lockdownDuring, true)
    t.eq(CS.lockdown, true)
  end,
  ['safety: round start clears stale flags and legit removals'] = function(t)
    world()
    roundStart()
    call('crewswap.safety.fire', nil, { characterInfo = W.roster[2] })
    CS.blockSave, CS.saveBlocked = true, true
    roundStart()
    t.eq(CS.blockSave, false); t.eq(CS.saveBlocked, false)
    table.remove(W.roster, 2)
    pre()
    t.eq(CS.blockSave, true, 'last round\'s firing no longer excuses a removal')
  end,
  ['safety: a bot fired in round 1 does not fail round 2'] = function(t)
    world()
    roundStart()
    call('crewswap.safety.fire', nil, { characterInfo = W.roster[2] })
    table.remove(W.roster, 2)
    pre(); post()
    t.eq(CS.blockSave, false, 'round 1')
    t.eq(save().PreventExecution, nil)
    call('crewswap.safety.revert')
    t.ok(CS.reg.chars.sid12 ~= nil, 'the record is kept for the session')
    -- the transition does not reload: round 2 starts on the same registry
    roundStart()
    pre(); post()
    t.eq(CS.blockSave, false, 'round 2: ' .. table.concat(CS.lastProblems, '; '))
    t.eq(save().PreventExecution, nil)
    call('crewswap.safety.revert')
    t.eq(#W.loads, 0); t.eq(CS.lockdown, false)
    -- round 3: an unexplained removal is still caught
    roundStart()
    table.remove(W.roster, 1)
    pre()
    t.eq(CS.blockSave, true)
    t.ok(logHas('INTEGRITY FAIL (pre-save): missing sid11 (Bot1)'))
  end,
  ['safety: a Permadeath bot death in round 1 does not fail round 2'] = function(t)
    world()
    Game.ServerSettings.RespawnMode = 3
    roundStart()
    call('crewswap.safety.kill', { Info = W.roster[1], IsHuman = true, TeamID = 1, Removed = false },
      { causeOfDeath = CauseOfDeathType.Damage })
    table.remove(W.roster, 1)
    pre(); post()
    t.eq(CS.blockSave, false, 'round 1')
    call('crewswap.safety.revert')
    roundStart()
    pre(); post()
    t.eq(CS.blockSave, false, 'round 2: ' .. table.concat(CS.lastProblems, '; '))
    t.eq(save().PreventExecution, nil)
    call('crewswap.safety.revert')
    t.eq(#W.loads, 0); t.eq(CS.lockdown, false)
  end,
  ['safety: inactive mod runs no check and takes no snapshot'] = function(t)
    world()
    CS.versionOk = false
    roundStart()
    t.eq(CS.snap, nil)
    W.roster = {}
    pre(); post()
    t.eq(CS.blockSave, false)
  end,
}

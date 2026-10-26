-- Safety net. Vanilla's rolling save backups are raised to 20. Every crew member is
-- snapshotted at round start; the integrity check runs after the pre-save restore and again after
-- vanilla SavePlayers. On a failure the disk write is prevented (SaveUtil.SaveGame prefix), the
-- campaign is reloaded from the last good save in the GameServer.EndGame postfix, and switching
-- and new rounds stay off until an admin runs `!crewswap check`.
if not SERVER then return end
local integrity = require('crewswap.core.integrity')
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')

local S = { errors = {} }

S.ALARM = '[CrewSwap] Integrity check failed: the round was not saved and the campaign was reloaded '
  .. 'from the last good save. Switching and new rounds are off until an admin runs !crewswap check.'
S.LOAD_ALARM = '[CrewSwap] Integrity check failed: this save has the same crew member twice. '
  .. 'Switching and new rounds are off until an admin runs !crewswap check or loads a backup.'
S.LOBBY_NOTICE = "[CrewSwap] The round can't start: an integrity check failed. An admin must run !crewswap check."
S.FORCE_FILE = '/CrewSwap/force-integrity-fail'   -- dev-only trigger, under Game.SaveFolder

CS.blockSave = CS.blockSave or false     -- a check failed: the next real save must not be written
CS.saveBlocked = CS.saveBlocked or false -- a save was prevented: EndGame reloads the campaign
-- Whether the last real save was blocked; unlike saveBlocked it survives the EndGame postfix
-- below, so other EndGame postfixes read it whatever order they run in. Cleared at round start.
CS.lastSaveBlocked = CS.lastSaveBlocked
CS.integrityLock = CS.integrityLock or false   -- this lockdown came from an integrity failure
CS.snap = CS.snap                          -- integrity.snapshot of the crew at round start / load
CS.lastProblems = CS.lastProblems or {}
CS.onSavePlayersPre = CS.onSavePlayersPre or {}
CS.onSavePlayersPost = CS.onSavePlayersPost or {}

-- Legitimate removals this round, by CharacterInfo.ID (converted to sids at check time).
local legitIds
local function resetLegit() legitIds = { permadead = {}, fired = {}, discarded = {}, adopted = {} } end
resetLegit()

local names = {}   -- [sid] = character name, for readable alarm lines

local function log(s) print('[CrewSwap] safety: ' .. s) end

local function announce(text)
  local ok, err = pcall(function() Game.SendMessage(text, ChatMessageType.Server) end)
  if not ok then log('chat failed: ' .. tostring(err)) end
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      S.errors[name] = (S.errors[name] or 0) + 1
      log(name .. ' error: ' .. tostring(err))
    end
  end
end

-- kind = 'permadead' | 'fired' | 'discarded' | 'adopted'
function CS.noteLegit(kind, infoId)
  if legitIds[kind] == nil then error('noteLegit: unknown kind ' .. tostring(kind)) end
  if infoId ~= nil then legitIds[kind][infoId] = true end
end

-- ---------- backups ----------

S.backupsSet = pcall(function()
  LuaUserData.RegisterType('Barotrauma.SaveUtil')
  LuaUserData.CreateStatic('Barotrauma.SaveUtil').MaxBackupCount = 20
end)
if not S.backupsSet then CS.fail('could not raise SaveUtil.MaxBackupCount to 20') end

-- ---------- the check ----------

-- Plain sid lists of the live campaign. sidOfInfo mints and binds an id for a brand-new hire or
-- home, so no entry is ever id-less. `table` is read last: minting adds records.
function S.stores(campaign)
  local st = { ccd = {}, roster = {}, table = {} }
  local function add(where, info)
    if info == nil then return end
    local sid = CS.sidOfInfo(info)
    names[sid] = tostring(info.Name)
    st[where][#st[where] + 1] = sid
  end
  for _, cd in ipairs(G.list(campaign.characterData)) do add('ccd', cd.CharacterInfo) end
  local cm = campaign.CrewManager
  if cm ~= nil then
    for _, ci in ipairs(G.list(cm:GetCharacterInfos(true))) do add('roster', ci) end
  end
  for sid in pairs(CS.reg.chars) do st.table[#st.table + 1] = sid end
  table.sort(st.table)
  return st
end

local function legitSids()
  local out = {}
  for kind, ids in pairs(legitIds) do
    out[kind] = {}
    for id in pairs(ids) do
      local sid = CS.reg:sidOf(id)
      if sid ~= nil then out[kind][sid] = true end
    end
  end
  return out
end

local function forced()
  local ok, exists = pcall(function() return File.Exists(Game.SaveFolder .. S.FORCE_FILE) end)
  return ok and exists == true
end

local function readable(problem)
  local sid = problem:match(' (%S+)$')
  local n = sid and names[sid]
  return n and (problem .. ' (' .. n .. ')') or problem
end

-- → ok. Logs every problem; the callers decide what a failure blocks.
function CS.runCheck(label)
  label = tostring(label or 'check')
  local ok, problems
  local ran, err = pcall(function()
    local campaign = G.campaign()
    if campaign == nil then ok, problems = true, {}; return end
    local stores = S.stores(campaign)   -- binds new infos first: legitSids looks them up
    ok, problems = integrity.check(CS.snap, stores, legitSids())
  end)
  if not ran then ok, problems = false, { 'check error: ' .. tostring(err) } end
  if forced() then
    ok = false
    problems[#problems + 1] = 'forced by ' .. S.FORCE_FILE
  end
  CS.lastProblems = problems
  if ok then
    log('integrity ' .. label .. ': ok')
  else
    for _, pr in ipairs(problems) do print('[CrewSwap] INTEGRITY FAIL (' .. label .. '): ' .. readable(pr)) end
    announce('[CrewSwap] Integrity check failed (' .. label .. '): ' .. #problems
      .. ' problem(s), see the server console.')
  end
  return ok
end

local function takeSnapshot(why)
  CS.snap = nil
  local campaign = G.campaign()
  if campaign == nil or not CS.versionOk or Game.ServerSettings.IronmanModeActive == true then return end
  local st = S.stores(campaign)
  CS.snap = integrity.snapshot(st)
  -- A home that died for good in an earlier round keeps its CCD until it is replaced (adoption,
  -- takeover); its removal then is the permadeath this round's kill hook never saw.
  for _, cd in ipairs(G.list(campaign.characterData)) do
    local ci = cd.CharacterInfo
    if ci ~= nil and ci.PermanentlyDead == true then CS.noteLegit('permadead', ci.ID) end
  end
  log(why .. ' snapshot: ' .. #st.ccd .. ' player character(s), ' .. #st.roster .. ' bot(s)')
end

local function lock(alarm)
  CS.lockdown = true
  CS.integrityLock = true
  CS.recomputeActive()
  print('[CrewSwap] INTEGRITY ALARM: ' .. alarm)
  announce(alarm)
end

-- ---------- round start ----------

Hook.Add('roundStart', 'crewswap.safety.rs', safe('roundStart', function()
  CS.blockSave, CS.saveBlocked, CS.lastSaveBlocked = false, false, false
  -- An integrity lock still in force stays marked, or !crewswap check could never lift it.
  if not CS.lockdown then CS.integrityLock = false end
  resetLegit()
  if not CS.recomputeActive() then CS.snap = nil; return end
  takeSnapshot('round-start')
end))

-- ---------- legitimate removals ----------

-- Every crew death in Permadeath is permanent (driven or not: vanilla drops a dead bot at End).
P.patch('crewswap.safety.kill', 'Barotrauma.Character', 'KillProjSpecific', nil, safe('kill', function(ch, p)
  if not CS.active or not G.isPermadeath() then return end
  if p['causeOfDeath'] == CauseOfDeathType.Disconnected then return end
  if ch.Info ~= nil and G.isCrew(ch) then CS.noteLegit('permadead', ch.Info.ID) end
end), Hook.HookMethodType.After)

P.patch('crewswap.safety.fire', 'Barotrauma.CrewManager', 'FireCharacter', { 'Barotrauma.CharacterInfo' },
  safe('fire', function(_, p)
    if not CS.active then return end
    local info = p['characterInfo']
    if info ~= nil then CS.noteLegit('fired', info.ID) end
  end), Hook.HookMethodType.Before)

-- Vanilla "create new character" (Talents tab, MidRound) and TryTakeOverBot drop the client's CCD.
P.patch('crewswap.safety.discard', 'Barotrauma.MultiPlayerCampaign', 'DiscardClientCharacterData', nil,
  safe('discard', function(campaign, p)
    if not CS.active then return end
    local client = p['client']
    if client == nil then return end
    for _, cd in ipairs(G.list(campaign.characterData)) do
      if cd.CharacterInfo ~= nil and cd:MatchesClient(client) then CS.noteLegit('discarded', cd.CharacterInfo.ID) end
    end
  end), Hook.HookMethodType.Before)

-- ---------- run the check around SavePlayers ----------

CS.onSavePlayersPre[#CS.onSavePlayersPre + 1] = function()
  if CS.active and not CS.runCheck('pre-save') then CS.blockSave = true end
end
CS.onSavePlayersPost[#CS.onSavePlayersPost + 1] = function()
  if CS.active and not CS.runCheck('post-save') then CS.blockSave = true end
end

-- ---------- block the write ----------

-- The save-on-load (isSavingOnLoading) only re-writes what was just loaded: never blocked.
P.patch('crewswap.safety.save', 'Barotrauma.SaveUtil', 'SaveGame', { 'Barotrauma.CampaignDataPath', 'System.Boolean' },
  function(_, p)
    if not p['isSavingOnLoading'] then CS.lastSaveBlocked = CS.blockSave == true end
    if CS.blockSave and not p['isSavingOnLoading'] then
      p.PreventExecution = true
      CS.saveBlocked = true
      pcall(log, 'INTEGRITY: save blocked, nothing was written')
    end
  end, Hook.HookMethodType.Before)

-- ---------- revert ----------

-- Memory already holds what SavePlayers did to it (folded CCDs, deleted inventories), so reload
-- the last good save the way vanilla's failed-round branch does (MPC.cs:438-443).
P.patch('crewswap.safety.revert', 'Barotrauma.Networking.GameServer', 'EndGame', nil, safe('revert', function()
  local blocked = CS.saveBlocked
  CS.saveBlocked, CS.blockSave = false, false
  if not blocked then return end
  -- Lock BEFORE the reload: on the server LoadCampaign starts the next round itself
  -- (GameSession ctor -> LoadNewLevel -> LoadInitialLevel -> TryStartGame, server MPC.cs:166-171)
  -- before it returns, so a lock set afterwards never reaches the lobby refusal. The load prefix
  -- below still lifts the lockdown for the load, so its save-on-load writes the ids.
  lock(S.ALARM)
  local ok, err = pcall(function()
    LuaUserData.CreateStatic('Barotrauma.MultiPlayerCampaign').LoadCampaign(Game.GameSession.DataPath, nil)
    local campaign = G.campaign()
    if campaign ~= nil then campaign:IncrementAllLastUpdateIds() end
  end)
  if not ok then log('INTEGRITY: reload failed: ' .. tostring(err) .. ' (load a backup from the lobby)') end
end), Hook.HookMethodType.After)

-- A load during a lockdown (an admin loading a backup) re-saves straight away; lift the lock for
-- the load so that save carries the ids, and put it back in the postfix.
local heldLock = false
S.loading = false   -- inside LoadCampaign: CS.dupes then describes the save being loaded
P.patch('crewswap.safety.load.pre', 'Barotrauma.MultiPlayerCampaign', 'LoadCampaign',
  { 'Barotrauma.CampaignDataPath', 'Barotrauma.Networking.Client' }, function()
    S.loading = true
    heldLock = CS.lockdown == true and CS.integrityLock == true
    if heldLock then CS.lockdown = false end
  end, Hook.HookMethodType.Before)

-- After every campaign load (failed round, backup, the revert above): new baseline; a save that
-- carries one id on two crew members locks down at once.
P.patch('crewswap.safety.load', 'Barotrauma.MultiPlayerCampaign', 'LoadCampaign',
  { 'Barotrauma.CampaignDataPath', 'Barotrauma.Networking.Client' }, safe('load', function()
    S.loading = false
    if heldLock then
      heldLock = false
      CS.lockdown = true
      CS.recomputeActive()
    end
    resetLegit()
    takeSnapshot('load')
    if CS.dupes ~= nil and #CS.dupes > 0 then
      for _, sid in ipairs(CS.dupes) do print('[CrewSwap] INTEGRITY FAIL (load): ' .. readable('duplicate ' .. sid)) end
      lock(S.LOAD_ALARM)
    end
  end), Hook.HookMethodType.After)

-- ---------- lockdown holds the lobby ----------

LuaUserData.RegisterType('Barotrauma.Networking.GameServer+TryStartGameResult')
local TryStartGameResult = LuaUserData.CreateEnumTable('Barotrauma.Networking.GameServer+TryStartGameResult')

-- Also refused inside a LoadCampaign, which calls TryStartGame before its postfix runs: while
-- an integrity lock is held for that load (lockdown lifted, integrityLock kept), or when identity's
-- MPC.Load postfix has just found duplicate ids in the save (the postfix locks down afterwards).
function S.holdsLobby()
  if CS.integrityLock and (CS.lockdown or heldLock) then return true end
  return S.loading == true and CS.dupes ~= nil and #CS.dupes > 0
end

-- Non-void: the result is returned from Lua; otherwise a bare return keeps vanilla.
P.patch('crewswap.safety.lobby', 'Barotrauma.Networking.GameServer', 'TryStartGame', nil, function(_, p)
  if not S.holdsLobby() then return end
  p.PreventExecution = true
  pcall(log, 'round start refused: integrity lockdown')
  announce(S.LOBBY_NOTICE)
  return TryStartGameResult.GameAlreadyStarted
end, Hook.HookMethodType.Before)

-- ---------- self-test ----------

local ST = require('crewswap.server.selftest')
ST.add('safety-patches', function()
  for _, id in ipairs({ 'crewswap.safety.kill', 'crewswap.safety.fire', 'crewswap.safety.discard', 'crewswap.safety.save',
                        'crewswap.safety.revert', 'crewswap.safety.load.pre', 'crewswap.safety.load',
                        'crewswap.safety.lobby' }) do
    if P.errors[id] ~= nil then return false, id .. ': ' .. P.errors[id] end
  end
  return true
end)
ST.add('safety-backups', function()
  local n = LuaUserData.CreateStatic('Barotrauma.SaveUtil').MaxBackupCount
  if n ~= 20 then return false, 'MaxBackupCount is ' .. tostring(n) end
  return true
end)
ST.add('safety-api', function()
  local v = TryStartGameResult.GameAlreadyStarted
  if v == nil then return false, 'TryStartGameResult.GameAlreadyStarted is nil' end
  local d = LuaUserData.RegisterType('Barotrauma.MultiPlayerCampaign')
  for _, m in ipairs({ 'LoadCampaign', 'IncrementAllLastUpdateIds', 'characterData' }) do
    if not LuaUserData.HasMember(d, m) then return false, 'MultiPlayerCampaign has no ' .. m end
  end
  return true
end)
-- The check on whatever is loaded (no campaign: trivially ok), without touching save state.
ST.add('safety-runcheck', function()
  local was = CS.lastProblems
  local ok = CS.runCheck('selftest')
  if forced() then return 'skip', 'force-integrity-fail present' end
  CS.lastProblems = was
  if not ok then return false, 'runCheck failed on the loaded campaign' end
  return true
end)

return S

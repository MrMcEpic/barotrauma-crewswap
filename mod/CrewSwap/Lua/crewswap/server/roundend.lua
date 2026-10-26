-- Round end. Before vanilla saves, put storage back into the shape it expects: every client
-- back in their own home body, borrowed bodies left as bots. Then undo the GameOver skew that
-- causes on save-and-quit (GameOver must never be set falsely), and count released home bodies
-- as crew so idle homes get what bots get (parity).
-- Design choice: no save-and-quit deferral, so on save-and-quit mission pay goes to home bodies.
if not SERVER then return end
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')
local SW = require('crewswap.server.switch')

local R = { errors = {} }   -- errors[name] = callback errors so far (the selftest reads it)

CS.roundEnding = false        -- true from the GameSession.EndRound prefix until roundStart
CS.preRestoreAlive = false    -- some in-game client had a living character before the restore
CS.restoredBeforeEnd = false  -- the restore ran before MultiPlayerCampaign.End (save-and-quit)
CS.onSavePlayersPre = CS.onSavePlayersPre or {}    -- fn(campaign), after the restore
CS.onSavePlayersPost = CS.onSavePlayersPost or {}  -- fn(campaign), in the SavePlayers postfix

-- [accountKey] = the home body as it was at EndRound. CampaignMode.End despawns dead bodies
-- before SavePlayers on the transition path, so G.homeBodyOf (a live lookup) can no longer find a dead home.
local endHomes = {}

local function log(s) print('[CrewSwap] roundend: ' .. s) end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      R.errors[name] = (R.errors[name] or 0) + 1
      log(name .. ' error: ' .. tostring(err))
    end
  end
end

-- A lockdown can come after players switched, and the save still needs the vanilla shape.
local function engaged() return CS.active == true or CS.lockdown == true end

local function homeBody(c) return G.homeBodyOf(c) or endHomes[G.accountKey(c)] end

local function gone(ch) return ch.IsDead or ch.Removed end

function CS.restoreAll()
  local clients = G.clients()
  -- (1) Everyone out of a body that isn't their home. SetClientCharacter(c, nil) is required
  -- for a live body: SavePlayers snapshots items only for bots, then deletes every inventory.
  for _, c in ipairs(clients) do
    local b, h = c.Character, homeBody(c)
    if b ~= nil and b ~= h then
      if gone(b) then
        c.Character = nil
      else
        SW.release(c)
        if c.Character == b then error('could not release ' .. tostring(c.Name)) end
      end
    end
  end
  -- (2) An alive home goes back to its owner. (3) A dead home is bound raw, never left nil:
  -- vanilla builds a dead player's CCD item data from client.Character. (4) No home body
  -- (never spawned, benched): the client keeps no character.
  for _, c in ipairs(clients) do
    local h = homeBody(c)
    if h ~= nil and c.Character ~= h then
      if gone(h) then
        c.Character = h
        c.CharacterInfo = h.Info
      else
        local driver = G.controllerOf(h)
        if driver ~= nil and driver ~= c then SW.release(driver) end
        Game.Server:SetClientCharacter(c, h)
      end
    end
  end
end

local function runHooks(list, campaign, label)
  for i, fn in ipairs(list) do
    local ok, err = pcall(fn, campaign)
    if not ok then
      CS.blockSave = true
      log(label .. ' hook ' .. i .. ' error: ' .. tostring(err))
    end
  end
end

-- ---------- round ending ----------

P.patch('crewswap.endround', 'Barotrauma.GameSession', 'EndRound', nil, safe('endround', function()
  CS.roundEnding = true
  endHomes = {}
  if not engaged() then return end
  for _, c in ipairs(G.clients()) do
    local h = G.homeBodyOf(c)
    if h ~= nil then endHomes[G.accountKey(c)] = h end
  end
end), Hook.HookMethodType.Before)

Hook.Add('roundStart', 'crewswap.roundend.rs', safe('roundStart', function()
  CS.roundEnding = false
  CS.restoredBeforeEnd = false
  endHomes = {}
end))

-- ---------- restore ----------

P.patch('crewswap.restore', 'Barotrauma.MultiPlayerCampaign', 'SavePlayers', nil, function(campaign)
  if not engaged() then return end
  local ok, err = pcall(function()
    local alive = false
    for _, c in ipairs(G.clients()) do
      if c.InGame and c.Character ~= nil and not c.Character.IsDead then alive = true end
    end
    CS.preRestoreAlive = alive
    CS.restoredBeforeEnd = Game.GameSession.IsRunning == true   -- true only on save-and-quit
    CS.restoreAll()
  end)
  if not ok then
    CS.blockSave = true
    log('restore error: ' .. tostring(err))
  end
  runHooks(CS.onSavePlayersPre, campaign, 'pre-save')
  SW.broadcastState()
end, Hook.HookMethodType.Before)

P.patch('crewswap.restore.post', 'Barotrauma.MultiPlayerCampaign', 'SavePlayers', nil, function(campaign)
  if not engaged() then return end
  runHooks(CS.onSavePlayersPost, campaign, 'post-save')
end, Hook.HookMethodType.After)

-- ---------- GameOver ----------

-- GameOver has a private setter; the restore can only skew it on save-and-quit, where End runs
-- after SavePlayers. Put back the pre-restore value; never recompute it from a Free-crew rule.
R.gameOverAccessible = pcall(function()
  LuaUserData.MakePropertyAccessible(LuaUserData.RegisterType('Barotrauma.MultiPlayerCampaign'), 'GameOver')
end)
if not R.gameOverAccessible then CS.fail('MultiPlayerCampaign.GameOver is not accessible') end

P.patch('crewswap.gameover', 'Barotrauma.MultiPlayerCampaign', 'End', { 'Barotrauma.CampaignMode+TransitionType' },
  safe('gameover', function(campaign)
    if not CS.restoredBeforeEnd then return end
    CS.restoredBeforeEnd = false
    campaign.GameOver = not CS.preRestoreAlive
  end), Hook.HookMethodType.After)

-- ---------- crew set ----------

-- Vanilla's crew set is client characters plus CrewManager bots; a home body nobody drives is
-- neither. Add it wherever bots are included (Bot flag = 1), so it gets mission XP and
-- round-end talents like a bot. ImmutableHashSet: Add returns a new set. Unregistered, the set
-- reaches Lua as an opaque userdata, so register the open generic (closed types inherit it).
R.setRegistered = pcall(function() LuaUserData.RegisterType('System.Collections.Immutable.ImmutableHashSet`1') end)
if not R.setRegistered then CS.fail('ImmutableHashSet`1 could not be registered') end
P.patch('crewswap.crewset', 'Barotrauma.GameSession', 'GetSessionCrewCharacters', nil,
  safe('crewset', function(_, p)
    if not CS.active then return end
    local ty = p['type']
    if ty == nil or ty % 2 ~= 1 then return end
    local campaign = G.campaign()
    if campaign == nil then return end
    local result = p.ReturnValue
    local changed = false
    for _, ch in ipairs(G.list(Character.CharacterList)) do
      if not gone(ch) and ch.IsBot and ch.Info ~= nil and campaign:GetCharacterData(ch.Info) ~= nil
          and not result:Contains(ch) then
        result = result:Add(ch)
        changed = true
      end
    end
    if changed then p.ReturnValue = result end
  end), Hook.HookMethodType.After)

-- ---------- dead crew kept and revived ----------

-- Vanilla deletes every dead bot at round end (CampaignMode.End, SavePlayers' dead-bot branch).
-- While the guard is up, a dead non-home crew member's removal is skipped, and the revive makes
-- it spawn alive next round, with the usual death penalty applied.
local revive = require('crewswap.core.revive')
local TT = { 'Barotrauma.CampaignMode+TransitionType' }

CS.keptDead = {}       -- [CharacterInfo.ID] = {info=, cause=, revived=bool}, until round start
CS.keepGuard = false   -- up in CampaignMode.End and SavePlayers

local function inRoster(cm, info)
  if cm == nil then return false end
  for _, ci in ipairs(G.list(cm:GetCharacterInfos(true))) do
    if ci.ID == info.ID then return true end
  end
  return false
end

local function causeOf(info)
  local cod = info.CauseOfDeath
  local ch = info.Character
  if cod == nil and ch ~= nil and ch.IsDead then
    cod = ch.CauseOfDeath
    if cod == nil then return 'other' end
  end
  if cod ~= nil then return cod.Type == CauseOfDeathType.Disconnected and 'disconnected' or 'other' end
  -- kept earlier this round end (save-and-quit: SavePlayers revived it, then End sees the body)
  local k = CS.keptDead[info.ID]
  return k and k.cause or 'none'
end

local function isPermadead(info) return G.isPermadeath() or info.PermanentlyDead == true end

-- → true when `info` is a dead crew member to keep (and records it in CS.keptDead).
local function keep(cm, info)
  local campaign = G.campaign()
  if info == nil or campaign == nil then return false end
  local facts = { cause = causeOf(info), permadeath = isPermadead(info),
                  inCCD = campaign:GetCharacterData(info) ~= nil, inRoster = inRoster(cm, info) }
  if not revive.plan(facts, 'transition').keep then return false end   -- keep doesn't depend on the path
  if CS.keptDead[info.ID] == nil then
    CS.keptDead[info.ID] = { info = info, cause = facts.cause, revived = false }
    log('kept dead crew member ' .. tostring(info.Name) .. ' (' .. facts.cause .. ')')
  end
  return true
end

P.patch('crewswap.keepdead', 'Barotrauma.CrewManager', 'RemoveCharacterInfo', { 'Barotrauma.CharacterInfo' },
  safe('keepdead', function(cm, p)
    if not CS.keepGuard or not CS.active then return end
    -- info is nil for monsters (End's dead-body loop)
    if keep(cm, p['characterInfo']) then p.PreventExecution = true end
  end), Hook.HookMethodType.Before)

-- Save-and-quit gotcha: the keepdead prefix never sees vanilla's own dead-bot removal inside SavePlayers (server
-- MPC.cs:350): at runtime on a dedicated server no patch on RemoveCharacterInfo fires for that call site, even
-- when SavePlayers is re-patched after it (the tiny method is inlined into SavePlayers' Harmony
-- replacement).
-- So the SavePlayers prefix decides up front, for exactly the bodies vanilla will drop, and the
-- postfix puts any kept info that vanilla removed back into the roster.
local function preKeepForSave(campaign)
  local cm = campaign and campaign.CrewManager
  if cm == nil then return end
  for _, ch in ipairs(G.list(Character.CharacterList)) do
    local cod = ch.CauseOfDeath
    if revive.dropsAtSave({ isBot = ch.IsBot == true, isDead = ch.IsDead == true, hasInfo = ch.Info ~= nil,
          hasInventory = ch.Inventory ~= nil, disconnected = cod ~= nil and cod.Type == CauseOfDeathType.Disconnected }) then
      keep(cm, ch.Info)
    end
  end
end

local function putBackKept(campaign)
  local cm = campaign and campaign.CrewManager
  if cm == nil then return end
  for _, k in pairs(CS.keptDead) do
    if not inRoster(cm, k.info) then
      cm:AddCharacterInfo(k.info)
      log('put kept crew member ' .. tostring(k.info.Name) .. ' back in the roster')
    end
  end
end

function R.applyRevive(info, a)
  if a.penalty then info:ApplyDeathEffects() else info.CauseOfDeath = nil end
  if a.clearHealth then info.HealthData = nil end
  if a.clearInventory then info.InventoryData = nil end
  if a.clearOrders then info:ClearCurrentOrders() end
  local ch = info.Character
  if ch ~= nil and ch.IsDead then info.Character = nil end
  if a.pendingSpawn then info.PendingSpawnToActiveService = true end
end

-- Revive every kept info not yet revived. Raises when any failed (the caller blocks the save:
-- an unrevived info would be dropped by CrewManager.SaveMultiplayer).
function CS.reviveKept(path)
  local campaign = G.campaign()
  local failed = 0
  for _, k in pairs(CS.keptDead) do
    if not k.revived then
      local ok, err = pcall(function()
        local info = k.info
        local a = revive.plan({ cause = k.cause, permadeath = isPermadead(info), inRoster = true,
                                inCCD = campaign ~= nil and campaign:GetCharacterData(info) ~= nil }, path)
        if not a.keep then return end
        R.applyRevive(info, a)
        k.revived = true
        log('revived ' .. tostring(info.Name) .. ' (' .. path .. (a.penalty and ', skill penalty' or '') .. ')')
      end)
      if not ok then
        failed = failed + 1
        log('revive error: ' .. tostring(err))
      end
    end
  end
  if failed > 0 then error(failed .. ' kept crew member(s) not revived') end
end

P.patch('crewswap.endguard', 'Barotrauma.CampaignMode', 'End', TT, safe('endguard', function()
  if not CS.active then return end
  CS.keepGuard = true
  CS.snapshotWallets()
end), Hook.HookMethodType.Before)

P.patch('crewswap.endguard.post', 'Barotrauma.CampaignMode', 'End', TT, safe('endguard.post', function()
  CS.keepGuard = false
end), Hook.HookMethodType.After)

CS.onSavePlayersPre[#CS.onSavePlayersPre + 1] = function(campaign)
  if not CS.active then return end
  CS.keepGuard = true
  preKeepForSave(campaign)
end
-- Runs before safety's post-save check (roundend loads first), so the check sees the roster
-- with the kept crew back in it. An error here blocks the save (runHooks).
CS.onSavePlayersPost[#CS.onSavePlayersPost + 1] = function(campaign)
  CS.keepGuard = false
  if CS.active then putBackKept(campaign) end
  CS.reviveKept(CS.restoredBeforeEnd and 'saveandquit' or 'transition')
end

-- [Character.ID] = the body whose wallet was restored (once per body)
local walletDone = {}

-- Unsaved ends (vote end, crew down, admin end without save) never reach SavePlayers.
P.patch('crewswap.endgame', 'Barotrauma.Networking.GameServer', 'EndGame', nil, safe('endgame', function(_, p)
  CS.keepGuard = false
  -- Order-independent: safety's EndGame postfix may already have cleared saveBlocked; lastSaveBlocked stays.
  local blocked = CS.saveBlocked == true or CS.lastSaveBlocked == true
  if p['wasSaved'] == false and not blocked then CS.reviveKept('unsaved') end
  CS.keptDead = {}
  walletDone = {}
  CS.walletStage = {}   -- staged wallets: committed already if the end was saved; dropped otherwise
end), Hook.HookMethodType.After)

Hook.Add('roundStart', 'crewswap.roundend.keep', safe('keep.roundStart', function()
  CS.keepGuard = false
  CS.keptDead = {}
  CS.walletStage = {}
end))

-- ---------- per-character wallets ----------

-- Vanilla keeps a wallet only through a CCD; a bot's is lost with its body. The balance and
-- salary ride on the crew member's registry record (wbal, wrd), saved with its info.
-- The CampaignMode.End snapshot is only STAGED. It reaches the records in the
-- SaveGame prefix of a save that is really written, and is dropped on an unsaved end, so bot
-- wallets revert together with the CCD (home) wallets.
CS.walletStage = {}   -- [sid] = {wbal=, wrd=}

-- Bot wallets into `stage`, one body at a time. → number of bodies that could not be read.
local function snapshotInto(stage)
  if not CS.active then return 0 end
  local campaign = G.campaign()
  if campaign == nil then return 0 end
  local failed = 0
  for _, ch in ipairs(G.list(Character.CharacterList)) do
    local ok, err = pcall(function()
      if G.isCrew(ch) and campaign:GetCharacterData(ch.Info) == nil then
        local w = ch.Wallet
        stage[CS.sidOfInfo(ch.Info)] = { wbal = w.Balance, wrd = w.RewardDistribution }
      end
    end)
    if not ok then
      failed = failed + 1
      log('wallet snapshot error for ' .. tostring(ch.Name) .. ': ' .. tostring(err))
    end
  end
  return failed
end

-- CampaignMode.End prefix. A body that can't be read would keep a stale wallet: block the save.
function CS.snapshotWallets()
  if snapshotInto(CS.walletStage) > 0 then CS.blockSave = true end
end

-- SaveGame prefix of a real save: stage + the live wallets into the records. → ok
function CS.commitWallets()
  if snapshotInto(CS.walletStage) > 0 then return false end
  for sid, w in pairs(CS.walletStage) do
    local rec = CS.reg:record(sid)
    rec.wbal, rec.wrd = w.wbal, w.wrd
  end
  CS.walletStage = {}
  return true
end

local function restoreWallet(ch, campaign)
  if ch == nil or ch.Removed or ch.Info == nil or walletDone[ch.ID] == ch then return end
  local info = ch.Info
  if campaign:GetCharacterData(info) ~= nil or not inRoster(campaign.CrewManager, info) then return end
  if CS.reg:sidOf(info.ID) == nil and (CS.pending == nil or CS.pending[info.ID] == nil) then return end
  local rec = CS.reg.chars[CS.sidOfInfo(info)]
  if rec == nil or rec.wbal == nil then return end
  walletDone[ch.ID] = ch
  local w = ch.Wallet
  w.Balance = rec.wbal
  w:ForceUpdate()
  if rec.wrd ~= nil then w:SetRewardDistribution(rec.wrd) end
end

R.saveUtilRegistered = pcall(function() LuaUserData.RegisterType('Barotrauma.SaveUtil') end)
P.patch('crewswap.wallets.save', 'Barotrauma.SaveUtil', 'SaveGame', { 'Barotrauma.CampaignDataPath', 'System.Boolean' },
  safe('wallets.save', function(_, p)
    if p['isSavingOnLoading'] or CS.blockSave then return end   -- a blocked save commits nothing
    if not CS.commitWallets() then
      -- this prefix may run before or after safety's: block the write here too
      CS.blockSave, CS.saveBlocked = true, true
      p.PreventExecution = true
      log('save blocked: a bot wallet could not be read')
    end
  end), Hook.HookMethodType.Before)

P.patch('crewswap.wallets.init', 'Barotrauma.CrewManager', 'InitRound', nil, safe('wallets.init', function()
  if not CS.active then return end
  local campaign = G.campaign()
  if campaign == nil then return end
  for _, ch in ipairs(G.list(Character.CharacterList)) do restoreWallet(ch, campaign) end
end), Hook.HookMethodType.After)

-- Bots created inline (first round of a campaign) and bench spawns never go through InitRound.
-- TeamID isn't set yet here, so the roster test stands in for the crew test.
Hook.Add('character.created', 'crewswap.wallets.created', safe('wallets.created', function(ch)
  if not CS.active then return end
  local campaign = G.campaign()
  if campaign ~= nil then restoreWallet(ch, campaign) end
end))

local ST = require('crewswap.server.selftest')
ST.add('roundend-patches', function()
  for _, id in ipairs({ 'crewswap.endround', 'crewswap.restore', 'crewswap.restore.post',
                        'crewswap.gameover', 'crewswap.crewset', 'crewswap.keepdead', 'crewswap.endguard',
                        'crewswap.endguard.post', 'crewswap.endgame', 'crewswap.wallets.save',
                        'crewswap.wallets.init' }) do
    if P.errors[id] ~= nil then return false, id .. ': ' .. P.errors[id] end
  end
  if not R.gameOverAccessible then return false, 'GameOver not accessible' end
  if not R.saveUtilRegistered then return false, 'SaveUtil not registered' end
  return true
end)
local function crewSet()
  local GS = LuaUserData.CreateStatic('Barotrauma.GameSession')
  return GS.GetSessionCrewCharacters(LuaUserData.CreateEnumTable('Barotrauma.CharacterType').Both)
end
ST.add('crew-set-add', function()
  local set = crewSet()
  if type(set) ~= 'userdata' then return false, 'GetSessionCrewCharacters gave a ' .. type(set) end
  local before = set.Count
  local bigger = set:Add(nil)
  if bigger.Count ~= before + 1 then return false, 'Add gave Count ' .. tostring(bigger.Count) end
  if set.Count ~= before then return false, 'Add changed the original set' end
  if not bigger:Contains(nil) then return false, 'Contains missed the added item' end
  return true
end)
-- Runs the postfix past its CS.active gate (no round, so it stops at the campaign check):
-- proves the enum argument arrives as a number the flag test can use.
ST.add('crew-set-postfix', function()
  local was, before = CS.active, R.errors.crewset or 0
  CS.active = true
  local ok, err = pcall(crewSet)
  CS.active = was
  if not ok then return false, tostring(err) end
  if (R.errors.crewset or 0) ~= before then return false, 'the postfix raised (see the roundend: crewset error line)' end
  return true
end)

-- The revive's member calls and field writes on a real CharacterInfo, penalty path included.
ST.add('revive-apply', function()
  local info = CharacterInfo(Identifier('human'))
  info.HealthData = XElement(XName.Get('health'))
  info.InventoryData = XElement(XName.Get('inventory'))
  R.applyRevive(info, revive.plan({ cause = 'other', permadeath = false, inCCD = false, inRoster = true }, 'transition'))
  if info.HealthData ~= nil then return false, 'HealthData not cleared' end
  if info.InventoryData ~= nil then return false, 'InventoryData not cleared' end
  if info.CauseOfDeath ~= nil then return false, 'CauseOfDeath not cleared' end
  if info.PendingSpawnToActiveService ~= true then return false, 'PendingSpawnToActiveService not set' end
  return true
end)

return R

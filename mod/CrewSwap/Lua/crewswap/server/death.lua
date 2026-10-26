-- Deaths. Vanilla applies a death's effects to whoever
-- DRIVES the body (Character.KillProjSpecific finds them via c.Character == this), so the mod
-- hides the driver from vanilla and applies the effects to the character that died. Also: a
-- dead borrowed corpse is kept out of vanilla respawn, RetainExperience is off, and vanilla
-- TAKEOVERBOT goes through the mod switch.
if not SERVER then return end
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')
local SW = require('crewswap.server.switch')

local D = { errors = {} }   -- errors[name] = callback errors so far

local NetFlags = LuaUserData.CreateEnumTable('Barotrauma.MultiPlayerCampaign+NetFlags')

CS.deathCtx = {}   -- [Character.ID] = {driver=, body=, cause=, balance=}, prefix to postfix

local function log(s) print('[CrewSwap] death: ' .. s) end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      D.errors[name] = (D.errors[name] or 0) + 1
      log(name .. ' error: ' .. tostring(err))
    end
  end
end

-- The driver died in `body`: send everyone fresh state, so the dead player sees Free crew.
function CS.onDriverDeath(client, body, disconnected)
  log(tostring(client.Name) .. ' died as ' .. tostring(body.Name) .. (disconnected and ' (disconnected)' or ''))
  SW.broadcastState()
end

-- ---------- kill redirect ----------

local function restore(ctx)
  if ctx.driver.Character == nil then ctx.driver.Character = ctx.body end
end

-- ApplyPermadeath on that home's CCD (that owner's stat). It drops the CCD's wallet, so bank
-- it into the campaign bank so the money is not lost.
local function homePermadeath(ccd, ch, campaign, balance)
  ccd:ApplyPermadeath()
  local amount = math.min(balance or 0, ch.Wallet.Balance)
  if amount > 0 then
    campaign.Bank:Give(amount)
    ch.Wallet:Deduct(amount)
    log('banked ' .. amount .. ' mk from ' .. tostring(ch.Name))
  end
end

-- Vanilla applies permadeath only through a driving client, so a player's home the AI was
-- running (its owner plays someone else, or it was released) would just die normally and
-- respawn next round. Under permadeath the character who died stays permanently dead.
local function undrivenPermadeath(ch, cause)
  if not CS.active or not G.isPermadeath() or cause == CauseOfDeathType.Disconnected then return end
  local info = ch.Info
  if info == nil or info.PermanentlyDead == true or G.controllerOf(ch) ~= nil or not G.isCrew(ch) then return end
  local campaign = G.campaign()
  local ccd = campaign and campaign:GetCharacterData(info)
  if ccd == nil then return end   -- a bot: vanilla drops it at round end
  homePermadeath(ccd, ch, campaign, ch.Wallet ~= nil and ch.Wallet.Balance or 0)
  campaign:IncrementLastUpdateIdForFlag(NetFlags.CharacterInfo)
  log(tostring(ch.Name) .. ' is permanently dead (nobody was playing them)')
end

-- The effects vanilla skipped, applied to the character that died.
local function applyEffects(ch, ctx)
  local driver = ctx.driver
  local campaign = G.campaign()
  if campaign == nil then return end
  -- Raw setter: the borrowed info keeps its Character, so nothing is Remove()d. Without this,
  -- vanilla respawn would spawn the borrowed crew member a second time.
  local home = campaign:GetClientCharacterData(driver)
  if home ~= nil and home.CharacterInfo ~= nil then driver.CharacterInfo = home.CharacterInfo end

  if G.isPermadeath() and ctx.cause ~= CauseOfDeathType.Disconnected and ch.Info ~= nil then
    local ccd = campaign:GetCharacterData(ch.Info)
    if ccd ~= nil then
      homePermadeath(ccd, ch, campaign, ctx.balance)   -- a home, maybe another player's
    else
      ch.Info.PermanentlyDead = true   -- a bot has no CCD
    end
    campaign:IncrementLastUpdateIdForFlag(NetFlags.CharacterInfo)
    log(tostring(ch.Name) .. ' is permanently dead')
  end

  local cod = ch.CauseOfDeath
  local killer = cod and cod.Killer
  if killer ~= nil and killer.IsTraitor and killer ~= ch and not Game.overrideTraitors then
    Game.Server:SendDirectChatMessage('KilledByTraitorNotification~', driver, ChatMessageType.ServerMessageBoxInGame)
  end
end

P.patch('crewswap.kill.pre', 'Barotrauma.Character', 'KillProjSpecific', nil, safe('kill.pre', function(ch, p)
  if not CS.active or not G.isCrew(ch) then return end
  local driver = G.controllerOf(ch)
  if driver == nil then return end
  CS.deathCtx[ch.ID] = { driver = driver, body = ch, cause = p['causeOfDeath'],
                         balance = ch.Wallet ~= nil and ch.Wallet.Balance or 0 }
  driver.Character = nil   -- hides the driver from all three vanilla lookups
end), Hook.HookMethodType.Before)

P.patch('crewswap.kill.post', 'Barotrauma.Character', 'KillProjSpecific', nil, safe('kill.post', function(ch, p)
  local ctx = CS.deathCtx[ch.ID]
  if ctx == nil then
    local ok, err = pcall(undrivenPermadeath, ch, p and p['causeOfDeath'])
    if not ok then
      D.errors.effects = (D.errors.effects or 0) + 1
      log('undriven death error for ' .. tostring(ch.Name) .. ': ' .. tostring(err))
    end
    return
  end
  CS.deathCtx[ch.ID] = nil
  restore(ctx)
  local ok, err = pcall(applyEffects, ch, ctx)
  if not ok then
    D.errors.effects = (D.errors.effects or 0) + 1
    log('death effects error for ' .. tostring(ch.Name) .. ': ' .. tostring(err))
  end
  CS.onDriverDeath(ctx.driver, ch, ctx.cause == CauseOfDeathType.Disconnected)
end), Hook.HookMethodType.After)

-- If vanilla threw inside KillProjSpecific the postfix never ran: give the driver back.
Hook.Add('think', 'crewswap.death.safety', safe('safety', function()
  if next(CS.deathCtx) == nil then return end
  for id, ctx in pairs(CS.deathCtx) do
    CS.deathCtx[id] = nil
    restore(ctx)
    log('restored ' .. tostring(ctx.driver.Name) .. ' after an interrupted death')
  end
end))

-- ---------- respawn ----------

-- RespawnCharacters despawns the client's current body. Outside Permadeath, a driver still
-- attached to a dead borrowed corpse is let go first, so the corpse stays in the world.
-- (In Permadeath a nil Character would make vanilla respawn the client.)
P.patch('crewswap.respawn.detach', 'Barotrauma.Networking.RespawnManager', 'RespawnCharacters',
  { 'Barotrauma.Networking.RespawnManager+TeamSpecificState' }, safe('respawn.detach', function()
    if not CS.active or G.isPermadeath() then return end
    local campaign = G.campaign()
    if campaign == nil then return end
    for _, c in ipairs(G.clients()) do
      local ch = c.Character
      if ch ~= nil and ch.IsDead then
        local ccd = campaign:GetClientCharacterData(c)
        if ccd == nil or ccd.CharacterInfo ~= ch.Info then
          c.Character = nil
          log(tostring(c.Name) .. ' let go of the corpse of ' .. tostring(ch.Name) .. ' before respawn')
        end
      end
    end
  end), Hook.HookMethodType.Before)

-- ---------- RetainExperienceForNewCharacter: off while active ----------

-- The talent would hand the XP of whatever body a client last drove to their home. The death
-- call site is already hidden by the kill redirect; this covers the round-end one too.
P.patch('crewswap.retainxp.save', 'Barotrauma.MultiPlayerCampaign', 'SaveExperiencePoints', nil, function(_, p)
  if CS.active then p.PreventExecution = true end
end, Hook.HookMethodType.Before)

-- int return: the number is returned from Lua (a bare return keeps vanilla).
P.patch('crewswap.retainxp.get', 'Barotrauma.MultiPlayerCampaign', 'GetSavedExperiencePoints', nil, function(_, p)
  if CS.active then
    p.PreventExecution = true
    return 0
  end
end, Hook.HookMethodType.Before)

-- ---------- TAKEOVERBOT ----------

-- The spawned crew body whose CharacterInfo.ID is infoId (TAKEOVERBOT sends info ids).
local function spawnedCrewByInfoId(infoId)
  for _, ch in ipairs(G.list(Character.CharacterList)) do
    if ch.Info ~= nil and ch.Info.ID == infoId and not ch.Removed and G.isCrew(ch) then return ch end
  end
  return nil
end

local function routeTakeover(p)
  local inc, sender = p['inc'], p['sender']
  local pos = inc.BitPosition
  local infoId = inc:ReadUInt16()
  inc.BitPosition = pos
  local target = spawnedCrewByInfoId(infoId)
  if target ~= nil then
    p.PreventExecution = true
    SW.request(sender, target, 'takeover')   -- validates Free, denies otherwise
    return
  end
  -- Hire / bench / new hire: vanilla discards the client's CCD, so only where that can't hit a
  -- living home, and only with client.CharacterInfo pointing at the home (not a borrowed info).
  local campaign = G.campaign()
  local ccd = campaign and campaign:GetClientCharacterData(sender)
  local homeInfo = ccd and ccd.CharacterInfo
  if G.isPermadeath() and (ccd == nil or (homeInfo ~= nil and homeInfo.PermanentlyDead)) then
    if homeInfo ~= nil and sender.CharacterInfo ~= homeInfo then sender.CharacterInfo = homeInfo end
    -- vanilla makes this info the sender's new home: roster -> CCD is legit,
    -- so tell the integrity check
    if CS.noteLegit then CS.noteLegit('adopted', infoId) end
    return
  end
  p.PreventExecution = true
  SW.deny(sender, 'takeover', 'takeover')
end

-- An error here would otherwise fail open into vanilla, which can discard a living home.
P.patch('crewswap.takeover', 'Barotrauma.Networking.GameServer', 'ReadTakeOverBotMessage', nil, function(_, p)
  if not CS.active then return end
  local ok, err = pcall(routeTakeover, p)
  if not ok then
    p.PreventExecution = true
    D.errors.takeover = (D.errors.takeover or 0) + 1
    log('takeover error: ' .. tostring(err))
  end
end, Hook.HookMethodType.Before)

-- Vanilla took a bot over (the fall-through path): that body is now the client's home.
P.patch('crewswap.takeover.post', 'Barotrauma.Networking.Client', 'TryTakeOverBot', nil,
  safe('takeover.post', function(client, p)
    if not CS.active or p.OriginalReturnValue ~= true then return end
    local ch = p['botCharacter']
    if ch == nil or ch.Info == nil then return end
    local key = G.accountKey(client)
    local rec = CS.reg:record(CS.sidOfInfo(ch.Info))
    rec.last, rec.lastAt, rec.home = key, os.time(), key
    SW.broadcastState()
  end), Hook.HookMethodType.After)

-- ---------- self-test ----------

local ST = require('crewswap.server.selftest')
ST.add('death-patches', function()
  for _, id in ipairs({ 'crewswap.kill.pre', 'crewswap.kill.post', 'crewswap.respawn.detach',
                        'crewswap.retainxp.save', 'crewswap.retainxp.get', 'crewswap.takeover',
                        'crewswap.takeover.post' }) do
    if P.errors[id] ~= nil then return false, id .. ': ' .. P.errors[id] end
  end
  return true
end)
ST.add('death-api', function()
  -- A registered enum arrives boxed (userdata of that type): exactly what the method takes.
  local f = NetFlags.CharacterInfo
  if not (type(f) == 'number' or LuaUserData.IsTargetType(f, 'Barotrauma.MultiPlayerCampaign+NetFlags')) then
    return false, 'NetFlags.CharacterInfo is ' .. type(f) .. ' ' .. tostring(f)
  end
  local want = {
    ['Barotrauma.CharacterCampaignData'] = { 'ApplyPermadeath', 'HasSpawned' },
    ['Barotrauma.MultiPlayerCampaign'] = { 'Bank', 'IncrementLastUpdateIdForFlag' },
    ['Barotrauma.Wallet'] = { 'Give', 'Deduct', 'Balance' },
    ['Barotrauma.Networking.IReadMessage'] = { 'BitPosition', 'ReadUInt16' },
  }
  for ty, members in pairs(want) do
    local d = LuaUserData.RegisterType(ty)
    for _, m in ipairs(members) do
      if not LuaUserData.HasMember(d, m) then return false, ty .. ' has no ' .. m end
    end
  end
  return true
end)

return D

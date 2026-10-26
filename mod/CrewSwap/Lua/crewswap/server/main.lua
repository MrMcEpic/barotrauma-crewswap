if not SERVER then return end
local build = require('crewswap.shared.build')
local version = require('crewswap.core.version')
print('[CrewSwap] server loaded build ' .. build.BUILD)

local prevCS = CS
CS = { active = false, versionOk = false, lockdown = false, campaignOk = false }
-- A server Lua reload leaves every client's Lua running: keep what their hellos told us, or no
-- connected player would get state again until they rejoined (switch.lua re-checks the builds).
if type(prevCS) == 'table' then
  for _, k in ipairs({ 'clientBuild', 'clientBad', 'joinedAt', 'noHelloTold' }) do
    if type(prevCS[k]) == 'table' then CS[k] = prevCS[k] end
  end
end

-- The mod switches itself off (failed patch, module load error, runtime audit). It says so
-- in chat, now and at every round start, until the server restarts: `!crewswap check` lifts
-- only integrity lockdowns, so a broken mod stays off until it is fixed and redeployed.
function CS.fail(reason)
  CS.active = false
  CS.lockdown = true
  print('[CrewSwap] FAIL: ' .. tostring(reason))
  if CS.failReason == nil then CS.failReason = tostring(reason) end
  pcall(function() Game.SendMessage(require('crewswap.core.commands').FAIL_NOTICE, ChatMessageType.Server) end)
end
Hook.Add('roundStart', 'crewswap.failnotice', function()
  if CS.failReason == nil then return end
  pcall(function() Game.SendMessage(require('crewswap.core.commands').FAIL_NOTICE, ChatMessageType.Server) end)
end)

-- Version gate: read the real game version and LuaCs commit. Needs unsandboxed server Lua (CSActive).
-- A wrong game version switches the mod off; a different LuaCs commit only warns.
local function readVersions()
  LuaUserData.RegisterType('System.Version')
  local v = LuaUserData.CreateStatic('Barotrauma.GameMain').Version
  -- An unreadable LuaCs revision is only a warning (compare reports it as 'unknown').
  local okRev, rev = pcall(function()
    LuaUserData.RegisterType('AssemblyInfo')
    return LuaUserData.CreateStatic('AssemblyInfo').GitRevision
  end)
  if not okRev then rev = nil end
  return { game = v.Major .. '.' .. v.Minor .. '.' .. v.Build .. '.' .. v.Revision, luacs = tostring(rev or '') }
end

local function checkVersions()
  if CSActive ~= true then return false, 'server Lua is sandboxed' end
  local ok, found = pcall(readVersions)
  if not ok then return false, 'version read failed: ' .. tostring(found) end
  print('[CrewSwap] running on game ' .. found.game .. ', LuaCs ' .. found.luacs)
  return version.compare(found, { game = build.EXPECT_GAME, luacs = build.EXPECT_LUACS })
end

local okVer, why, luacsWarning = checkVersions()
if luacsWarning then print(luacsWarning) end
if not okVer then
  CS.active = false
  print('[CrewSwap] OFF: version mismatch (' .. tostring(why) .. ')')
  Hook.Add('roundStart', 'crewswap.versionoff', function()
    Game.SendMessage("[CrewSwap] CrewSwap is off until it's updated for this game version (" .. tostring(why) .. ').',
      ChatMessageType.Server)
  end)
  return
end
CS.versionOk = true
print('[CrewSwap] save folder: ' .. tostring(Game.SaveFolder))

-- Active = right version, not locked down, a multiplayer campaign, and not Ironman.
-- Patches can't be removed, so every callback checks CS.active; this recomputes it.
LuaUserData.RegisterType('Barotrauma.MultiPlayerCampaign')
local ironmanNotified = false
-- `campaign` overrides Game.GameSession.Campaign (unset while a campaign is still loading).
function CS.recomputeActive(campaign)
  local ok, mp, ironman = pcall(function()
    local gs = Game.GameSession
    campaign = campaign or (gs and gs.Campaign)
    local isMp = campaign ~= nil and LuaUserData.IsTargetType(campaign, 'Barotrauma.MultiPlayerCampaign')
    return isMp, Game.ServerSettings.IronmanModeActive == true
  end)
  if not ok then
    CS.active, CS.campaignOk = false, false
    print('[CrewSwap] recomputeActive error: ' .. tostring(mp))
    return false
  end
  -- campaignOk ignores lockdowns: the identity layer keeps writing the ids and records it already
  -- holds while locked down, or the next vanilla save would drop them for good.
  CS.campaignOk = CS.versionOk and mp and not ironman
  CS.active = CS.campaignOk and not CS.lockdown
  if mp and ironman and not ironmanNotified then
    ironmanNotified = true
    Game.SendMessage('[CrewSwap] CrewSwap is off in Ironman campaigns.', ChatMessageType.Server)
  end
  return CS.active
end

Hook.Add('roundStart', 'crewswap.active', function()
  ironmanNotified = false   -- the Ironman notice goes out once per round
  print('[CrewSwap] round start, active: ' .. tostring(CS.recomputeActive()))
end)

-- Load the server modules in dependency order; ones that don't exist yet are skipped.
local MODULES = { 'game', 'patch', 'selftest', 'spawn', 'identity', 'switch', 'presence',
  'roundend', 'death', 'crewdown', 'safety', 'admin' }
local loaded = {}
for _, name in ipairs(MODULES) do
  local mod = 'crewswap.server.' .. name
  local ok, err = pcall(require, mod)
  if ok then
    loaded[#loaded + 1] = name
  elseif not tostring(err):find("module '" .. mod .. "' not found", 1, true) then
    CS.fail('loading ' .. mod .. ': ' .. tostring(err))
  end
end
print('[CrewSwap] modules loaded: ' .. table.concat(loaded, ', '))
require('crewswap.server.patch').summary()

CS.recomputeActive()
print('[CrewSwap] active: ' .. tostring(CS.active))

if File.Exists(Game.SaveFolder .. '/CrewSwap/selftest') then
  Timer.Wait(function() require('crewswap.server.selftest').run() end, 1000)
end

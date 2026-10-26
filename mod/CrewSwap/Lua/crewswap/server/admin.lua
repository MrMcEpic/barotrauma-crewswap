-- Admin chat commands (!crewswap ...), the persisted pool/protect toggles and own-crew
-- ownership by hiring (the chatMessage hook suppresses the command text; ownership patches
-- CampaignMode.TryHireCharacter).
if not SERVER then return end
local commands = require('crewswap.core.commands')
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')
local SW = require('crewswap.server.switch')

local A = { errors = {} }

A.ADMIN_ONLY = '[CrewSwap] Only admins can change CrewSwap settings.'

local function log(s) print('[CrewSwap] admin: ' .. s) end

-- ---------- config file ----------

local function configDir() return Game.SaveFolder .. '/CrewSwap' end
local function configPath() return configDir() .. '/config.txt' end

local function copy(t) return { pool = t.pool, protect = t.protect } end

function A.load()
  local toggles
  local ok, err = pcall(function()
    if File.Exists(configPath()) then toggles = commands.configDecode(File.Read(configPath())) end
  end)
  if not ok then log('config read failed, using defaults: ' .. tostring(err)) end
  CS.config = { toggles = toggles or copy(commands.DEFAULTS) }
  log('config: pool=' .. CS.config.toggles.pool .. ' protect=' .. (CS.config.toggles.protect and 'on' or 'off')
    .. (toggles and ' (from file)' or ' (defaults)'))
end

-- → ok. Written via a .tmp file and a move, like the mirror, so a crash never leaves half a file.
function A.save()
  local ok, err = pcall(function()
    pcall(function()
      LuaUserData.RegisterType('Barotrauma.IO.Directory')
      LuaUserData.CreateStatic('Barotrauma.IO.Directory').CreateDirectory(configDir())
    end)
    File.Write(configPath() .. '.tmp', commands.configEncode(CS.config.toggles))
    File.Move(configPath() .. '.tmp', configPath())
  end)
  if not ok then log('config write failed: ' .. tostring(err)) end
  return ok
end

local function setToggle(client, key, value, label)
  CS.config.toggles[key] = value
  local saved = A.save()
  log(tostring(client.Name) .. ' set ' .. key .. ' = ' .. tostring(value))
  G.announce('[CrewSwap] ' .. label)
  if not saved then
    G.tell(client, '[CrewSwap] Could not save the setting to disk; it applies until the server restarts.')
  end
  SW.broadcastState()   -- Free rows depend on the toggles
end

-- ---------- commands ----------

local function findCharacter(name)
  local list = {}
  for _, v in ipairs(G.crewViews()) do list[#list + 1] = v end
  return commands.findByName(list, name)
end

-- → Client | nil, 'none'|'ambiguous'  (findByName reads .name; a Client has .Name)
local function findPlayer(name)
  local list = {}
  for _, c in ipairs(G.clients()) do list[#list + 1] = { name = tostring(c.Name), client = c } end
  local hit, why = commands.findByName(list, name)
  return hit and hit.client, why
end

local function runOwner(client, cmd)
  if not CS.active then G.tell(client, '[CrewSwap] CrewSwap is off right now.'); return end
  local view, why = findCharacter(cmd.character)
  if view == nil then
    G.tell(client, why == 'ambiguous' and ('[CrewSwap] More than one crew member matches "' .. cmd.character .. '".')
      or ('[CrewSwap] No crew member named "' .. cmd.character .. '".'))
    return
  end
  local target, why2 = findPlayer(cmd.player)
  if target == nil then
    G.tell(client, why2 == 'ambiguous' and ('[CrewSwap] More than one player matches "' .. cmd.player .. '".')
      or ('[CrewSwap] No connected player named "' .. cmd.player .. '".'))
    return
  end
  if view.sid == nil then G.tell(client, '[CrewSwap] That crew member has no CrewSwap record yet.'); return end
  CS.reg:record(view.sid).owner = G.accountKey(target)
  log(tostring(client.Name) .. ' made ' .. tostring(target.Name) .. ' the owner of ' .. view.name)
  G.tell(client, '[CrewSwap] ' .. view.name .. ' now belongs to ' .. tostring(target.Name) .. '.')
  SW.broadcastState()
end

local function runCheck(client)
  if CS.runCheck == nil then G.tell(client, '[CrewSwap] The integrity check is not available.'); return end
  local ok = CS.runCheck('manual')
  if ok then
    -- Only an integrity lock may be lifted here; a lockdown from a failed patch or version stays.
    -- With a FAIL on record the lock is cleared but the lockdown stays, so the mod stays off.
    if CS.integrityLock then
      CS.integrityLock = false
      if CS.failReason == nil then
        CS.lockdown = false
        CS.recomputeActive()
      end
    end
    G.tell(client, CS.lockdown and '[CrewSwap] The integrity check passed, but CrewSwap is still locked down (see the server console).'
      or '[CrewSwap] The integrity check passed.')
  else
    G.tell(client, '[CrewSwap] The integrity check failed. See the server console for the details.')
  end
end

function A.run(client, cmd)
  if cmd.op == 'status' then
    G.tell(client, commands.statusText(G.toggles(), { active = CS.active == true, failReason = CS.failReason }))
    return
  end
  if not G.isAdmin(client) then G.tell(client, A.ADMIN_ONLY); return end
  if cmd.op == 'error' then G.tell(client, cmd.text)
  elseif cmd.op == 'pool' then
    setToggle(client, 'pool', cmd.value, cmd.value == 'own'
      and 'Crew pool is now "own": you can only switch into characters you hired or that nobody has claimed.'
      or 'Crew pool is now "shared": any Free crew member can be taken.')
  elseif cmd.op == 'protect' then
    setToggle(client, 'protect', cmd.value, cmd.value
      and "Home protection is now on: players' own characters cannot be taken by others."
      or "Home protection is now off: players' own characters can be taken when they are Free.")
  elseif cmd.op == 'owner' then runOwner(client, cmd)
  elseif cmd.op == 'check' then runCheck(client)
  end
end

-- Every sender's command text is swallowed so it never shows in public chat.
function A.onChat(text, client)
  local cmd = commands.parse(text)
  if cmd == nil then return end
  local ok, err = pcall(A.run, client, cmd)
  if not ok then
    A.errors.run = (A.errors.run or 0) + 1
    log('command error: ' .. tostring(err))
  end
  return true
end

Hook.Add('chatMessage', 'crewswap.cmd', A.onChat)

-- ---------- ownership by hiring ----------

-- Signature: CampaignMode.TryHireCharacter(Location, CharacterInfo, bool takeMoney, Client client, bool buyingNewCharacter).
-- Own-crew rule: only a hire made in own mode belongs to the hirer; anything hired before own mode
-- was switched on is claimed by whoever plays it first (switch.lua). A Permadeath replacement
-- character (buyingNewCharacter) becomes the buyer's home, not a hire.
P.patch('crewswap.hire.owner', 'Barotrauma.CampaignMode', 'TryHireCharacter', nil, function(_, p)
  local ok, err = pcall(function()
    if not CS.active or p.ReturnValue ~= true or p['client'] == nil then return end
    if G.toggles().pool ~= 'own' or p['buyingNewCharacter'] == true then return end
    local info = p['characterInfo']
    if info == nil then return end
    local hirer = G.accountKey(p['client'])
    CS.reg:record(CS.sidOfInfo(info)).owner = hirer
    log(tostring(p['client'].Name) .. ' hired ' .. tostring(info.Name) .. ' and now owns them')
  end)
  if not ok then
    A.errors.hire = (A.errors.hire or 0) + 1
    log('hire error: ' .. tostring(err))
  end
end, Hook.HookMethodType.After)

A.load()

local ST = require('crewswap.server.selftest')
ST.add('config-roundtrip', function()
  local saved = CS.config
  CS.config = { toggles = { pool = 'own', protect = false } }
  local ok = A.save()
  local back = ok and commands.configDecode(File.Read(configPath()))
  CS.config = saved
  A.save()   -- put the real settings back
  if not ok then return false, 'config.txt could not be written' end
  if back.pool ~= 'own' or back.protect ~= false then return false, 'config did not round trip' end
  return true
end)
ST.add('hire-signature', function()
  local d = LuaUserData.RegisterType('Barotrauma.CampaignMode')
  if not LuaUserData.HasMember(d, 'TryHireCharacter') then return false, 'CampaignMode has no TryHireCharacter' end
  return true
end)

return A

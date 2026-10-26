-- Every campaign crew body is AI-capable, so any of them can be handed back to the AI. Vanilla spawns a client's own body
-- as a plain Character (hasAi:false); a plain body can't be handed to the AI, so a released
-- body would just stand there. We force hasAi=true on those spawns, then audit that it worked.
if not SERVER then return end
local P = require('crewswap.server.patch')

local S = {}

local CREATE_SIG = { 'Barotrauma.CharacterPrefab', 'Microsoft.Xna.Framework.Vector2', 'System.String',
  'Barotrauma.CharacterInfo', 'System.UInt16', 'System.Boolean', 'System.Boolean', 'System.Boolean',
  'Barotrauma.RagdollParams', 'System.Boolean' }

-- True when `ch` is an AICharacter driven by a HumanAIController.
function S.isAIBody(ch)
  if ch == nil then return false end
  if not LuaUserData.IsTargetType(ch, 'Barotrauma.AICharacter') then return false end
  local ctl = ch.AIController
  return ctl ~= nil and LuaUserData.IsTargetType(ctl, 'Barotrauma.HumanAIController')
end

-- Prefix on Character.Create. Returns nothing: a value would overwrite Create's result.
local function forceAi(instance, p)
  if not CS.active then return end
  if not p['isRemotePlayer'] or p['hasAi'] then return end
  if p['characterInfo'] == nil then return end
  local gs = Game.GameSession
  if gs == nil or gs.Campaign == nil then return end
  p['hasAi'] = true
end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then print('[CrewSwap] spawn ' .. name .. ' callback error: ' .. tostring(err)) end
  end
end

P.patch('crewswap.forceai', 'Barotrauma.Character', 'Create', CREATE_SIG, safe('forceai', forceAi),
  Hook.HookMethodType.Before)

-- CS.active is only recomputed at round start, load and save, so a sandbox/PvP round started
-- after a campaign spawns its plain player bodies while it is still true: audit campaigns only.
local function inMpCampaign()
  local gs = Game.GameSession
  local c = gs and gs.Campaign
  return c ~= nil and LuaUserData.IsTargetType(c, 'Barotrauma.MultiPlayerCampaign')
end

-- Audit: a Lua error in the prefix fails open (vanilla runs), so check the result.
Hook.Add('roundStart', 'crewswap.audit', safe('audit', function()
  if not CS.active or not inMpCampaign() then return end
  for _, c in pairs(Client.ClientList) do
    local ch = c.Character
    if ch ~= nil and ch.Info ~= nil and not S.isAIBody(ch) then
      CS.fail('non-AI body for ' .. tostring(c.Name))
    end
  end
end))

Hook.Add('character.created', 'crewswap.audit2', safe('audit2', function(ch)
  if not CS.active or ch == nil or not inMpCampaign() then return end
  if ch.IsHuman and ch.IsRemotePlayer and ch.Info ~= nil and not S.isAIBody(ch) then
    CS.fail('non-AI body (respawn) for ' .. tostring(ch.Name))
  end
end))

local ST = require('crewswap.server.selftest')
ST.add('create-sig-resolves', function()
  if P.errors['crewswap.forceai'] ~= nil then return false, P.errors['crewswap.forceai'] end
  return true
end)

return S

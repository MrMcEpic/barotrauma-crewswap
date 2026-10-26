-- server/spawn.lua against fake Hook/Game/LuaUserData/Client globals.
local function fresh(campaign)
  package.loaded['crewswap.server.spawn'] = nil
  package.loaded['crewswap.server.patch'] = nil
  local hooks, patches = {}, {}
  _G.Hook = {
    Patch = function(id, class, method, types, fn, when) patches[#patches + 1] = { id = id, types = types, fn = fn, when = when } end,
    Add = function(ev, id, fn) hooks[ev] = fn end,
    HookMethodType = { Before = 'B', After = 'A' },
  }
  _G.CS = { active = true, failed = {}, fail = function(r) table.insert(_G.CS.failed, r); _G.CS.active = false end }
  _G.Game = { GameSession = { Campaign = campaign } }
  _G.Client = { ClientList = {} }
  _G.LuaUserData = { IsTargetType = function(o, ty) return o.types ~= nil and o.types[ty] == true end }
  _G.SERVER = true
  local realPrint = print
  print = function() end
  local ok, S = pcall(require, 'crewswap.server.spawn')
  print = realPrint
  assert(ok, S)
  return S, hooks, patches
end
local function args(over)
  local p = { isRemotePlayer = true, hasAi = false, characterInfo = {} }
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end
local MPC = { types = { ['Barotrauma.MultiPlayerCampaign'] = true } }
local function aiBody() return { Info = {}, types = { ['Barotrauma.AICharacter'] = true }, AIController = { types = { ['Barotrauma.HumanAIController'] = true } } } end

return {
 ['patch registered on the CharacterPrefab Create overload, Before'] = function(t)
   local _, _, patches = fresh({})
   t.eq(#patches, 1); t.eq(patches[1].when, 'B'); t.eq(#patches[1].types, 10)
   t.eq(patches[1].types[1], 'Barotrauma.CharacterPrefab'); t.eq(patches[1].types[10], 'System.Boolean')
 end,
 ['forces hasAi for a campaign remote player body'] = function(t)
   local _, _, patches = fresh({})
   local p = args()
   t.eq(patches[1].fn(nil, p), nil)
   t.eq(p.hasAi, true)
 end,
 ['leaves hasAi alone when any condition fails'] = function(t)
   local cases = {
     function(p) _G.CS.active = false end,
     function(p) p.isRemotePlayer = false end,
     function(p) p.hasAi = true end,
     function(p) p.characterInfo = nil end,
     function(p) _G.Game.GameSession.Campaign = nil end,
     function(p) _G.Game.GameSession = nil end,
   }
   for i, mutate in ipairs(cases) do
     local _, _, patches = fresh({})
     local p = args(); mutate(p)
     local was = p.hasAi
     t.eq(patches[1].fn(nil, p), nil, 'case ' .. i)
     t.eq(p.hasAi, was, 'case ' .. i)
   end
 end,
 ['isAIBody needs AICharacter and a HumanAIController'] = function(t)
   local S = fresh({})
   t.eq(S.isAIBody(aiBody()), true)
   local plain = { types = {} }
   t.eq(S.isAIBody(plain), false)
   local noCtl = aiBody(); noCtl.AIController = nil
   t.eq(S.isAIBody(noCtl), false)
   local wrongCtl = aiBody(); wrongCtl.AIController = { types = { ['Barotrauma.EnemyAIController'] = true } }
   t.eq(S.isAIBody(wrongCtl), false)
 end,
 ['roundStart audit fails closed on a non-AI client body'] = function(t)
   local _, hooks = fresh(MPC)
   _G.Client.ClientList = { { Name = 'a', Character = aiBody() }, { Name = 'b', Character = nil } }
   hooks.roundStart(); t.eq(#_G.CS.failed, 0)
   _G.Client.ClientList = { { Name = 'c', Character = { Info = {}, types = {} } } }
   local realPrint = print; print = function() end
   hooks.roundStart(); print = realPrint
   t.eq(#_G.CS.failed, 1); t.ok(_G.CS.failed[1]:find('non-AI body', 1, true))
 end,
 ['audits stay silent outside a multiplayer campaign, even on a stale CS.active'] = function(t)
   -- a sandbox/PvP round after a campaign: CS.active is still true from the campaign
   for _, campaign in ipairs({ false, {} }) do
     local _, hooks = fresh(campaign or nil)
     _G.Client.ClientList = { { Name = 'c', Character = { Info = {}, types = {} } } }
     hooks.roundStart()
     hooks['character.created']({ IsHuman = true, IsRemotePlayer = true, Info = {}, Name = 'x', types = {} })
     t.eq(#_G.CS.failed, 0); t.eq(_G.CS.active, true)
   end
 end,
 ['audit is silent while inactive'] = function(t)
   local _, hooks = fresh({})
   _G.CS.active = false
   _G.Client.ClientList = { { Name = 'c', Character = { Info = {}, types = {} } } }
   hooks.roundStart(); t.eq(#_G.CS.failed, 0)
 end,
 ['character.created audit flags a non-AI remote human with Info'] = function(t)
   local _, hooks = fresh(MPC)
   hooks['character.created'](aiBody())
   hooks['character.created']({ IsHuman = true, IsRemotePlayer = false, Info = {}, types = {} })
   hooks['character.created']({ IsHuman = true, IsRemotePlayer = true, Info = nil, types = {} })
   t.eq(#_G.CS.failed, 0)
   local b = { IsHuman = true, IsRemotePlayer = true, Info = {}, Name = 'x', types = {} }
   local realPrint = print; print = function() end
   hooks['character.created'](b); print = realPrint
   t.eq(#_G.CS.failed, 1); t.ok(_G.CS.failed[1]:find('non-AI body', 1, true))
 end,
}

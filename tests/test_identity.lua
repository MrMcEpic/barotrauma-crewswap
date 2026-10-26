-- server/identity.lua against fake game globals: what the save patches write while the mod is
-- locked down, and the mirror carrying the per-character records.
local registry = require('crewswap.core.registry')

local W   -- the current fake world

-- A tiny XElement: attributes, children, ToString as a Lua-readable dump.
local function xel(name)
  local e = { name = name, attrs = {}, kids = {} }
  function e:SetAttribute(k, v) self.attrs[k] = v end
  function e:GetAttributeString(k, d) local v = self.attrs[k]; if v == nil then return d end; return v end
  function e:Add(c) self.kids[#self.kids + 1] = c end
  function e:Element(n) for _, c in ipairs(self.kids) do if c.name == n then return c end end end
  function e:Elements() return self.kids end
  function e:ToString() local id = #W.docs + 1; W.docs[id] = self; return 'doc:' .. id end
  return e
end

local function info(id, name)
  local ci = { ID = id, OriginalName = name, Name = name }
  function ci:GetIdentifierUsingOriginalName() return 'h' .. name end
  return ci
end

local function world()
  for _, m in ipairs({ 'game', 'patch', 'selftest', 'identity' }) do
    package.loaded['crewswap.server.' .. m] = nil
  end
  W = { hooks = {}, patches = {}, files = {}, docs = {}, guids = 0 }
  _G.SERVER = true
  _G.Hook = { Add = function(ev, id, fn) W.hooks[ev .. '/' .. id] = fn end,
              Patch = function(id, class, method, a, b, c)
                local types, fn, when = a, b, c
                if type(a) == 'function' then types, fn, when = nil, a, b end
                W.patches[id] = { class = class, method = method, types = types, fn = fn, when = when }
              end,
              HookMethodType = { Before = 'B', After = 'A' } }
  _G.LuaUserData = {
    IsTargetType = function(o, ty) return type(o) == 'table' and o.types ~= nil and o.types[ty] == true end,
    RegisterType = function(name) return { name = name } end,
    MakeFieldAccessible = function() end,
    CreateStatic = function(name)
      if name == 'System.Guid' then
        return { NewGuid = function()
          W.guids = W.guids + 1
          local s = string.format('%032d', W.guids)
          return { ToString = function() return s end }
        end }
      end
      return { TotalTime = 0 }
    end,
    CreateEnumTable = function() return { None = 0, MidRound = 1, BetweenRounds = 2, Permadeath = 3 } end,
  }
  _G.XName = { Get = function(n) return n end }
  _G.XElement = xel
  _G.XDocument = { Parse = function(s) return { Root = W.docs[tonumber(s:match('doc:(%d+)'))] } end }
  _G.File = { Exists = function(p) return W.files[p] ~= nil end, Read = function(p) return W.files[p] end,
              Write = function(p, s) W.files[p] = s end,
              Move = function(a, b) W.files[b] = W.files[a]; W.files[a] = nil end }
  _G.Character = { CharacterList = {} }
  _G.Client = { ClientList = {} }
  W.roster, W.ccd = { info(11, 'Bot1'), info(12, 'Bot2') }, { info(1, 'Ann') }
  local campaign = setmetatable({ types = { ['Barotrauma.MultiPlayerCampaign'] = true }, CampaignID = 7 },
    { __index = function(_, k)
        if k == 'characterData' then
          local out = {}
          for i, ci in ipairs(W.ccd) do out[i] = { CharacterInfo = ci } end
          return out
        end
      end })
  campaign.CrewManager = { GetCharacterInfos = function() return W.roster end }
  W.campaign = campaign
  _G.Game = { GameSession = { Campaign = nil, DataPath = { SavePath = '/saves/Multiplayer/c.save' } },
              ServerSettings = { IronmanModeActive = false }, SaveFolder = '/saves' }
  local reg = registry.new()
  _G.CS = { active = false, lockdown = true, versionOk = true, campaignOk = true, reg = reg, pending = {} }
  function CS.fail() end
  function CS.recomputeActive() return CS.active end
  local realPrint = print
  print = function() end
  local ok, M = pcall(require, 'crewswap.server.identity')
  print = realPrint
  assert(ok, M)
  return M
end

local function quiet(fn, ...)
  local realPrint = print
  print = function() end
  local r = table.pack(pcall(fn, ...))
  print = realPrint
  assert(r[1], r[2])
  return table.unpack(r, 2, r.n)
end

local function saveCampaign()
  local root = xel('Gamesession')
  local p = { element = root, isSavingOnLoading = false }
  quiet(W.patches['crewswap.mpc.save.pre'].fn, W.campaign, p)
  root:Add(xel('MultiPlayerCampaign'))
  quiet(W.patches['crewswap.mpc.save.post'].fn, W.campaign, p)
  return root
end

local function ciSave(ci)
  local el = xel('Character')
  quiet(W.patches['crewswap.ci.save'].fn, ci, { ReturnValue = el })
  return el
end

return {
  ['identity: a locked-down campaign still writes the ids and records it holds'] = function(t)
    world()
    CS.campaignObjId = 7
    CS.campaignGuid = 'g'
    CS.reg:bind(11, 'sB1'); CS.reg:record('sB1').wbal = 300
    CS.reg:bind(1, 'sA'); CS.reg:record('sA').owner = 'STEAM_A'
    local root = saveCampaign()
    t.eq(CS.reg:sidOf(12), nil, 'no new id minted while locked down')
    t.eq(CS.reg:sidOf(11), 'sB1', 'existing bindings kept')
    local cs = root:Element('MultiPlayerCampaign'):Element('CrewSwap')
    t.ok(cs ~= nil, '<CrewSwap> written'); t.eq(cs.attrs.campaignguid, 'g')
    local el = ciSave(W.roster[1])
    t.eq(el.attrs.crewswap_id, 'sB1'); t.eq(el.attrs.crewswap_wbal, '300')
    t.eq(ciSave(W.ccd[1]).attrs.crewswap_owner, 'STEAM_A')
    t.eq(next(ciSave(W.roster[2]).attrs), nil, 'unbound info left vanilla')
  end,
  ['identity: a non-campaign or Ironman save writes nothing'] = function(t)
    world()
    CS.campaignOk = false
    CS.reg:bind(11, 'sB1')
    t.eq(next(ciSave(W.roster[1]).attrs), nil)
    local root = saveCampaign()
    t.eq(root:Element('MultiPlayerCampaign'):Element('CrewSwap'), nil)
  end,
  ['identity: an active save mints ids; the mirror carries the records'] = function(t)
    world()
    CS.active, CS.lockdown = true, false
    CS.campaignObjId = 7; CS.campaignGuid = 'g'
    CS.reg:bind(11, 'sB1'); CS.reg:record('sB1').wbal = 300
    saveCampaign()
    t.ok(CS.reg:sidOf(12) ~= nil, 'minted'); t.ok(CS.reg:sidOf(1) ~= nil, 'minted')
    t.ok(W.files['/saves/Multiplayer/c_CrewSwap.xml'] ~= nil, 'mirror written')
    -- a save written while the mod was off drops every attribute; the mirror brings them back
    local M = require('crewswap.server.identity')
    CS.reg, CS.pending = registry.new(), {}
    CS.campaignGuid = 'g'
    quiet(M.bindMissing, { W.roster[1], W.roster[2], W.ccd[1] }, false)
    t.eq(CS.reg:sidOf(11), 'sB1')
    t.eq(CS.reg.chars.sB1.wbal, 300, 'record restored from the mirror')
  end,
  ['identity: a record the save already has is not overwritten by the mirror'] = function(t)
    world()
    CS.active, CS.lockdown = true, false
    CS.campaignObjId = 7; CS.campaignGuid = 'g'
    CS.reg:bind(11, 'sB1'); CS.reg:record('sB1').wbal = 300
    saveCampaign()
    local M = require('crewswap.server.identity')
    CS.reg, CS.pending = registry.new(), {}
    CS.reg.chars.sB1 = { wbal = 999 }   -- loaded from the save's own attributes earlier
    quiet(M.bindMissing, { W.roster[1] }, false)
    t.eq(CS.reg.chars.sB1.wbal, 999)
  end,
}

-- Stable character identity and campaign-level mod state.
-- Every crew CharacterInfo gets a GUID ("sid"), saved as crewswap_* attributes on its vanilla
-- <Character> element; the campaign GUID rides in <MultiPlayerCampaign><CrewSwap/>. So mod state
-- saves, reverts and backs up exactly with vanilla. <save>_CrewSwap.xml next to the save is a
-- recovery mirror only (Lua reload / mod-off gap), never the source of truth.
local registry = require('crewswap.core.registry')
local mirror = require('crewswap.core.mirror')
local build = require('crewswap.shared.build')
local P = require('crewswap.server.patch')
local G = require('crewswap.server.game')

local M = {}

CS.reg = CS.reg or registry.new()
CS.pending = CS.pending or {}   -- [CharacterInfo.ID] = {sid=, rec=} read by the XML constructor
CS.dupes = CS.dupes or {}       -- sids found on two live crew infos at the last load (read by the integrity check)
CS.campaignGuid = CS.campaignGuid
CS.campaignObjId = CS.campaignObjId   -- MultiPlayerCampaign.CampaignID of the campaign object seen

local MPC = LuaUserData.RegisterType('Barotrauma.MultiPlayerCampaign')
LuaUserData.MakeFieldAccessible(MPC, 'characterData')
LuaUserData.RegisterType('System.Guid')
local Guid = LuaUserData.CreateStatic('System.Guid')

local function log(s) print('[CrewSwap] identity: ' .. s) end

-- CLR collections: the one converter (copied tables, iterators and userdata enumerables).
local function each(x) return G.list(x) end

-- Wrap a patch callback: errors are logged, never thrown into the game, and nothing is
-- returned (a non-void return would overwrite the patched method's result).
local function guard(name, fn)
  return function(instance, p)
    local ok, err = pcall(fn, instance, p)
    if not ok then log(name .. ' callback error: ' .. tostring(err)) end
  end
end

function CS.newGuid()
  local ok, s = pcall(function() return Guid.NewGuid():ToString('N') end)
  if ok and type(s) == 'string' and #s == 32 then return s end
  local t = {}
  for i = 1, 32 do t[i] = string.format('%x', math.random(0, 15)) end
  return table.concat(t)
end

-- Live crew of a campaign: bots (incl. reserve bench), every player home, Ironman's backups.
-- The second result marks the infos that came only from the Ironman backup list.
local function collect(campaign)
  local out, seen, backup = {}, {}, {}
  local function add(ci, isBackup)
    if ci ~= nil and not seen[ci.ID] then
      seen[ci.ID] = true
      out[#out + 1] = ci
      if isBackup then backup[ci.ID] = true end
    end
  end
  local cm = campaign.CrewManager
  if cm ~= nil then
    for _, ci in ipairs(each(cm:GetCharacterInfos(true))) do add(ci) end
  end
  for _, cd in ipairs(each(campaign.characterData)) do add(cd.CharacterInfo) end
  for _, cd in ipairs(each(campaign.replacedCharacterDataBackup)) do add(cd.CharacterInfo, true) end
  return out, backup
end

function CS.liveCrewInfos(campaign)
  return (collect(campaign))
end

function CS.sidOfInfo(info)
  local sid = CS.reg:sidOf(info.ID)
  if sid then return sid end
  local pend = CS.pending[info.ID]
  if pend then
    sid = pend.sid
    CS.pending[info.ID] = nil
    if CS.reg.chars[sid] == nil then CS.reg.chars[sid] = pend.rec end
  else
    sid = CS.newGuid()
    CS.minted = (CS.minted or 0) + 1
  end
  CS.reg:bind(info.ID, sid)
  CS.reg:record(sid)
  return sid
end

-- ---------- mirror file ----------

local function mirrorPath()
  local gs = Game.GameSession
  local savePath = gs and gs.DataPath.SavePath
  if savePath == nil or savePath == '' then return nil end
  return (tostring(savePath):gsub('%.save$', '')) .. '_CrewSwap.xml'
end

-- One odd info (no head, no job prefab) must not stop the others from matching: '' never matches.
local function keyOf(ci)
  local okJ, job = pcall(function() return ci.Job and tostring(ci.Job.Prefab.Identifier) or '' end)
  local okH, h = pcall(function() return tostring(ci:GetIdentifierUsingOriginalName()) end)
  return { sessionId = ci.ID, on = tostring(ci.OriginalName or ''),
           h = okH and h or '', job = okJ and job or '' }
end

-- rows = {{sid=, on=, h=, job=, rec=}}; written via a .tmp file and a move, so a crash never
-- leaves a half-written mirror. Each row carries its record, so a save made while the mod was
-- off (no crewswap_* attributes) can still be reconciled.
function M.writeMirror(path, guid, rows)
  local root = XElement(XName.Get('CrewSwapMirror'))
  root:SetAttribute('campaignguid', guid or '')
  for _, r in ipairs(rows) do
    local c = XElement(XName.Get('c'))
    for k, v in pairs(mirror.rowAttrs(r)) do c:SetAttribute(k, v) end
    root:Add(c)
  end
  File.Write(path .. '.tmp', root:ToString())
  File.Move(path .. '.tmp', path)
end

-- → guid, entries ({[sid]={on,h,job,rec}}), or nil when there is no readable mirror.
function M.readMirror(path)
  if path == nil or not File.Exists(path) then return nil end
  local root = XDocument.Parse(File.Read(path)).Root
  local entries = {}
  for _, c in ipairs(each(root:Elements())) do
    local sid, e = mirror.parseRow(function(name) return c:GetAttributeString(name, '') end)
    if sid ~= nil then entries[sid] = e end
  end
  return root:GetAttributeString('campaignguid', ''), entries
end

-- Bind infos that have no sid: first from the mirror (if it belongs to this campaign), then,
-- when allowMint, with fresh GUIDs. A save with no <CrewSwap> adopts the mirror's GUID only if
-- the mirror re-matches at least half of the unbound crew (guards against a stale mirror left
-- by a deleted campaign of the same name).
local function bindMissing(infos, allowMint)
  local unbound = {}
  for _, ci in ipairs(infos) do
    if CS.reg:sidOf(ci.ID) == nil and CS.pending[ci.ID] == nil then unbound[#unbound + 1] = ci end
  end
  if #unbound > 0 then
    local ok, mguid, entries = pcall(M.readMirror, mirrorPath())
    if not ok then log('mirror unreadable: ' .. tostring(mguid)); entries = nil end
    if entries and mguid ~= '' and (CS.campaignGuid == nil or mguid == CS.campaignGuid) then
      for _, sid in pairs(CS.reg.bySession) do entries[sid] = nil end
      for _, p in pairs(CS.pending) do entries[p.sid] = nil end
      local live = {}
      for _, ci in ipairs(unbound) do live[#live + 1] = keyOf(ci) end
      local m = mirror.match(entries, live)
      local n = 0
      for _ in pairs(m) do n = n + 1 end
      if CS.campaignGuid == nil then
        if n > 0 and n * 2 >= #unbound then CS.campaignGuid = mguid else m, n = {}, 0 end
      end
      for sessionId, sid in pairs(m) do
        CS.reg:bind(sessionId, sid)
        -- the save had no record for it (mod-off gap / Lua reload): take the mirror's
        local have = CS.reg.chars[sid]
        if (have == nil or next(have) == nil) and entries[sid].rec ~= nil then
          local rec = {}
          for k, v in pairs(entries[sid].rec) do rec[k] = v end
          CS.reg.chars[sid] = rec
        end
        CS.reg:record(sid)
      end
      if n > 0 then log('re-matched ' .. n .. ' of ' .. #unbound .. ' from the mirror') end
    end
  end
  if allowMint then
    for _, ci in ipairs(infos) do CS.sidOfInfo(ci) end
  end
end
M.bindMissing = bindMissing

-- ---------- patches ----------

-- Write the sid and the record onto the <Character> element vanilla just built.
P.patch('crewswap.ci.save', 'Barotrauma.CharacterInfo', 'Save', { 'System.Xml.Linq.XElement' },
  guard('ci.save', function(info, p)
    if not CS.campaignOk then return end   -- also during a lockdown: existing data must survive
    local sid = CS.reg:sidOf(info.ID)
    if sid == nil then return end
    local el = p.ReturnValue
    if el == nil then return end
    el:SetAttribute(registry.ID_ATTR, sid)
    for k, v in pairs(registry.encodeAttrs(CS.reg.chars[sid] or {})) do el:SetAttribute(k, v) end
  end), Hook.HookMethodType.After)

-- Read them back whenever an info is built from XML. Not gated on CS.active: it runs
-- during campaign load, before activity is known.
P.patch('crewswap.ci.ctorxml', 'Barotrauma.CharacterInfo', '.ctor',
  { 'Barotrauma.ContentXElement', 'Barotrauma.Identifier' },
  guard('ci.ctor', function(info, p)
    local cx = p['infoElement']
    if cx == nil then return end
    local sid = cx:GetAttributeString(registry.ID_ATTR, '')
    if sid == '' then return end
    local map = {}
    for _, attr in pairs(registry.FIELDS) do map[attr] = cx:GetAttributeString(attr, '') end
    CS.pending[info.ID] = { sid = sid, rec = registry.decodeAttrs(map) }
  end), Hook.HookMethodType.After)

-- After every load (fresh, failed-round reload, backup): rebuild the registry.
-- GameMode isn't set yet here, so everything uses the patch instance.
P.patch('crewswap.mpc.load', 'Barotrauma.MultiPlayerCampaign', 'Load', { 'System.Xml.Linq.XElement' },
  guard('mpc.load', function(campaign, p)
    local el = p['element']:Element(XName.Get('CrewSwap'))
    local map = {}
    if el ~= nil then
      for _, attr in pairs(registry.CAMPAIGN_ATTRS) do map[attr] = el:GetAttributeString(attr, '') end
    end
    CS.campaignGuid = registry.parseCampaignElement(map).campaignGuid

    CS.reg, CS.dupes = registry.new(), {}
    local infos, backup = collect(campaign)
    local seen = {}
    for _, ci in ipairs(infos) do
      local pend = CS.pending[ci.ID]
      if pend then
        if seen[pend.sid] and not backup[ci.ID] and not backup[seen[pend.sid]] then
          CS.dupes[#CS.dupes + 1] = pend.sid
          log('duplicate id ' .. pend.sid .. ' on two crew members')
        end
        seen[pend.sid] = seen[pend.sid] or ci.ID
        CS.reg:bind(ci.ID, pend.sid)
        if CS.reg.chars[pend.sid] == nil then CS.reg.chars[pend.sid] = pend.rec end
      end
    end
    CS.pending = {}
    bindMissing(infos, false)
    local bound = 0
    for _ in pairs(CS.reg.bySession) do bound = bound + 1 end
    log('load bound ' .. bound .. ' of ' .. #infos .. ' crew, campaign ' .. tostring(CS.campaignGuid))

    CS.campaignObjId = campaign.CampaignID
    CS.recomputeActive(campaign)
  end), Hook.HookMethodType.After)

-- Before every save: a campaign object we never saw load is a new campaign (fresh registry and
-- GUID). Then every live crew member gets a sid before CharacterInfo.Save runs.
P.patch('crewswap.mpc.save.pre', 'Barotrauma.MultiPlayerCampaign', 'Save',
  { 'System.Xml.Linq.XElement', 'System.Boolean' },
  guard('mpc.save.pre', function(campaign, p)
    CS.recomputeActive(campaign)
    if not CS.campaignOk then return end
    -- A lockdown still writes back every id and record held; only minting waits for CS.active.
    if campaign.CampaignID ~= CS.campaignObjId then
      CS.campaignObjId = campaign.CampaignID
      CS.reg, CS.dupes, CS.pending = registry.new(), {}, {}
      CS.campaignGuid = CS.newGuid()
      log('new campaign ' .. CS.campaignGuid)
    end
    local infos = collect(campaign)
    local mintedBefore = CS.minted or 0
    bindMissing(infos, CS.active == true)
    -- After a restart or reload mid-campaign this must show 0 for existing crew
    log('save: minted ' .. ((CS.minted or 0) - mintedBefore) .. ' new ids for ' .. #infos .. ' crew')
    if CS.campaignGuid == nil then CS.campaignGuid = CS.newGuid() end
    local ids = {}
    for _, ci in ipairs(infos) do ids[#ids + 1] = ci.ID end
    CS.reg:prune(ids)
    CS.pending = {}
  end), Hook.HookMethodType.Before)

-- After every save: <CrewSwap> into the MultiPlayerCampaign element, then the mirror file.
P.patch('crewswap.mpc.save.post', 'Barotrauma.MultiPlayerCampaign', 'Save',
  { 'System.Xml.Linq.XElement', 'System.Boolean' },
  guard('mpc.save.post', function(campaign, p)
    if not CS.campaignOk then return end
    local mode = p['element']:Element(XName.Get('MultiPlayerCampaign'))
    if mode == nil then log('no MultiPlayerCampaign element in the save'); return end
    local cs = XElement(XName.Get('CrewSwap'))
    local attrs = registry.campaignElement({ campaignGuid = CS.campaignGuid, modVersion = build.MODVERSION })
    for k, v in pairs(attrs) do cs:SetAttribute(k, v) end
    mode:Add(cs)

    if p['isSavingOnLoading'] then return end
    local path = mirrorPath()
    if path == nil then return end
    local rows = {}
    for _, ci in ipairs(collect(campaign)) do
      local sid = CS.reg:sidOf(ci.ID)
      if sid then
        local k = keyOf(ci)
        rows[#rows + 1] = { sid = sid, on = k.on, h = k.h, job = k.job, rec = CS.reg.chars[sid] }
      end
    end
    local ok, err = pcall(M.writeMirror, path, CS.campaignGuid, rows)
    if not ok then log('mirror write failed: ' .. tostring(err)) end
  end), Hook.HookMethodType.After)

-- A Lua reload mid-campaign empties the registry while the infos stay loaded: re-match them
-- from the mirror now (no minting), and remember the campaign object so the next save
-- doesn't take it for a new campaign.
do
  local ok, err = pcall(function()
    local gs = Game.GameSession
    local campaign = gs and gs.Campaign
    if campaign == nil or not LuaUserData.IsTargetType(campaign, 'Barotrauma.MultiPlayerCampaign') then return end
    if CS.campaignObjId == campaign.CampaignID then return end
    CS.campaignObjId = campaign.CampaignID
    bindMissing(collect(campaign), false)
    log('reload recovery, campaign ' .. tostring(CS.campaignGuid))
  end)
  if not ok then log('reload recovery skipped: ' .. tostring(err)) end
end

-- ---------- self-test ----------
local selftest = require('crewswap.server.selftest')
local saved   -- the <Character> element from ci-save-attr, read back by ci-ctor-read
local SELFTEST_SID = 'selftest00000000000000000000000'

selftest.add('ci-save-attr', function()
  local info = CharacterInfo(Identifier('human'))
  CS.reg:bind(info.ID, SELFTEST_SID)
  CS.reg:record(SELFTEST_SID).lastAt = 1700000000
  local wasOk = CS.campaignOk
  CS.campaignOk = true
  local ok, el = pcall(function() return info:Save(XElement(XName.Get('x'))) end)
  CS.campaignOk = wasOk
  CS.reg.bySession[info.ID] = nil
  CS.reg.chars[SELFTEST_SID] = nil
  if not ok then return false, 'Save threw: ' .. tostring(el) end
  if el == nil then return false, 'Save returned nil' end
  if el:GetAttributeString(registry.ID_ATTR, '') ~= SELFTEST_SID then return false, 'no crewswap_id on ' .. tostring(el) end
  if el:GetAttributeString('crewswap_lastat', '') ~= '1700000000' then return false, 'no crewswap_lastat' end
  saved = el
  return true
end)

selftest.add('ci-ctor-read', function()
  if saved == nil then return 'skip', 'ci-save-attr did not produce an element' end
  local ok, info = pcall(function() return CharacterInfo(ContentXElement(nil, saved)) end)
  if not ok then return false, 'ctor threw: ' .. tostring(info) end
  local pend = CS.pending[info.ID]
  CS.pending[info.ID] = nil
  if pend == nil then return false, 'CS.pending has no entry for the new info' end
  if pend.sid ~= SELFTEST_SID then return false, 'pending sid is ' .. tostring(pend.sid) end
  if pend.rec.lastAt ~= 1700000000 then return false, 'pending lastAt is ' .. tostring(pend.rec.lastAt) end
  return true
end)

selftest.add('mirror-io', function()
  local path = Game.SaveFolder .. '/CrewSwap/selftest_CrewSwap.xml'
  M.writeMirror(path, 'g1', { { sid = 'aa', on = 'Ann', h = '-12', job = 'medic', rec = { wbal = 300 } } })
  local guid, entries = M.readMirror(path)
  File.Delete(path)
  if guid ~= 'g1' then return false, 'guid ' .. tostring(guid) end
  local e = entries and entries['aa']
  if e == nil or e.on ~= 'Ann' or e.h ~= '-12' or e.job ~= 'medic' then return false, 'entry did not round-trip' end
  if e.rec == nil or e.rec.wbal ~= 300 then return false, 'record did not round-trip' end
  if File.Exists(path .. '.tmp') then return false, '.tmp left behind' end
  return true
end)

return M

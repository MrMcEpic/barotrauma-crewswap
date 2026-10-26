-- Server-side game adapter: turns live game objects into the plain views core/ consumes, and
-- wraps the chat/time/settings calls the other server modules need. Crew enumeration: the
-- server CrewManager holds bots only, so crew = Team1 humans whose
-- Info is a CCD info (player homes) or in CrewManager.GetCharacterInfos(true) (bots, bench).
if not SERVER then return end

local G = {}

G.DEFAULT_TOGGLES = { pool = 'shared', protect = true }

-- CLR collections arrive as copied tables (List<T>), as iterator functions (converted
-- IEnumerables) or as userdata enumerables (e.g. a LINQ Concat); always returns an array.
-- A userdata is tried with `for v in x` first, then through GetEnumerator/MoveNext/Current.
local function viaForIn(x)
  local out = {}
  for v in x do out[#out + 1] = v end
  return out
end

local function viaEnumerator(x)
  local out = {}
  local e = x:GetEnumerator()
  while e:MoveNext() do out[#out + 1] = e.Current end
  return out
end

-- The non-table path, exposed for the unit tests (plain Lua has no userdata to hand).
function G.iterate(x)
  if type(x) == 'function' then return viaForIn(x) end
  local ok, out = pcall(viaForIn, x)
  if ok then return out end
  local ok2, out2 = pcall(viaEnumerator, x)
  if ok2 then return out2 end
  error('cannot iterate ' .. tostring(x) .. ' (for-in: ' .. tostring(out) .. '; enumerator: ' .. tostring(out2) .. ')')
end

function G.list(x)
  local out = {}
  if x == nil then return out end
  if type(x) == 'table' then
    if #x > 0 then
      for i = 1, #x do out[i] = x[i] end
    else
      for _, v in pairs(x) do out[#out + 1] = v end
    end
    return out
  end
  return G.iterate(x)
end

-- AccountId string, or the client's address when it has none (matches CCD.ClientAddress).
function G.accountKey(client)
  local id = client.AccountId
  if id ~= nil then return id.StringRepresentation end
  return 'addr:' .. tostring(client.Connection.Endpoint.Address.StringRepresentation)
end

function G.clients() return G.list(Client.ClientList) end

function G.campaign()
  local gs = Game.GameSession
  local c = gs and gs.Campaign
  if c == nil or not LuaUserData.IsTargetType(c, 'Barotrauma.MultiPlayerCampaign') then return nil end
  return c
end

-- Session ids (CharacterInfo.ID) of every bot and reserve-bench info.
local function botInfoIds(campaign)
  local ids = {}
  local cm = campaign.CrewManager
  if cm ~= nil then
    for _, ci in ipairs(G.list(cm:GetCharacterInfos(true))) do ids[ci.ID] = true end
  end
  return ids
end

local function isCrewWith(ch, campaign, botIds)
  if ch == nil or ch.Removed or ch.Info == nil or not ch.IsHuman then return false end
  if ch.TeamID ~= CharacterTeamType.Team1 then return false end
  if campaign:GetCharacterData(ch.Info) ~= nil then return true end
  return (botIds or botInfoIds(campaign))[ch.Info.ID] == true
end

function G.isCrew(ch)
  local campaign = G.campaign()
  if campaign == nil then return false end
  return isCrewWith(ch, campaign)
end

function G.controllerOf(ch)
  for _, c in ipairs(G.clients()) do
    if c.Character == ch then return c end
  end
  return nil
end

local function ccdKey(ccd)
  if ccd == nil then return nil end
  local id = ccd.AccountId
  if id ~= nil then return id.StringRepresentation end
  if ccd.ClientAddress ~= nil then return 'addr:' .. tostring(ccd.ClientAddress.StringRepresentation) end
  return nil
end

-- The account whose home this body is (its info is that player's CCD info), or nil.
function G.homeOf(ch)
  local campaign = G.campaign()
  if campaign == nil or ch == nil or ch.Info == nil then return nil end
  return ccdKey(campaign:GetCharacterData(ch.Info))
end

-- The client's home body, looked up live rather than cached (survives respawns and mid-round joins).
function G.homeBodyOf(client)
  local campaign = G.campaign()
  if campaign == nil then return nil end
  local ccd = campaign:GetClientCharacterData(client)
  if ccd == nil or ccd.CharacterInfo == nil then return nil end
  local info = ccd.CharacterInfo
  for _, ch in ipairs(G.list(Character.CharacterList)) do
    if ch.Info == info and not ch.Removed then return ch end
  end
  return nil
end

local function buildView(ch, campaign, botIds)
  local S = require('crewswap.server.spawn')
  local crew = isCrewWith(ch, campaign, botIds)
  local ctl = G.controllerOf(ch)
  local controller, controllerName
  if ctl ~= nil then
    controller, controllerName = G.accountKey(ctl), tostring(ctl.Name)
  elseif ch.IsRemotePlayer then
    -- owned by a client that is gone; not Free until the mod releases it
    controller, controllerName = 'remote:?', ''
  end
  local sid   -- minted only while active: a mod-off campaign must stay vanilla
  if crew and CS.active then sid = CS.sidOfInfo(ch.Info) elseif crew then sid = CS.reg:sidOf(ch.Info.ID) end
  local rec = sid and CS.reg.chars[sid]
  return {
    id = ch.ID, sid = sid, alive = not ch.IsDead, conscious = not ch.IsIncapacitated,
    removed = ch.Removed == true, crew = crew, isAI = S.isAIBody(ch),
    controller = controller, controllerName = controllerName,
    homeOf = crew and ccdKey(campaign:GetCharacterData(ch.Info)) or nil,
    owner = rec and rec.owner or nil, name = tostring(ch.Name),
  }
end

-- View of any character; crew=false for non-crew (rules.validate then says 'invalid').
function G.view(ch)
  local campaign = G.campaign()
  if ch == nil or campaign == nil or not LuaUserData.IsTargetType(ch, 'Barotrauma.Character') then return nil end
  return buildView(ch, campaign)
end

function G.crewViews()
  local campaign = G.campaign()
  local out = {}
  if campaign == nil then return out end
  local botIds = botInfoIds(campaign)
  for _, ch in ipairs(G.list(Character.CharacterList)) do
    if isCrewWith(ch, campaign, botIds) then out[#out + 1] = buildView(ch, campaign, botIds) end
  end
  return out
end

function G.tell(client, text)
  Game.SendDirectChatMessage('CrewSwap', text, nil, ChatMessageType.Server, client)
end

function G.announce(text) Game.SendMessage(text, ChatMessageType.Server) end

function G.isAdmin(client) return client:HasPermission(ClientPermissions.ManageSettings) == true end

local Timing = LuaUserData.CreateStatic('Barotrauma.Timing')
function G.now() return Timing.TotalTime end

-- RespawnMode arrives as a number; compare against the enum table.
local RespawnMode = LuaUserData.CreateEnumTable('Barotrauma.Networking.RespawnMode')
function G.isPermadeath() return Game.ServerSettings.RespawnMode == RespawnMode.Permadeath end

-- Pool/protect toggles: CS.config.toggles, loaded from <SaveFolder>/CrewSwap/config.txt by server/admin.lua.
function G.toggles()
  local cfg = CS.config
  return (cfg ~= nil and cfg.toggles ~= nil) and cfg.toggles or G.DEFAULT_TOGGLES
end

-- The first round of a campaign proves the real crew list converts (the selftests run before
-- any campaign is loaded). A failure here would break every crew lookup, so the mod goes off.
local liveChecked = false
function G.checkLiveList()
  if liveChecked then return end
  local campaign = G.campaign()
  local cm = campaign and campaign.CrewManager
  if cm == nil then return end
  liveChecked = true
  local ok, err = pcall(function()
    local infos = G.list(cm:GetCharacterInfos(true))
    for i, ci in ipairs(infos) do
      if not LuaUserData.IsTargetType(ci, 'Barotrauma.CharacterInfo') then
        error('item ' .. i .. ' is ' .. tostring(ci))
      end
    end
    return #infos
  end)
  if ok then
    print('[CrewSwap] SELFTEST PASS live-crew-list')
  else
    print('[CrewSwap] SELFTEST FAIL live-crew-list: ' .. tostring(err))
    CS.fail('the crew list cannot be read: ' .. tostring(err))
  end
end
Hook.Add('roundStart', 'crewswap.game.listcheck', function()
  local ok, err = pcall(G.checkLiveList)
  if not ok then print('[CrewSwap] live-crew-list check error: ' .. tostring(err)) end
end)

local ST = require('crewswap.server.selftest')
ST.add('list-convert', function()
  local n = #G.list(Character.CharacterList)
  if not (n >= 0) then return false, 'CharacterList gave ' .. tostring(n) end
  local three = #G.list({ 'a', 'b', 'c' })
  if three ~= 3 then return false, 'a 3-element table gave ' .. tostring(three) end
  return true
end)

return G

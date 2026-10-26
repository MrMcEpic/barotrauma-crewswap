-- Pure: session id -> stable id bindings, per-character mod records, and their XML attribute form.
-- A record is {last, owner, home, wbal, wrd, lastAt}; it rides on the vanilla <Character> element
-- as crewswap_* attributes, and the campaign-level state as a <CrewSwap> element.
local M = {}

-- record field -> attribute name; NUMERIC fields are numbers in the record, strings in XML.
M.FIELDS = { last = 'crewswap_last', owner = 'crewswap_owner', home = 'crewswap_home',
             wbal = 'crewswap_wbal', wrd = 'crewswap_wrd', lastAt = 'crewswap_lastat' }
M.NUMERIC = { wbal = true, wrd = true, lastAt = true }
M.ID_ATTR = 'crewswap_id'

local R = {}
R.__index = R

function M.new()
  return setmetatable({ bySession = {}, chars = {} }, R)
end

function R:bind(sessionId, sid) self.bySession[sessionId] = sid end
function R:sidOf(sessionId) return self.bySession[sessionId] end

function R:record(sid)
  local rec = self.chars[sid]
  if rec == nil then rec = {}; self.chars[sid] = rec end
  return rec
end

-- Drop session bindings whose session id isn't in liveSessionIds. Records are kept.
function R:prune(liveSessionIds)
  local live = {}
  for _, id in ipairs(liveSessionIds) do live[id] = true end
  for id in pairs(self.bySession) do
    if not live[id] then self.bySession[id] = nil end
  end
end

function M.encodeAttrs(rec)
  local out = {}
  for field, attr in pairs(M.FIELDS) do
    local v = rec[field]
    if v ~= nil then out[attr] = tostring(v) end
  end
  return out
end

function M.decodeAttrs(map)
  local rec = {}
  for field, attr in pairs(M.FIELDS) do
    local v = map[attr]
    if v ~= nil and v ~= '' then
      if M.NUMERIC[field] then v = tonumber(v) end
      rec[field] = v
    end
  end
  return rec
end

local CAMPAIGN = { campaignGuid = 'campaignguid', modVersion = 'modversion' }
M.CAMPAIGN_ATTRS = CAMPAIGN

function M.campaignElement(state)
  local out = {}
  for field, attr in pairs(CAMPAIGN) do
    if state[field] ~= nil then out[attr] = tostring(state[field]) end
  end
  return out
end

function M.parseCampaignElement(map)
  local state = {}
  for field, attr in pairs(CAMPAIGN) do
    local v = map[attr]
    if v ~= nil and v ~= '' then state[field] = v end
  end
  return state
end

return M

-- Pure: fuzzy re-match of mirror entries to live crew after a Lua reload or a mod-off gap.
-- entries = {[sid] = {on=, h=, job=, rec=}}, live = {{sessionId=, on=, h=, job=}, ...}
-- Pass 1 pairs an entry and a live info that share an exact hash and nobody else shares it.
-- Pass 2 does the same on OriginalName among what pass 1 left. Anything ambiguous stays unmatched,
-- so every sid is claimed at most once and the answer doesn't depend on listing order.
local registry = require('crewswap.core.registry')

local M = {}

-- One mirror row <c .../> as attributes: id, on, h, job, plus the record's crewswap_* fields,
-- so a save written while the mod was off (which drops every crewswap_* attribute) can still
-- be reconciled. row = {sid=, on=, h=, job=, rec=}
function M.rowAttrs(row)
  local out = { id = row.sid, on = row.on or '', h = row.h or '', job = row.job or '' }
  for k, v in pairs(registry.encodeAttrs(row.rec or {})) do out[k] = v end
  return out
end

-- get(name) -> attribute string ('' when absent). → sid, {on=, h=, job=, rec=} | nil
function M.parseRow(get)
  local sid = get('id')
  if sid == nil or sid == '' then return nil end
  local map = {}
  for _, attr in pairs(registry.FIELDS) do map[attr] = get(attr) end
  return sid, { on = get('on'), h = get('h'), job = get('job'), rec = registry.decodeAttrs(map) }
end

local function pass(entries, live, key, claimed, out)
  local entryBy, liveBy = {}, {}
  for sid, e in pairs(entries) do
    local k = e[key]
    if not claimed[sid] and k ~= nil and k ~= '' then
      entryBy[k] = entryBy[k] or {}
      table.insert(entryBy[k], sid)
    end
  end
  for _, l in ipairs(live) do
    local k = l[key]
    if out[l.sessionId] == nil and k ~= nil and k ~= '' then
      liveBy[k] = liveBy[k] or {}
      table.insert(liveBy[k], l.sessionId)
    end
  end
  for k, sids in pairs(entryBy) do
    local ls = liveBy[k]
    if #sids == 1 and ls and #ls == 1 then
      out[ls[1]] = sids[1]
      claimed[sids[1]] = true
    end
  end
end

function M.match(entries, live)
  local out, claimed = {}, {}
  pass(entries, live, 'h', claimed, out)
  pass(entries, live, 'on', claimed, out)
  return out
end

return M

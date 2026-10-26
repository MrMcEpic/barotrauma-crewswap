-- Pure: the save integrity check over plain lists of stable ids (sids).
-- stores = {ccd={sid...}, roster={sid...}, table={sid...}}: every CCD's info, every
-- CrewManager info (active + bench) and every sid the mod's registry holds a record for.
-- legit = {permadead={[sid]=true}, fired={[sid]=true}, discarded={[sid]=true}, adopted={[sid]=true}}:
-- removals vanilla (or the mod) made on purpose this round (discarded = a player's vanilla
-- "create new character", or a dead home replaced by a takeover); adopted = a bot that became a player's new home in
-- Permadeath, which moves it roster -> CCD (vanilla keeps it in both until SavePlayers).
local M = {}

local function copy(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

-- `stale` = registry sids that were already in neither store at the snapshot: removals an earlier
-- round accepted (fired, permadead). Records are kept for the session, so later checks ignore them
-- instead of calling them 'unknown'.
function M.snapshot(stores)
  local present, stale = {}, {}
  for _, where in ipairs({ 'ccd', 'roster' }) do
    for _, sid in ipairs(stores[where] or {}) do present[sid] = true end
  end
  for _, sid in ipairs(stores.table or {}) do
    if not present[sid] then stale[sid] = true end
  end
  return { ccd = copy(stores.ccd), roster = copy(stores.roster), stale = stale }
end

-- → {[sid] = {ccd=n, roster=n}}
local function count(stores)
  local c = {}
  for _, where in ipairs({ 'ccd', 'roster' }) do
    for _, sid in ipairs(stores and stores[where] or {}) do
      c[sid] = c[sid] or { ccd = 0, roster = 0 }
      c[sid][where] = c[sid][where] + 1
    end
  end
  return c
end

local function place(n)
  if n.ccd > 0 and n.roster > 0 then return 'both' end
  return n.ccd > 0 and 'ccd' or 'roster'
end

-- → ok, problems (sorted strings: 'duplicate <sid>', 'missing <sid>', 'moved <sid>', 'unknown <sid>')
function M.check(startSnap, nowStores, legit)
  legit = legit or {}
  local adopted = legit.adopted or {}
  local removedOk = {}
  for _, kind in ipairs({ 'permadead', 'fired', 'discarded' }) do
    for sid in pairs(legit[kind] or {}) do removedOk[sid] = true end
  end
  local problems = {}
  local now, was = count(nowStores), count(startSnap)
  local stale = startSnap and startSnap.stale or {}

  for sid, n in pairs(now) do
    local overlapOk = adopted[sid] and n.ccd == 1 and n.roster == 1
    if n.ccd + n.roster > 1 and not overlapOk then
      problems[#problems + 1] = 'duplicate ' .. sid
    end
  end
  for sid, n in pairs(was) do
    local cur = now[sid]
    if cur == nil then
      if not removedOk[sid] then problems[#problems + 1] = 'missing ' .. sid end
    else
      local a, b = place(n), place(cur)
      if a ~= 'both' and b ~= 'both' and a ~= b and not adopted[sid] then
        problems[#problems + 1] = 'moved ' .. sid
      end
    end
  end
  for _, sid in ipairs(nowStores and nowStores.table or {}) do
    if now[sid] == nil and not stale[sid] and not removedOk[sid] then
      problems[#problems + 1] = 'unknown ' .. sid
    end
  end

  table.sort(problems)
  return #problems == 0, problems
end

return M

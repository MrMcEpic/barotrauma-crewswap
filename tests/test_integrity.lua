-- core/integrity.lua: the integrity check over plain sid lists.
local integrity = require('crewswap.core.integrity')

local NONE = { permadead = {}, fired = {} }

local function has(problems, s)
  for _, p in ipairs(problems) do if p == s then return true end end
  return false
end

local function start()
  return integrity.snapshot({ ccd = { 'homeA', 'homeB' }, roster = { 'bot1', 'bot2' } })
end

return {
  ['clean round passes'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeB', 'homeA' }, roster = { 'bot2', 'bot1' }, table = { 'homeA', 'bot1' } }, NONE)
    t.eq(ok, true); t.eq(#problems, 0)
  end,
  ['bot in roster and CCD is duplicate'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB', 'bot1' }, roster = { 'bot1', 'bot2' } }, NONE)
    t.eq(ok, false)
    t.ok(has(problems, 'duplicate bot1'), table.concat(problems, '; '))
    t.eq(#problems, 1, table.concat(problems, '; '))
  end,
  ['twice in one store is duplicate'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB' }, roster = { 'bot1', 'bot2', 'bot2' } }, NONE)
    t.eq(ok, false); t.eq(problems[1], 'duplicate bot2'); t.eq(#problems, 1)
  end,
  ['integrity flags a CCD holding a borrowed bot'] = function(t)
    -- the restore failed: SavePlayers folded the borrowed bot into homeA's CCD slot
    local ok, problems = integrity.check(start(),
      { ccd = { 'bot1', 'homeB' }, roster = { 'bot2' } }, NONE)
    t.eq(ok, false)
    t.ok(has(problems, 'missing homeA'), table.concat(problems, '; '))
    t.ok(has(problems, 'moved bot1'), table.concat(problems, '; '))
    t.eq(#problems, 2, table.concat(problems, '; '))
  end,
  ['permadeath removal is legit'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB' }, roster = { 'bot2' }, table = { 'bot1' } },
      { permadead = { bot1 = true }, fired = {} })
    t.eq(ok, true, table.concat(problems, '; '))
  end,
  ['fired removal is legit'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB' }, roster = { 'bot1' }, table = { 'bot2' } },
      { permadead = {}, fired = { bot2 = true } })
    t.eq(ok, true, table.concat(problems, '; '))
  end,
  ['discarded removal is legit (vanilla "create new character")'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeB' }, roster = { 'bot1', 'bot2' }, table = { 'homeA' } },
      { permadead = {}, fired = {}, discarded = { homeA = true } })
    t.eq(ok, true, table.concat(problems, '; '))
  end,
  ['new hire present now only is fine'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB', 'homeC' }, roster = { 'bot1', 'bot2', 'hire1' }, table = { 'hire1' } }, NONE)
    t.eq(ok, true, table.concat(problems, '; '))
  end,
  ['unknown table sid flagged'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB' }, roster = { 'bot1', 'bot2' }, table = { 'bot1', 'ghost' } }, NONE)
    t.eq(ok, false); t.eq(problems[1], 'unknown ghost'); t.eq(#problems, 1)
  end,
  ['a record already absent at the snapshot is not unknown later'] = function(t)
    -- bot2 was fired last round: its record stays in the registry for the session
    local snap = integrity.snapshot({ ccd = { 'homeA' }, roster = { 'bot1' }, table = { 'homeA', 'bot1', 'bot2' } })
    t.eq(snap.stale.bot2, true); t.eq(snap.stale.bot1, nil)
    local ok, problems = integrity.check(snap,
      { ccd = { 'homeA' }, roster = { 'bot1' }, table = { 'homeA', 'bot1', 'bot2' } }, NONE)
    t.eq(ok, true, table.concat(problems, '; '))
    -- a record minted after the snapshot that vanished is still unknown
    ok, problems = integrity.check(snap,
      { ccd = { 'homeA' }, roster = { 'bot1' }, table = { 'homeA', 'bot1', 'bot2', 'hire9' } }, NONE)
    t.eq(ok, false); t.eq(problems[1], 'unknown hire9'); t.eq(#problems, 1)
    -- a snapshot member that vanishes is still missing, stale set or not
    ok, problems = integrity.check(snap, { ccd = { 'homeA' }, roster = {}, table = { 'homeA', 'bot1', 'bot2' } }, NONE)
    t.eq(ok, false); t.eq(table.concat(problems, ','), 'missing bot1,unknown bot1')
  end,
  ['missing without a legit reason is flagged'] = function(t)
    local ok, problems = integrity.check(start(),
      { ccd = { 'homeA', 'homeB' }, roster = { 'bot1' } }, NONE)
    t.eq(ok, false); t.eq(problems[1], 'missing bot2'); t.eq(#problems, 1)
  end,
  ['adopted home: move and roster+CCD overlap are legit'] = function(t)
    -- Permadeath takeover: bot1 becomes a CCD (vanilla keeps it in the roster until SavePlayers)
    local legit = { permadead = { homeA = true }, fired = {}, adopted = { bot1 = true } }
    local ok, problems = integrity.check(start(),
      { ccd = { 'bot1', 'homeB' }, roster = { 'bot1', 'bot2' } }, legit)
    t.eq(ok, true, table.concat(problems, '; '))
    ok, problems = integrity.check(start(), { ccd = { 'bot1', 'homeB' }, roster = { 'bot2' } }, legit)
    t.eq(ok, true, table.concat(problems, '; '))
    -- still a duplicate when it appears a third time
    ok, problems = integrity.check(start(), { ccd = { 'bot1', 'bot1', 'homeB' }, roster = { 'bot2' } }, legit)
    t.eq(ok, false); t.eq(problems[1], 'duplicate bot1')
  end,
  ['no snapshot: only duplicates and unknowns count'] = function(t)
    local ok, problems = integrity.check(nil, { ccd = { 'homeA' }, roster = { 'bot1' } }, NONE)
    t.eq(ok, true, table.concat(problems, '; '))
    ok, problems = integrity.check(nil, { ccd = { 'homeA' }, roster = { 'homeA' } }, NONE)
    t.eq(ok, false); t.eq(problems[1], 'duplicate homeA')
  end,
  ['problems are sorted and the snapshot is a copy'] = function(t)
    local ccd = { 'homeA', 'homeB' }
    local snap = integrity.snapshot({ ccd = ccd, roster = { 'bot1', 'bot2' } })
    ccd[1] = 'changed'
    local ok, problems = integrity.check(snap, { ccd = {}, roster = {} }, NONE)
    t.eq(ok, false)
    t.eq(table.concat(problems, ','), 'missing bot1,missing bot2,missing homeA,missing homeB')
  end,
}

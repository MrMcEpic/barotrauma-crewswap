local mirror = require('crewswap.core.mirror')

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function L(sessionId, on, h, job) return { sessionId = sessionId, on = on, h = h, job = job } end

return {
  ['row codec: id/on/h/job plus the record attributes round-trip'] = function(t)
    local attrs = mirror.rowAttrs({ sid = 'aa', on = 'Ann', h = '-12', job = 'medic',
                                    rec = { wbal = 300, wrd = 20, owner = 'STEAM_A', lastAt = 5 } })
    t.eq(attrs.id, 'aa'); t.eq(attrs.on, 'Ann'); t.eq(attrs.h, '-12'); t.eq(attrs.job, 'medic')
    t.eq(attrs.crewswap_wbal, '300'); t.eq(attrs.crewswap_owner, 'STEAM_A')
    local get = function(name) return attrs[name] or '' end
    local sid, e = mirror.parseRow(get)
    t.eq(sid, 'aa'); t.eq(e.on, 'Ann'); t.eq(e.h, '-12'); t.eq(e.job, 'medic')
    t.eq(e.rec.wbal, 300); t.eq(e.rec.wrd, 20); t.eq(e.rec.owner, 'STEAM_A'); t.eq(e.rec.lastAt, 5)
    t.eq(e.rec.last, nil)
  end,
  ['row codec: an old row without record attributes has an empty record; no id is skipped'] = function(t)
    local old = { id = 'bb', on = 'Bob', h = '1', job = 'x' }
    local sid, e = mirror.parseRow(function(n) return old[n] or '' end)
    t.eq(sid, 'bb'); t.eq(next(e.rec), nil)
    t.eq(mirror.parseRow(function() return '' end), nil)
  end,
  ['exact hash wins over name'] = function(t)
    local entries = { s1 = { on = 'Ann', h = '11', job = 'mechanic' },
                      s2 = { on = 'Bob', h = '22', job = 'medic' } }
    -- live 5 carries Ann's name but Bob's exact hash: the hash decides
    local m = mirror.match(entries, { L(5, 'Ann', '22', 'medic') })
    t.eq(m[5], 's2')
  end,
  ['name fallback when job changed'] = function(t)
    local entries = { s1 = { on = 'Ann', h = '11', job = 'mechanic' } }
    local m = mirror.match(entries, { L(5, 'Ann', '99', 'engineer') })
    t.eq(m[5], 's1')
  end,
  ['ambiguous name gives no match'] = function(t)
    local entries = { s1 = { on = 'Ann', h = '11', job = 'mechanic' },
                      s2 = { on = 'Ann', h = '12', job = 'medic' } }
    local m = mirror.match(entries, { L(5, 'Ann', '99', 'engineer') })
    t.eq(m[5], nil, 'two entries named Ann')
    local m2 = mirror.match({ s1 = { on = 'Ann', h = '11', job = 'x' } },
      { L(5, 'Ann', '98', 'y'), L(6, 'Ann', '97', 'z') })
    t.eq(count(m2), 0, 'two live infos named Ann')
  end,
  ['ambiguous hash gives no match'] = function(t)
    local m = mirror.match({ s1 = { on = 'Ann', h = '11', job = 'x' } },
      { L(5, 'Ann', '11', 'x'), L(6, 'Ann', '11', 'x') })
    t.eq(count(m), 0)
  end,
  ['each sid claimed once'] = function(t)
    local entries = { s1 = { on = 'Ann', h = '11', job = 'mechanic' } }
    -- live 5 takes s1 by hash; live 6 would match s1 by name but s1 is already claimed
    local m = mirror.match(entries, { L(5, 'Ann', '11', 'mechanic'), L(6, 'Ann', '77', 'medic') })
    t.eq(m[5], 's1'); t.eq(m[6], nil)
    -- and the reverse listing order gives the same answer
    local m2 = mirror.match(entries, { L(6, 'Ann', '77', 'medic'), L(5, 'Ann', '11', 'mechanic') })
    t.eq(m2[5], 's1'); t.eq(m2[6], nil)
  end,
  ['empty inputs'] = function(t)
    t.eq(count(mirror.match({}, { L(1, 'A', '1', 'j') })), 0)
    t.eq(count(mirror.match({ s1 = { on = 'A', h = '1', job = 'j' } }, {})), 0)
  end,
  ['mirror re-match after reload keeps ids'] = function(t)
    local entries = { ['aaaa'] = { on = 'Ann', h = '-1001', job = 'mechanic' },
                      ['bbbb'] = { on = 'Bob', h = '2002', job = 'medic' },
                      ['cccc'] = { on = 'Cat', h = '3003', job = 'captain' } }
    -- after a Lua reload the same infos come back with fresh session ids
    local m = mirror.match(entries, { L(40, 'Cat', '3003', 'captain'), L(41, 'Ann', '-1001', 'mechanic'),
      L(42, 'Bob', '2002', 'medic') })
    t.eq(m[41], 'aaaa'); t.eq(m[42], 'bbbb'); t.eq(m[40], 'cccc')
    t.eq(count(m), 3)
  end,
}

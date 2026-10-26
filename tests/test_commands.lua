local C = require('crewswap.core.commands')

return {
  ['non-command returns nil'] = function(t)
    t.eq(C.parse('hello there'), nil)
    t.eq(C.parse('!crewswapper'), nil)
    t.eq(C.parse(''), nil)
    t.eq(C.parse(nil), nil)
  end,
  ['status'] = function(t)
    t.eq(C.parse('!crewswap status').op, 'status')
    t.eq(C.parse('  !crewswap  ').op, 'status', 'bare command is status')
  end,
  ['pool own'] = function(t)
    local c = C.parse('!crewswap pool own')
    t.eq(c.op, 'pool'); t.eq(c.value, 'own')
    t.eq(C.parse('!crewswap pool shared').value, 'shared')
  end,
  ['protect off'] = function(t)
    local c = C.parse('!crewswap protect off')
    t.eq(c.op, 'protect'); t.eq(c.value, false)
    t.eq(C.parse('!crewswap protect on').value, true)
  end,
  ['check'] = function(t) t.eq(C.parse('!crewswap check').op, 'check') end,
  ['owner with quoted names'] = function(t)
    local c = C.parse('!crewswap owner "Kim Lee" "Zoë Park"')
    t.eq(c.op, 'owner'); t.eq(c.character, 'Kim Lee'); t.eq(c.player, 'Zoë Park')
    local d = C.parse('!crewswap owner Bob Alice')
    t.eq(d.character, 'Bob'); t.eq(d.player, 'Alice')
  end,
  ['bad pool value gives usage'] = function(t)
    local c = C.parse('!crewswap pool everyone')
    t.eq(c.op, 'error'); t.ok(c.text:find('!crewswap pool', 1, true), 'usage names the command')
    t.eq(C.parse('!crewswap protect maybe').op, 'error')
    t.eq(C.parse('!crewswap owner "only one"').op, 'error')
    t.eq(C.parse('!crewswap owner "unterminated Bob').op, 'error')
    t.eq(C.parse('!crewswap frobnicate').op, 'error')
  end,
  ['config round trip'] = function(t)
    local s = C.configEncode({ pool = 'own', protect = false })
    t.eq(s, 'pool=own\nprotect=off\n')
    local d = C.configDecode(s)
    t.eq(d.pool, 'own'); t.eq(d.protect, false)
    t.eq(C.configEncode({ pool = 'shared', protect = true }), 'pool=shared\nprotect=on\n')
  end,
  ['config defaults on garbage'] = function(t)
    for _, s in ipairs({ '', 'garbage\n\x00\xff', 'pool=banana\nprotect=perhaps\n', 'pool\n=\n' }) do
      local d = C.configDecode(s)
      t.eq(d.pool, 'shared'); t.eq(d.protect, true)
    end
    t.eq(C.configDecode(nil).pool, 'shared')
    local half = C.configDecode('protect=off\r\n')
    t.eq(half.protect, false); t.eq(half.pool, 'shared')
  end,
  ['status text mentions both toggles'] = function(t)
    local s = C.statusText({ pool = 'own', protect = false }, { active = true })
    t.ok(s:find('own', 1, true), 'pool'); t.ok(s:find('off', 1, true), 'protect')
    t.ok(s:find('^%[CrewSwap%]'), 'prefix')
    local d = C.statusText({ pool = 'shared', protect = true }, { active = false })
    t.ok(d:find('shared', 1, true) and d:find('on', 1, true))
    t.ok(not s:find('color'), 'no US spelling')
  end,
  ['statusText says the mod switched itself off, and why'] = function(t)
    local s = C.statusText({ pool = 'shared', protect = true }, { active = false, failReason = 'patch x failed' })
    t.ok(s:find('^%[CrewSwap%] CrewSwap is off'), s)
    t.ok(s:find('patch x failed', 1, true), s)
    t.ok(s:find('restart', 1, true), s)
    t.ok(not s:find('inactive right now', 1, true), s)
  end,
  ['findByName exact, case-insensitive, ambiguity'] = function(t)
    local list = { { name = 'Kim Lee' }, { name = 'Kim Leeson' }, { name = 'Bob' }, { name = 'bobby' } }
    t.eq(C.findByName(list, 'kim lee').name, 'Kim Lee')
    t.eq(C.findByName(list, 'Bob').name, 'Bob')
    local r, why = C.findByName(list, 'zzz'); t.eq(r, nil); t.eq(why, 'none')
    local r2, why2 = C.findByName({ { name = 'A' }, { name = 'a' } }, 'a'); t.eq(r2, nil); t.eq(why2, 'ambiguous')
    t.eq(C.findByName(list, 'Kim Leeso').name, 'Kim Leeson', 'unique prefix')
  end,
}

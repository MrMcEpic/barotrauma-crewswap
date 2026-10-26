local placement = require('crewswap.core.placement')
local F = require('fakes')

local OFF = { pool = 'shared', protect = false }
local ON = { pool = 'shared', protect = true }

local function views()
  return {
    F.view{ id = 10, sid = 'sA', homeOf = 'acct:A', controller = 'acct:A' },
    F.view{ id = 20, sid = 'sB', homeOf = 'acct:B', controller = 'acct:B' },
    F.view{ id = 30, sid = 'sBot' },
  }
end

return {
  ['protect on keeps everyone home'] = function(t)
    local moves = placement.roundStart({
      { key = 'acct:A', homeId = 10, last = 'sBot' }, { key = 'acct:B', homeId = 20, last = 'sBot' } }, views(), ON)
    t.eq(#moves, 0)
  end,
  ['protect off moves to last played if free'] = function(t)
    local moves = placement.roundStart({ { key = 'acct:A', homeId = 10, last = 'sBot' } }, views(), OFF)
    t.eq(#moves, 1); t.eq(moves[1].key, 'acct:A'); t.eq(moves[1].targetId, 30)
  end,
  ['protect off stays home when last played is taken'] = function(t)
    local moves = placement.roundStart({ { key = 'acct:A', homeId = 10, last = 'sB' } }, views(), OFF)
    t.eq(#moves, 0)
  end,
  ['two players with same last: first wins'] = function(t)
    local moves = placement.roundStart({
      { key = 'acct:A', homeId = 10, last = 'sBot' }, { key = 'acct:B', homeId = 20, last = 'sBot' } }, views(), OFF)
    t.eq(#moves, 1); t.eq(moves[1].key, 'acct:A')
  end,
  ['reconnect places player in last played if free'] = function(t)
    local vs = views()
    vs[1].controller = nil   -- A's old body is idle again
    t.eq(placement.rejoin({ key = 'acct:B', homeId = 20, last = 'sA' }, vs, OFF), 10)
  end,
  ['rejoin with no last stays home'] = function(t)
    t.eq(placement.rejoin({ key = 'acct:B', homeId = 20 }, views(), OFF), nil)
  end,
  ['rejoin protect on stays home'] = function(t)
    local vs = views(); vs[3].homeOf = 'acct:A'
    t.eq(placement.rejoin({ key = 'acct:B', homeId = 20, last = 'sBot' }, vs, ON), nil)
  end,
  ['no move when last played is already the home body'] = function(t)
    local vs = views(); vs[2].controller = nil
    t.eq(placement.rejoin({ key = 'acct:B', homeId = 20, last = 'sB' }, vs, OFF), nil)
  end,
  ['rejoinTarget falls back to a Free home body'] = function(t)
    local vs = views(); vs[2].controller = nil; vs[2].isAI = true
    t.eq(placement.rejoinTarget({ key = 'acct:B', homeId = 20, last = 'sB' }, vs, OFF), 20)
    t.eq(placement.rejoinTarget({ key = 'acct:B', homeId = 20 }, vs, OFF), 20)
    t.eq(placement.rejoinTarget({ key = 'acct:B', homeId = 20, last = 'sBot' }, vs, ON), 20)
  end,
  ['rejoinTarget leaves a taken home alone'] = function(t)
    local vs = views(); vs[2].controller = 'acct:A'
    t.eq(placement.rejoinTarget({ key = 'acct:B', homeId = 20 }, vs, OFF), nil)
  end,
  ['lastPlayed picks greatest lastAt'] = function(t)
    local chars = { s1 = { last = 'acct:A', lastAt = 5 }, s2 = { last = 'acct:A', lastAt = 9 },
                    s3 = { last = 'acct:B', lastAt = 99 }, s4 = { last = 'acct:A' } }
    t.eq(placement.lastPlayed(chars, 'acct:A'), 's2')
    t.eq(placement.lastPlayed(chars, 'acct:Z'), nil)
  end,
}

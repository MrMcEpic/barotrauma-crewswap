-- core/grace.lua
local grace = require('crewswap.core.grace')

return {
  ['not down: no mask'] = function(t)
    local g = grace.new()
    local m, a = g:step(1, false, true)
    t.eq(m, false); t.eq(a, nil)
    m, a = g:step(1, false, false)
    t.eq(m, false); t.eq(a, nil)
  end,
  ['down with free crew masks'] = function(t)
    local g = grace.new()
    t.eq((g:step(0.016, true, true)), true)
    t.eq((g:step(50, true, true)), true)
  end,
  ['down without free crew: no mask'] = function(t)
    local g = grace.new()
    local m, a = g:step(1, true, false)
    t.eq(m, false); t.eq(a, nil)
  end,
  ['mask drops at 120 s'] = function(t)
    local g = grace.new()
    t.eq((g:step(119.9, true, true)), true)
    t.eq((g:step(0.2, true, true)), false)
    t.eq((g:step(5, true, true)), false)
  end,
  ['elapsed resets when someone gets up'] = function(t)
    local g = grace.new()
    g:step(100, true, true)
    g:step(1, false, true)
    t.eq(g.elapsed, 0)
    t.eq((g:step(100, true, true)), true)   -- a fresh 120 s window
    local _, a = g:step(1, true, true)
    t.eq(a, nil)   -- 101 s: no repeat of the start line; the 90 s warning was this episode's
  end,
  ['three announcements once each'] = function(t)
    local g = grace.new()
    local seen = {}
    for _ = 1, 400 do
      local _, a = g:step(0.5, true, true)
      if a then seen[#seen + 1] = a end
    end
    t.eq(#seen, 3)
    t.eq(seen[1], grace.MSG_START); t.eq(seen[2], grace.MSG_WARN); t.eq(seen[3], grace.MSG_END)
    -- a new down-episode announces again
    g:step(1, false, true)
    local _, a = g:step(0.1, true, true)
    t.eq(a, grace.MSG_START)
  end,
}

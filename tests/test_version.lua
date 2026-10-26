local v = require('crewswap.core.version')
local E = { game='1.13.4', luacs='85ded59' }
local WARN_OTHER = '[CrewSwap] WARNING: built for LuaCs 85ded59, running on 1234567; continuing (patch audit and self-tests still guard)'
local WARN_UNKNOWN = '[CrewSwap] WARNING: built for LuaCs 85ded59, running on unknown; continuing (patch audit and self-tests still guard)'
return {
 ['exact versions pass without a warning'] = function(t)
   local ok, why, warn = v.compare({game='1.13.4.0', luacs='85ded59'}, E); t.eq(ok, true); t.eq(why, nil); t.eq(warn, nil) end,
 ['revision suffix ignored'] = function(t)
   local ok, _, warn = v.compare({game='1.13.4.2', luacs='85ded59abc'}, E); t.eq(ok, true); t.eq(warn, nil) end,
 ['newer game fails with reason'] = function(t)
   local ok, why = v.compare({game='1.13.5.0', luacs='85ded59'}, E); t.eq(ok, false); t.eq(why, 'game 1.13.5.0') end,
 ['other luacs passes with a warning'] = function(t)
   local ok, why, warn = v.compare({game='1.13.4.0', luacs='1234567'}, E); t.eq(ok, true); t.eq(why, nil); t.eq(warn, WARN_OTHER) end,
 ['missing luacs passes with an unknown warning'] = function(t)
   local ok, _, warn = v.compare({game='1.13.4.0', luacs=''}, E); t.eq(ok, true); t.eq(warn, WARN_UNKNOWN) end,
 ['dotted boundary: 1.13.40 fails'] = function(t)
   local ok, why = v.compare({game='1.13.40.0', luacs='85ded59'}, E); t.eq(ok, false); t.eq(why, 'game 1.13.40.0') end,
 ['bare expected version passes'] = function(t) t.ok(v.compare({game='1.13.4', luacs='85ded59'}, E)) end,
 ['short luacs passes with a warning'] = function(t)
   local ok, _, warn = v.compare({game='1.13.4.0', luacs='85ded5'}, E); t.eq(ok, true)
   t.ok(warn and warn:find('running on 85ded5;', 1, true), warn) end,
 ['non-string fields'] = function(t)
   t.eq((v.compare({game=nil, luacs='85ded59'}, E)), false)
   local ok, _, warn = v.compare({game='1.13.4.0', luacs=nil}, E); t.eq(ok, true); t.eq(warn, WARN_UNKNOWN) end,
 ['game mismatch wins over a luacs mismatch (no warning)'] = function(t)
   local ok, why, warn = v.compare({game='1.14.0.0', luacs='1234567'}, E); t.eq(ok, false); t.eq(why, 'game 1.14.0.0'); t.eq(warn, nil) end,
}

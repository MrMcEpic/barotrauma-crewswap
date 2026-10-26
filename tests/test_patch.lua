-- server/patch.lua against a fake Hook global; output captured from print.
local function fresh(hookPatch)
  package.loaded['crewswap.server.patch'] = nil
  _G.Hook = { Patch = hookPatch, HookMethodType = { Before = 'B', After = 'A' } }
  local lines = {}
  _G.CS = { failed = {}, fail = function(r) table.insert(_G.CS.failed, r) end }
  local P = require('crewswap.server.patch')
  local realPrint = print
  return P, lines, function(fn) print = function(s) lines[#lines + 1] = s end; local ok, e = pcall(fn); print = realPrint; assert(ok, e) end
end

return {
 ['patch with types passes them and counts ok'] = function(t)
   local got
   local P, _, quiet = fresh(function(...) got = { ... } end)
   local fn = function() end
   quiet(function() t.eq(P.patch('id1', 'C', 'M', { 'System.Int32' }, fn, 'A'), true) end)
   t.eq(#got, 6); t.eq(got[1], 'id1'); t.eq(got[4][1], 'System.Int32'); t.eq(got[5], fn); t.eq(got[6], 'A')
   t.eq(P.ok, 1); t.eq(P.failed, 0)
 end,
 ['patch without types omits the type list'] = function(t)
   local got
   local P, _, quiet = fresh(function(...) got = { ... } end)
   local fn = function() end
   quiet(function() P.patch('id2', 'C', 'M', nil, fn, 'B') end)
   t.eq(#got, 5); t.eq(got[4], fn); t.eq(got[5], 'B')
 end,
 ['when defaults to Before'] = function(t)
   local got
   local P, _, quiet = fresh(function(...) got = { ... } end)
   quiet(function() P.patch('id3', 'C', 'M', nil, function() end) end)
   t.eq(got[5], 'B')
 end,
 ['failure is counted, recorded and fails the mod'] = function(t)
   local P, _, quiet = fresh(function() error('ambiguous method signature') end)
   quiet(function() t.eq(P.patch('bad', 'C', 'M', nil, function() end, 'B'), false) end)
   t.eq(P.failed, 1); t.eq(P.ok, 0)
   t.ok(tostring(P.errors['bad']):find('ambiguous', 1, true))
   t.eq(#CS.failed, 1); t.ok(CS.failed[1]:find('bad', 1, true))
 end,
 ['summary prints ok/total'] = function(t)
   local n = 0
   local P, lines, quiet = fresh(function() n = n + 1; if n == 2 then error('x') end end)
   quiet(function()
     P.patch('a', 'C', 'M', nil, function() end); P.patch('b', 'C', 'M', nil, function() end)
     P.patch('c', 'C', 'M', nil, function() end); P.summary()
   end)
   t.eq(lines[#lines], '[CrewSwap] patches installed: 2/3')
 end,
 ['summary with no patches is 0/0'] = function(t)
   local P, lines, quiet = fresh(function() end)
   quiet(function() P.summary() end)
   t.eq(lines[#lines], '[CrewSwap] patches installed: 0/0')
 end,
}

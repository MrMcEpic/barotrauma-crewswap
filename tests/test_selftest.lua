-- server/selftest.lua runner semantics (the built-in checks need the game and are not run here).
local function fresh()
  package.loaded['crewswap.server.selftest'] = nil
  local S = require('crewswap.server.selftest')
  S.checks, S.order = {}, {}   -- drop the built-in game checks
  return S
end
local function capture(fn)
  local lines, realPrint = {}, print
  print = function(s) lines[#lines + 1] = s end
  local ok, e = pcall(fn); print = realPrint; assert(ok, e)
  return lines
end

return {
 ['pass, fail, error and skip lines in registration order'] = function(t)
   local S = fresh()
   S.add('one', function() return true end)
   S.add('two', function() return false, 'not a number' end)
   S.add('three', function() error('boom', 0) end)
   S.add('four', function() return 'skip', 'not implemented yet' end)
   local lines = capture(S.run)
   t.eq(lines[1], '[CrewSwap] SELFTEST PASS one')
   t.eq(lines[2], '[CrewSwap] SELFTEST FAIL two: not a number')
   t.eq(lines[3], '[CrewSwap] SELFTEST FAIL three: boom')
   t.eq(lines[4], '[CrewSwap] SELFTEST SKIP four: not implemented yet')
   t.eq(lines[5], '[CrewSwap] SELFTEST done: 1 passed, 2 failed, 1 skipped')
 end,
 ['re-adding a name replaces the check in place'] = function(t)
   local S = fresh()
   S.add('a', function() return 'skip', 'placeholder' end)
   S.add('b', function() return true end)
   S.add('a', function() return true end)
   local lines = capture(S.run)
   t.eq(lines[1], '[CrewSwap] SELFTEST PASS a'); t.eq(lines[2], '[CrewSwap] SELFTEST PASS b'); t.eq(#lines, 3)
 end,
 ['run returns the failure count'] = function(t)
   local S = fresh()
   S.add('x', function() return nil end)
   local n; capture(function() n = S.run() end); t.eq(n, 1)
 end,
 ['built-in checks are registered'] = function(t)
   package.loaded['crewswap.server.selftest'] = nil
   local S = require('crewswap.server.selftest')
   t.eq(S.order[1], 'timing'); t.eq(S.order[2], 'enum-numbers'); t.eq(S.order[3], 'list-convert')
 end,
}

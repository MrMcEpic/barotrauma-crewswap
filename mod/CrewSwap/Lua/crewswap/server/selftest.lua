-- In-game self-test. Runs only when <SaveFolder>/CrewSwap/selftest exists (see server/main.lua).
-- A check returns true (PASS), 'skip', why (SKIP), or anything else / raises (FAIL).
local M = { checks = {}, order = {} }

function M.add(name, fn)
  if not M.checks[name] then M.order[#M.order + 1] = name end
  M.checks[name] = fn
end

function M.run()
  local passed, failed, skipped = 0, 0, 0
  for _, name in ipairs(M.order) do
    local ok, res, why = pcall(M.checks[name])
    if not ok then
      failed = failed + 1
      print('[CrewSwap] SELFTEST FAIL ' .. name .. ': ' .. tostring(res))
    elseif res == true then
      passed = passed + 1
      print('[CrewSwap] SELFTEST PASS ' .. name)
    elseif res == 'skip' then
      skipped = skipped + 1
      print('[CrewSwap] SELFTEST SKIP ' .. name .. ': ' .. tostring(why))
    else
      failed = failed + 1
      print('[CrewSwap] SELFTEST FAIL ' .. name .. ': ' .. tostring(why or 'returned ' .. tostring(res)))
    end
  end
  print('[CrewSwap] SELFTEST done: ' .. passed .. ' passed, ' .. failed .. ' failed, ' .. skipped .. ' skipped')
  return failed
end

M.add('timing', function()
  local t = LuaUserData.CreateStatic('Barotrauma.Timing').TotalTime
  if type(t) ~= 'number' then return false, 'Timing.TotalTime is ' .. type(t) end
  return true
end)

M.add('enum-numbers', function()
  local v = CauseOfDeathType.Disconnected
  if type(v) ~= 'number' then return false, 'CauseOfDeathType.Disconnected is ' .. type(v) end
  return true
end)

M.add('list-convert', function() return 'skip', 'not implemented yet' end)

return M

-- P.patch(): every Hook.Patch goes through here. A patch that does not resolve means the
-- game/LuaCs is not what this build was made for, so the mod fails closed (CS.fail).
local P = { ok = 0, failed = 0, errors = {} }

function P.patch(id, class, method, types, fn, when)
  when = when or Hook.HookMethodType.Before
  local ok, err = pcall(function()
    if types then Hook.Patch(id, class, method, types, fn, when)
    else Hook.Patch(id, class, method, fn, when) end
  end)
  if ok then
    P.ok = P.ok + 1
    return true
  end
  P.failed = P.failed + 1
  P.errors[id] = tostring(err)
  CS.fail('patch ' .. id .. ' (' .. class .. '.' .. method .. '): ' .. tostring(err))
  return false
end

function P.summary()
  print('[CrewSwap] patches installed: ' .. P.ok .. '/' .. (P.ok + P.failed))
end

return P

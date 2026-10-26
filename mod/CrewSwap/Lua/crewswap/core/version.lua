-- Pure: compare the running game / LuaCs versions with the ones this build was made for.
local M = {}

-- '1.13.4' matches '1.13.4' and '1.13.4.<anything>', but not '1.13.40'.
local function gameMatches(found, want)
  if type(found) ~= 'string' or found:sub(1, #want) ~= want then return false end
  local nextChar = found:sub(#want + 1, #want + 1)
  return nextChar == '' or nextChar == '.'
end

-- LuaCs commits are compared on their first 7 characters (git short hash).
local function luacsMatches(found, want)
  return type(found) == 'string' and #found >= 7 and found:sub(1, 7) == want:sub(1, 7)
end

-- found / expect = { game = string, luacs = string }. Returns ok, reason, warning.
-- Only a game mismatch fails (ok = false, reason set). A different or unreadable LuaCs commit
-- passes with a console warning: the patch-install audit and the self-tests still guard it.
function M.compare(found, expect)
  if not gameMatches(found.game, expect.game) then
    return false, 'game ' .. tostring(found.game), nil
  end
  if not luacsMatches(found.luacs, expect.luacs) then
    local rev = found.luacs
    if type(rev) ~= 'string' or rev == '' then rev = 'unknown' end
    return true, nil, '[CrewSwap] WARNING: built for LuaCs ' .. expect.luacs .. ', running on ' .. rev
      .. '; continuing (patch audit and self-tests still guard)'
  end
  return true, nil, nil
end

return M

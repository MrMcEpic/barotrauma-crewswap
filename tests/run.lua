-- Run from the repo root: lua5.2 tests/run.lua
package.path = 'mod/CrewSwap/Lua/?.lua;tests/?.lua;' .. package.path

local T = {}
local function fmt(v) return tostring(v) end
function T.eq(a, b, msg)
  if a ~= b then error((msg and (msg .. ': ') or '') .. 'expected ' .. fmt(b) .. ', got ' .. fmt(a), 2) end
end
function T.ok(v, msg)
  if not v then error(msg or 'expected truthy value', 2) end
end
function T.err(fn, msg)
  if pcall(fn) then error(msg or 'expected an error', 2) end
end

local files = {}
local p = io.popen('ls tests/test_*.lua')
for line in p:lines() do files[#files + 1] = line end
p:close()
table.sort(files)

local passed, failed = 0, 0
for _, f in ipairs(files) do
  local ok, cases = pcall(dofile, f)
  if not ok or type(cases) ~= 'table' then
    failed = failed + 1
    print('FAIL ' .. f .. ': ' .. tostring(cases))
  else
    local names = {}
    for name in pairs(cases) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local ok2, err = pcall(cases[name], T)
      if ok2 then passed = passed + 1; print('PASS ' .. name)
      else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
    end
  end
end
print(passed .. ' passed, ' .. failed .. ' failed')
os.exit(failed == 0 and 0 or 1)

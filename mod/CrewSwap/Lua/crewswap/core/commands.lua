-- Pure: the !crewswap admin chat command parser, the config file format and status text.
local M = {}

M.PREFIX = '!crewswap'
M.DEFAULTS = { pool = 'shared', protect = true }

local USAGE = {
  pool = 'Usage: !crewswap pool shared|own',
  protect = 'Usage: !crewswap protect on|off',
  owner = 'Usage: !crewswap owner "<character>" "<player>"',
  general = 'Usage: !crewswap status | pool shared|own | protect on|off | owner "<character>" "<player>" | check',
}

local function err(kind) return { op = 'error', text = '[CrewSwap] ' .. USAGE[kind] } end

-- Split on whitespace; "double quoted" parts keep their spaces. nil when a quote never closes.
local function tokens(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match('%s') then
      i = i + 1
    elseif c == '"' then
      local close = s:find('"', i + 1, true)
      if not close then return nil end
      out[#out + 1] = s:sub(i + 1, close - 1)
      i = close + 1
    else
      local j = s:find('[%s"]', i) or n + 1
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return out
end

function M.parse(text)
  if type(text) ~= 'string' then return nil end
  local s = text:match('^%s*(.-)%s*$')
  if s:sub(1, #M.PREFIX):lower() ~= M.PREFIX then return nil end
  local rest = s:sub(#M.PREFIX + 1)
  if rest ~= '' and not rest:match('^%s') then return nil end   -- !crewswapper is not ours
  local tk = tokens(rest)
  if tk == nil then return err('general') end
  local op = (tk[1] or 'status'):lower()
  if op == 'status' and #tk <= 1 then return { op = 'status' } end
  if op == 'check' and #tk == 1 then return { op = 'check' } end
  if op == 'pool' then
    local v = tk[2] and tk[2]:lower()
    if #tk == 2 and (v == 'shared' or v == 'own') then return { op = 'pool', value = v } end
    return err('pool')
  end
  if op == 'protect' then
    local v = tk[2] and tk[2]:lower()
    if #tk == 2 and (v == 'on' or v == 'off') then return { op = 'protect', value = v == 'on' } end
    return err('protect')
  end
  if op == 'owner' then
    if #tk == 3 then return { op = 'owner', character = tk[2], player = tk[3] } end
    return err('owner')
  end
  return err('general')
end

local function onoff(b) return b and 'on' or 'off' end

function M.configEncode(t)
  local pool = (t and t.pool == 'own') and 'own' or 'shared'
  local protect = not (t and t.protect == false)
  return 'pool=' .. pool .. '\nprotect=' .. onoff(protect) .. '\n'
end

function M.configDecode(s)
  local t = { pool = M.DEFAULTS.pool, protect = M.DEFAULTS.protect }
  if type(s) ~= 'string' then return t end
  for line in s:gmatch('[^\r\n]+') do
    local k, v = line:match('^%s*(%a+)%s*=%s*(%a+)%s*$')
    if k == 'pool' and (v == 'shared' or v == 'own') then t.pool = v end
    if k == 'protect' and (v == 'on' or v == 'off') then t.protect = v == 'on' end
  end
  return t
end

M.FAIL_NOTICE = '[CrewSwap] CrewSwap is off until an admin restarts the server (see the server console).'

-- info (optional): { active = bool, failReason = string (the mod switched itself off) }
function M.statusText(t, info)
  if info and info.failReason then
    return '[CrewSwap] CrewSwap is off: ' .. tostring(info.failReason)
      .. '. Fix it and restart the server; !crewswap check cannot turn it back on.'
  end
  local state = (info and info.active == false) and 'inactive right now' or 'active'
  return string.format('[CrewSwap] CrewSwap is %s. Crew pool: %s. Home protection: %s.',
    state, t.pool, onoff(t.protect))
end

-- Case-insensitive name lookup: exact match first, then a unique prefix.
-- → item | nil, 'none' | 'ambiguous'
function M.findByName(list, name)
  local want = tostring(name):lower()
  local function pick(match)
    local hit, n = nil, 0
    for _, it in ipairs(list) do
      if match(tostring(it.name):lower()) then hit, n = it, n + 1 end
    end
    if n == 1 then return hit end
    if n > 1 then return nil, 'ambiguous' end
  end
  local r, why = pick(function(nm) return nm == want end)
  if r or why then return r, why end
  r, why = pick(function(nm) return nm:sub(1, #want) == want end)
  if r or why then return r, why end
  return nil, 'none'
end

return M

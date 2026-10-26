-- server/admin.lua against fake game globals (chat command handling, config file, hire ownership).
local registry = require('crewswap.core.registry')
local commands = require('crewswap.core.commands')

local W

local function client(name, acct, admin)
  return { Name = name, AccountId = { StringRepresentation = acct }, admin = admin,
           HasPermission = function(self) return self.admin == true end }
end

local function world(opts)
  opts = opts or {}
  for _, m in ipairs({ 'game', 'switch', 'patch', 'selftest', 'admin' }) do
    package.loaded['crewswap.server.' .. m] = nil
  end
  W = { hooks = {}, patches = {}, told = {}, announced = {}, files = {}, broadcasts = 0, views = {}, clients = {} }
  if opts.config then W.files['/save/CrewSwap/config.txt'] = opts.config end
  _G.SERVER = true
  _G.ClientPermissions = { ManageSettings = 8 }
  _G.Hook = { Add = function(ev, id, fn) W.hooks[ev .. '/' .. id] = fn end,
              Patch = function(id, cls, m, fn, when) W.patches[id] = { fn = fn, when = when } end,
              HookMethodType = { Before = 'B', After = 'A' } }
  _G.LuaUserData = { RegisterType = function() end, CreateStatic = function() return { CreateDirectory = function() end } end }
  _G.File = {
    Exists = function(p) return W.files[p] ~= nil end,
    Read = function(p) return W.files[p] end,
    Write = function(p, s) if W.failWrite then error('disk full') end W.files[p] = s end,
    Move = function(a, b) W.files[b] = W.files[a]; W.files[a] = nil end,
  }
  _G.Game = { SaveFolder = '/save' }
  _G.CS = { active = true, reg = registry.new(), fail = function() end, recomputeActive = function() CS.active = true; return true end }
  function CS.sidOfInfo(info)
    local sid = CS.reg:sidOf(info.ID)
    if sid == nil then sid = 'sid' .. info.ID; CS.reg:bind(info.ID, sid); CS.reg:record(sid) end
    return sid
  end
  local G = {
    toggles = function() return CS.config.toggles end,
    isAdmin = function(c) return c:HasPermission(8) end,
    tell = function(c, text) W.told[#W.told + 1] = { c = c, text = text } end,
    announce = function(text) W.announced[#W.announced + 1] = text end,
    crewViews = function() return W.views end,
    clients = function() return W.clients end,
    accountKey = function(c) return c.AccountId.StringRepresentation end,
  }
  package.loaded['crewswap.server.game'] = G
  package.loaded['crewswap.server.switch'] = { broadcastState = function() W.broadcasts = W.broadcasts + 1 end }
  package.loaded['crewswap.server.patch'] = { patch = function(id, cls, m, types, fn, when) W.patches[id] = { fn = fn, when = when, cls = cls, m = m } return true end }
  package.loaded['crewswap.server.selftest'] = { add = function() end }
  local realPrint = print; print = function() end
  local ok, A = pcall(require, 'crewswap.server.admin')
  print = realPrint
  assert(ok, A)
  return A
end

local function chat(text, c) return W.hooks['chatMessage/crewswap.cmd'](text, c) end

return {
  ['non-command chat is left alone'] = function(t)
    world()
    t.eq(chat('hello', client('A', 'a', true)), nil)
    t.eq(#W.told, 0)
  end,
  ['command text is swallowed for admin and non-admin'] = function(t)
    world()
    t.eq(chat('!crewswap protect off', client('A', 'a', true)), true)
    t.eq(chat('!crewswap protect on', client('B', 'b', false)), true)
    t.eq(chat('!crewswap garbage', client('B', 'b', false)), true)
  end,
  ['non-admin gets the admin-only message and nothing changes'] = function(t)
    world()
    local b = client('B', 'b', false)
    chat('!crewswap protect off', b)
    t.eq(W.told[1].text, '[CrewSwap] Only admins can change CrewSwap settings.')
    t.eq(CS.config.toggles.protect, true)
    t.eq(W.files['/save/CrewSwap/config.txt'], nil)
  end,
  ['status is open to everyone'] = function(t)
    world()
    chat('!crewswap status', client('B', 'b', false))
    t.ok(W.told[1].text:find('Crew pool: shared', 1, true))
    t.ok(W.told[1].text:find('Home protection: on', 1, true))
  end,
  ['status shows a self-switched-off mod and its reason'] = function(t)
    world()
    CS.active, CS.failReason = false, 'patch crewswap.x failed'
    chat('!crewswap status', client('B', 'b', false))
    t.ok(W.told[1].text:find('CrewSwap is off: patch crewswap.x failed', 1, true), W.told[1].text)
  end,
  ['protect off applies at once and is persisted'] = function(t)
    world()
    chat('!crewswap protect off', client('A', 'a', true))
    t.eq(CS.config.toggles.protect, false)
    t.eq(W.files['/save/CrewSwap/config.txt'], 'pool=shared\nprotect=off\n')
    t.eq(W.files['/save/CrewSwap/config.txt.tmp'], nil, 'tmp moved')
    t.eq(W.broadcasts, 1)
    t.eq(#W.announced, 1)
  end,
  ['config is loaded on start (survives a restart)'] = function(t)
    world({ config = 'pool=own\nprotect=off\n' })
    t.eq(CS.config.toggles.pool, 'own'); t.eq(CS.config.toggles.protect, false)
  end,
  ['missing or garbage config gives defaults'] = function(t)
    world(); t.eq(CS.config.toggles.pool, 'shared'); t.eq(CS.config.toggles.protect, true)
    world({ config = '\0\0 junk' }); t.eq(CS.config.toggles.protect, true)
  end,
  ['failed config write is reported but the toggle still applies'] = function(t)
    world(); W.failWrite = true
    local a = client('A', 'a', true)
    chat('!crewswap pool own', a)
    t.eq(CS.config.toggles.pool, 'own')
    t.ok(W.told[1].text:find('Could not save', 1, true))
  end,
  ['usage error goes to the admin only'] = function(t)
    world()
    chat('!crewswap pool nope', client('A', 'a', true))
    t.ok(W.told[1].text:find('Usage', 1, true))
  end,
  ['owner command sets the record owner'] = function(t)
    world()
    local ann = client('Ann', 'STEAM_A', false)
    W.clients = { ann }
    W.views = { { id = 1, sid = 's1', name = 'Kim Lee' } }
    chat('!crewswap owner "Kim Lee" Ann', client('Root', 'r', true))
    t.eq(CS.reg.chars.s1.owner, 'STEAM_A')
    chat('!crewswap owner Nobody Ann', client('Root', 'r', true))
    t.ok(W.told[#W.told].text:find('No crew member', 1, true))
  end,
  ['check passing lifts an integrity lockdown only'] = function(t)
    world()
    local root = client('Root', 'r', true)
    CS.runCheck = function() return true end
    CS.lockdown, CS.integrityLock = true, true
    chat('!crewswap check', root)
    t.eq(CS.lockdown, false); t.eq(CS.integrityLock, false)
    CS.lockdown, CS.integrityLock = true, false   -- e.g. a failed patch
    chat('!crewswap check', root)
    t.eq(CS.lockdown, true, 'non-integrity lockdown stays')
    CS.runCheck = function() return false end
    CS.lockdown, CS.integrityLock = true, true
    chat('!crewswap check', root)
    t.eq(CS.lockdown, true)
  end,
  ['check passing never re-activates a mod with a FAIL on record'] = function(t)
    world()
    local root = client('Root', 'r', true)
    local recomputed = 0
    CS.runCheck = function() return true end
    CS.recomputeActive = function() recomputed = recomputed + 1; CS.active = true; return true end
    CS.active, CS.lockdown, CS.integrityLock, CS.failReason = false, true, true, 'patch crewswap.x failed'
    chat('!crewswap check', root)
    t.eq(CS.integrityLock, false, 'integrity lock cleared')
    t.eq(CS.lockdown, true, 'lockdown stays')
    t.eq(CS.active, false); t.eq(recomputed, 0)
    t.eq(W.told[#W.told].text, '[CrewSwap] The integrity check passed, but CrewSwap is still locked down (see the server console).')
  end,
  ['hire postfix records the hirer as owner (own mode)'] = function(t)
    world()
    CS.config.toggles.pool = 'own'
    local hire = W.patches['crewswap.hire.owner']
    t.eq(hire.when, 'A'); t.eq(hire.m, 'TryHireCharacter')
    local info = { ID = 42, Name = 'Rookie' }
    local ann = client('Ann', 'STEAM_A', false)
    hire.fn(nil, { ReturnValue = true, client = ann, characterInfo = info })
    t.eq(CS.reg.chars[CS.sidOfInfo(info)].owner, 'STEAM_A')
  end,
  ['hire postfix: a hire in shared mode stays unowned (first player claims it later)'] = function(t)
    world()
    local hire = W.patches['crewswap.hire.owner']
    local info = { ID = 44, Name = 'Early' }
    hire.fn(nil, { ReturnValue = true, client = client('Ann', 'STEAM_A'), characterInfo = info })
    t.eq(CS.reg:sidOf(44), nil, 'no owner, no record')
  end,
  ['hire postfix: a Permadeath replacement character (buyingNewCharacter) is not a hire'] = function(t)
    world()
    CS.config.toggles.pool = 'own'
    local hire = W.patches['crewswap.hire.owner']
    local info = { ID = 45, Name = 'NewMe' }
    hire.fn(nil, { ReturnValue = true, client = client('Ann', 'STEAM_A'), characterInfo = info, buyingNewCharacter = true })
    t.eq(CS.reg:sidOf(45), nil)
  end,
  ['hire postfix ignores failed hires and hires without a client'] = function(t)
    world()
    local hire = W.patches['crewswap.hire.owner']
    local info = { ID = 43, Name = 'X' }
    hire.fn(nil, { ReturnValue = false, client = client('A', 'a'), characterInfo = info })
    hire.fn(nil, { ReturnValue = true, client = nil, characterInfo = info })
    t.eq(CS.reg:sidOf(43), nil, 'no record minted')
  end,
}

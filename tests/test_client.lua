-- client/main.lua against fake client globals (Networking, Hook, Timer, GUI, Game, CrewManager rows).
local codec = require('crewswap.core.statecodec')
local rules = require('crewswap.core.rules')
local BUILD = require('crewswap.shared.build').BUILD
local F = require('fakes')

local W

local function row(c)
  local r = { UserData = c, Color = 'white', HoverColor = 'hover', children = {}, RectTransform = {} }
  r.RectTransform.owner = r
  r.children[1] = { UserData = 'name', TextColor = 'job' }
  function r:FindChild(ud, rec)
    for _, ch in ipairs(self.children) do if ch.UserData == ud and (rec or ud ~= 'name') then return ch end end
  end
  function r:RemoveChild(ch)
    for i, x in ipairs(self.children) do if x == ch then table.remove(self.children, i) return end end
  end
  return r
end

local function char(id, o)
  local c = { ID = id, Name = 'c' .. id, IsPlayer = false, IsDead = false, Removed = false,
              types = { ['Barotrauma.Character'] = true } }
  for k, v in pairs(o or {}) do c[k] = v end
  W.entities[id] = c
  return c
end

local function crewManager()
  local cm = { calls = {} }
  cm.crewList = { DraggedElement = nil, Content = { rows = {} } }
  local content = cm.crewList.Content
  function content:GetChildByUserData(c) for _, r in ipairs(self.rows) do if r.UserData == c then return r end end end
  function content:GetChildIndex(r) for i, x in ipairs(self.rows) do if x == r then return i - 1 end end return -1 end
  function cm:RemoveCharacterFromCrewList(c)
    for i, r in ipairs(content.rows) do if r.UserData == c then table.remove(content.rows, i) break end end
    self.calls[#self.calls + 1] = 'remove'
  end
  -- Like the real AddCharacter: builds the row via AddCharacterToCrewList, so the postfix runs.
  function cm:AddCharacter(c) self.calls[#self.calls + 1] = 'add'; W.addRow(c) end
  function cm:DisableCommandUI() self.calls[#self.calls + 1] = 'disablecmd' end
  function cm:ResetCrewListOpenState() self.calls[#self.calls + 1] = 'resetopen' end
  function cm:AutoHideCrewList() self.calls[#self.calls + 1] = 'autohide' end
  return cm
end

local function load(o)
  o = o or {}
  package.loaded['crewswap.client.main'] = nil
  W = { recv = {}, sent = {}, patches = {}, hooks = {}, waits = {}, msgs = {}, chat = {}, order = {},
        entities = {}, now = 50, statics = {} }
  W.statics['Barotrauma.Timing'] = setmetatable({}, { __index = function(_, k) if k == 'TotalTime' then return W.now end end })
  W.statics['Barotrauma.CoroutineManager'] = { IsCoroutineRunning = function(name) return W.transition == true end }
  W.statics['Barotrauma.ConversationAction'] = { IsDialogOpen = false }
  W.statics['Barotrauma.HintManager'] = { OnChangeCharacter = function() W.hinted = true end }
  W.statics['Barotrauma.TabMenu'] = { SelectedTab = 0 }
  W.statics['Barotrauma.GameSession'] = { TabMenuInstance = nil }
  W.statics['Barotrauma.ChatBox'] = { ResetChatBoxOpenState = function() W.chatReset = true end,
                                      AutoHideChatBox = function() W.chatHidden = true end }
  _G.SERVER, _G.CLIENT = false, true
  _G.CSC = nil
  _G.Color = setmetatable({ Red = 'red', LightGreen = 'green' }, { __call = function(_, r, g, b, a) return 'grey' end })
  _G.Vector2 = function(x, y) return { x = x, y = y } end
  _G.ChatMessageType = { Server = 3, Error = 1 }
  _G.Inventory = { DraggingSlot = 'slot' }
  _G.Entity = { FindEntityByID = function(id) return W.entities[id] end }
  _G.GUI = {
    AddMessage = function(text, color) W.msgs[#W.msgs + 1] = { text = text, color = color } end,
    RectTransform = function(size, parent, anchor) return { parent = parent } end,
    TextBlock = function(rt, text)
      local b = { Text = text }
      local owner = rt.parent.owner
      owner.children[#owner.children + 1] = b
      return b
    end,
    Anchor = { CenterRight = 5 }, Alignment = { CenterRight = 6 }, GUIStyle = { SmallFont = 'small' },
  }
  _G.LuaUserData = {
    CreateStatic = function(name) return W.statics[name] or {} end,
    IsTargetType = function(x, ty) return type(x) == 'table' and x.types ~= nil and x.types[ty] == true end,
    RegisterType = function(name) return { name = name } end,
    MakeFieldAccessible = function() if o.fieldFails then error('no field') end end,
  }
  _G.Networking = {
    Receive = function(name, fn) W.recv[name] = fn; W.order[#W.order + 1] = 'recv:' .. name end,
    Start = function(name) local b = F.buffer(); b.name = name; return b end,
    Send = function(m) W.sent[#W.sent + 1] = m; W.order[#W.order + 1] = 'send:' .. m.name end,
  }
  _G.Hook = {
    HookMethodType = { Before = 'B', After = 'A' },
    Patch = function(id, class, method, fn, when)
      W.order[#W.order + 1] = 'patch:' .. id
      if o.failPatch == id then error('method not found') end
      W.patches[id] = { class = class, method = method, fn = fn, when = when }
    end,
    Add = function(ev, id, fn) W.hooks[ev] = fn end,
  }
  _G.Timer = { Wait = function(fn, ms)
    local quiet = function() local rp = print; print = function() end; fn(); print = rp end
    W.waits[#W.waits + 1] = { fn = quiet, ms = ms }
  end }
  W.cm = crewManager()
  W.me = char(1, { Name = 'Me', IsPlayer = true })
  _G.Game = {
    IsMultiplayer = true,
    GameSession = { CrewManager = W.cm },
    Client = { Character = W.me, EndCinematic = nil },
  }
  function Game.Client:AddChatMessage(text, ty) W.chat[#W.chat + 1] = { text = text, ty = ty } end
  function W.addRow(c)
    local r = row(c)
    table.insert(W.cm.crewList.Content.rows, r)
    local p = { character = c, ReturnValue = r }
    local n = select('#', W.patches['crewswap.row'].fn(W.cm, p))
    W.lastRowReturns = n
    return r
  end
  local realPrint = print
  print = function() end
  local ok, err = pcall(dofile, 'mod/CrewSwap/Lua/crewswap/client/main.lua')
  print = realPrint
  assert(ok, err)
  return W
end

local function stateMsg(entries)
  local b = F.buffer()
  codec.encode(b, entries)
  return b
end

local function click(sel)
  local p = { selection = sel }
  local r = W.patches['crewswap.click'].fn(W.cm, p)
  return r, p
end

return {
 ['client: handlers registered before patches and before the hello'] = function(t)
   load()
   t.eq(W.order[1], 'recv:crewswap.state'); t.eq(W.order[2], 'recv:crewswap.denied')
   t.eq(#W.sent, 0, 'hello waits')
   t.eq(#W.waits, 1); t.eq(W.waits[1].ms, 2000)
   W.waits[1].fn()
   local m = W.sent[1]
   t.eq(m.name, 'crewswap.hello')
   t.eq(m:ReadString(), BUILD); t.eq(m:ReadBoolean(), true)
 end,
 ['client: patches are Before CharacterClicked and After AddCharacterToCrewList'] = function(t)
   load()
   t.eq(W.patches['crewswap.click'].method, 'CharacterClicked'); t.eq(W.patches['crewswap.click'].when, 'B')
   t.eq(W.patches['crewswap.row'].method, 'AddCharacterToCrewList'); t.eq(W.patches['crewswap.row'].when, 'A')
 end,
 ['client: a failed patch or field probe reports probes false in the hello'] = function(t)
   for _, o in ipairs({ { failPatch = 'crewswap.row' }, { failPatch = 'crewswap.click' }, { fieldFails = true } }) do
     load(o)
     W.waits[1].fn()
     local m = W.sent[1]; m:ReadString()
     t.eq(m:ReadBoolean(), false)
   end
 end,
 ['client: state message fills CSC.state by entity id'] = function(t)
   load()
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true }, { id = 8, controller = 'Bob', free = false } }))
   t.eq(CSC.state[7].free, true); t.eq(CSC.state[7].controller, '')
   t.eq(CSC.state[8].controller, 'Bob'); t.eq(CSC.state[8].free, false)
   W.recv['crewswap.state'](stateMsg({ { id = 8, controller = '', free = true } }))
   t.eq(CSC.state[7], nil, 'replaced, not merged')
 end,
 ['client: click on a free bot sends the request and prevents vanilla'] = function(t)
   load()
   local bot = char(7)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true } }))
   local r, p = click(bot)
   t.eq(r, true); t.eq(p.PreventExecution, true)
   local m = W.sent[#W.sent]
   t.eq(m.name, 'crewswap.request'); t.eq(m:ReadUInt16(), 7)
 end,
 ['client: clicks stay vanilla for taken, own, unknown rows, non-characters and singleplayer'] = function(t)
   load()
   local bot, taken, unknown = char(7), char(8), char(9)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true }, { id = 8, controller = 'Bob', free = false },
                                        { id = 1, controller = 'Me', free = true } }))
   for _, sel in ipairs({ taken, W.me, unknown, { ID = 7 }, nil }) do
     local r, p = click(sel)
     t.eq(r, nil); t.eq(p.PreventExecution, nil)
   end
   Game.IsMultiplayer = false
   local r, p = click(bot)
   t.eq(r, nil); t.eq(p.PreventExecution, nil)
   t.eq(#W.sent, 0)
 end,
 ['client: click on a crew bot that is not Free for me asks the server, which says why; vanilla runs'] = function(t)
   load()
   local bot = char(7)   -- e.g. another player's idle home under protect, or an unconscious bot
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = false } }))
   local r, p = click(bot)
   t.eq(r, nil); t.eq(p.PreventExecution, nil, 'vanilla camera behaviour kept')
   local m = W.sent[#W.sent]
   t.eq(m.name, 'crewswap.request'); t.eq(m:ReadUInt16(), 7)
   -- the local guards still apply: no request inside a conversation
   W.statics['Barotrauma.ConversationAction'].IsDialogOpen = true
   local n = #W.sent
   click(bot)
   t.eq(#W.sent, n)
 end,
 ['client: rows that are not Free for me (and not taken) get a dimmed name'] = function(t)
   load()
   local bot = char(7)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = false } }))
   local r = W.addRow(bot)
   t.eq(r.children[1].TextColor, 'grey', 'dimmed'); t.eq(r.Color, 'white', 'row colour unchanged')
   t.eq(r:FindChild('crewswap.label', false), nil)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true } }))
   t.eq(r.children[1].TextColor, 'job', 'Free again: original colour')
 end,
 ['client: the hello is resent every 5 s until the first state arrives (at most 12 tries)'] = function(t)
   load()
   W.waits[1].fn()
   t.eq(#W.sent, 1)
   t.eq(W.waits[2].ms, 5000)
   W.waits[2].fn()
   t.eq(#W.sent, 2); t.eq(W.sent[2].name, 'crewswap.hello')
   W.recv['crewswap.state'](stateMsg({}))
   W.waits[3].fn()
   t.eq(#W.sent, 2, 'no resend once state arrived')
   t.eq(W.waits[4], nil, 'and no further retry')
   load()
   local i = 1
   while W.waits[i] do W.waits[i].fn(); i = i + 1 end
   t.eq(#W.sent, 12, 'capped')
 end,
 ['client: the server asking for a hello gets one at once, even after state arrived'] = function(t)
   load()
   W.recv['crewswap.state'](stateMsg({}))
   t.ok(W.recv['crewswap.hello?'] ~= nil, 'handler registered')
   W.recv['crewswap.hello?'](F.buffer())
   local m = W.sent[#W.sent]
   t.eq(m.name, 'crewswap.hello'); t.eq(m:ReadString(), BUILD)
 end,
 ['client: click while dead (no character) on a free bot still requests'] = function(t)
   load()
   local bot = char(7)
   Game.Client.Character = nil
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true } }))
   local r = click(bot)
   t.eq(r, true); t.eq(W.sent[#W.sent].name, 'crewswap.request')
 end,
 ['client: dialogue and camera transition block locally without a request'] = function(t)
   load()
   local bot = char(7)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true } }))
   W.statics['Barotrauma.ConversationAction'].IsDialogOpen = true
   local r, p = click(bot)
   t.eq(r, true); t.eq(p.PreventExecution, true)
   t.eq(W.msgs[#W.msgs].text, rules.message('dialogue')); t.eq(W.msgs[#W.msgs].color, 'red')
   W.statics['Barotrauma.ConversationAction'].IsDialogOpen = false
   W.transition = true
   r, p = click(bot)
   t.eq(r, true); t.eq(p.PreventExecution, true)
   W.transition = false
   Game.Client.EndCinematic = { Running = true }
   click(bot)
   t.eq(#W.sent, 0)
 end,
 ['client: own control change notifies once, does housekeeping and starts the cooldown echo'] = function(t)
   load()
   W.hooks.think()
   t.eq(#W.msgs, 0, 'first body is not a switch')
   local bot = char(7, { Name = 'Ann' })
   Game.Client.Character = bot
   W.hooks.think()
   t.eq(W.msgs[1].text, '[CrewSwap] Now playing Ann'); t.eq(W.msgs[1].color, 'green')
   t.eq(W.chat[1].text, '[CrewSwap] Now playing Ann'); t.eq(W.chat[1].ty, 3)
   t.eq(Inventory.DraggingSlot, nil); t.eq(W.hinted, true); t.eq(W.chatReset, true)
   t.eq(W.cm.calls[1], 'disablecmd')
   W.hooks.think()
   t.eq(#W.msgs, 1, 'no repeat while unchanged')
   -- cooldown echo: within 3 s a click on a free bot shows seconds and sends nothing
   local other = char(9)
   W.recv['crewswap.state'](stateMsg({ { id = 9, controller = '', free = true } }))
   W.now = W.now + 1
   click(other)
   t.eq(W.msgs[#W.msgs].text, rules.message('cooldown', 2)); t.eq(#W.sent, 0)
   W.now = W.now + 2.5
   click(other)
   t.eq(W.sent[#W.sent].name, 'crewswap.request')
 end,
 ['client: a throwing UI call during a control change fires once and fails open'] = function(t)
   for _, mode in ipairs({ 'chat', 'textblock' }) do
     load()
     local taken = char(8)
     W.recv['crewswap.state'](stateMsg({ { id = 8, controller = 'Bob', free = false }, { id = 9, controller = '', free = true } }))
     if mode == 'chat' then
       function Game.Client:AddChatMessage() error('chat broke') end
     else
       GUI.TextBlock = function() error('textblock broke') end
       W.addRow(taken)   -- label creation fails inside the (pcall'd) postfix; styleAll will retry and throw
     end
     W.hooks.think()
     Game.Client.Character = char(7, { Name = 'Ann' })
     W.hooks.think()
     t.eq(#W.msgs, 1, mode .. ': notified once')
     t.eq(W.msgs[1].text, '[CrewSwap] Now playing Ann', mode)
     t.eq(W.cm.calls[1], 'disablecmd', mode)
     local ncalls, changedAt = #W.cm.calls, CSC.lastSwitchAt
     W.now = W.now + 1
     W.hooks.think()
     t.eq(#W.msgs, 1, mode .. ': second think does not re-fire')
     t.eq(#W.cm.calls, ncalls, mode .. ': no repeated housekeeping')
     t.eq(CSC.lastSwitchAt, changedAt, mode .. ': cooldown not reset')
     W.now = W.now + 2.5
     click(char(9))
     t.eq(W.sent[#W.sent].name, 'crewswap.request', mode .. ': click after 3 s requests')
   end
 end,
 ['client: a nil frame between old and new body still counts as a switch'] = function(t)
   load()
   W.hooks.think()
   Game.Client.Character = nil; W.hooks.think()
   Game.Client.Character = char(7, { Name = 'Ann' }); W.hooks.think()
   t.eq(W.msgs[1].text, '[CrewSwap] Now playing Ann')
 end,
 ['client: round start and end reset the control watch'] = function(t)
   for _, ev in ipairs({ 'roundStart', 'roundEnd' }) do
     load()
     W.hooks.think()
     W.hooks[ev]()
     Game.Client.Character = char(7); W.hooks.think()
     t.eq(#W.msgs, 0, ev)
   end
 end,
 ['client: denied shows the rules message as an error'] = function(t)
   load()
   local m = F.buffer(); m:WriteString('cooldown'); m:WriteSingle(2)
   W.recv['crewswap.denied'](m)
   t.eq(W.msgs[1].text, rules.message('cooldown', 2)); t.eq(W.msgs[1].color, 'red')
   t.eq(W.chat[1].ty, 1)
   m = F.buffer(); m:WriteString('taken'); m:WriteSingle(0)
   W.recv['crewswap.denied'](m)
   t.eq(W.msgs[2].text, rules.message('taken'))
 end,
 ['client: row postfix returns nothing and styles taken rows grey with the controller name'] = function(t)
   load()
   local bot = char(7)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = 'Bob', free = false } }))
   local r = W.addRow(bot)
   t.eq(W.lastRowReturns, 0, 'bare return')
   t.eq(r.Color, 'grey'); t.eq(r.HoverColor, 'grey'); t.eq(r.children[1].TextColor, 'grey')
   local label = r:FindChild('crewswap.label', false)
   t.ok(label, 'label'); t.eq(label.Text, 'Bob'); t.eq(label.CanBeFocused, false)
   -- free again: originals restored and the label removed
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = '', free = true } }))
   t.eq(r.Color, 'white'); t.eq(r.HoverColor, 'hover'); t.eq(r.children[1].TextColor, 'job')
   t.eq(r:FindChild('crewswap.label', false), nil)
 end,
 ['client: postfix ignores a nil row (row already existed)'] = function(t)
   load()
   local p = { character = char(7), ReturnValue = nil }
   t.eq(select('#', W.patches['crewswap.row'].fn(W.cm, p)), 0)
   t.eq(CSC.rows[7], nil)
 end,
 ['client: rows built before the Lua state are adopted on a state message'] = function(t)
   load()
   local bot = char(7)
   local r = row(bot); table.insert(W.cm.crewList.Content.rows, r)
   W.recv['crewswap.state'](stateMsg({ { id = 7, controller = 'Bob', free = false } }))
   t.eq(r.Color, 'grey'); t.eq(CSC.rows[7], bot)
 end,
 ['client: a row is rebuilt in place when IsPlayer flips, but not mid-drag'] = function(t)
   load()
   local a, bot = char(5), char(7, { IsPlayer = true })
   W.addRow(a); W.addRow(bot); W.addRow(char(8))
   bot.IsPlayer = false
   W.cm.crewList.DraggedElement = 'dragging'
   W.hooks.think()
   t.eq(#W.cm.calls, 0, 'not while dragging')
   W.cm.crewList.DraggedElement = nil
   local repositioned
   W.now = W.now + 1
   local realAdd = W.addRow
   W.addRow = function(c)
     local r = realAdd(c)
     function r.RectTransform:RepositionChildInHierarchy(i) repositioned = i end
     return r
   end
   W.hooks.think()
   t.eq(W.cm.calls[1], 'remove'); t.eq(W.cm.calls[2], 'add'); t.eq(repositioned, 1)
   t.eq(CSC.builtPlayer[7], false)
   W.now = W.now + 1
   W.hooks.think()
   t.eq(#W.cm.calls, 2, 'no second rebuild')
 end,
}

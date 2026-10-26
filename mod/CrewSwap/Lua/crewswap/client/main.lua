-- Client UI: click a Free crew row to ask the server for that body, grey out taken
-- rows, housekeeping after the client's own control changes, and denial messages.
-- Talks to the server over the crewswap.* network messages (hello, request, state, denied).
if not CLIENT then return end
local build = require('crewswap.shared.build')
local codec = require('crewswap.core.statecodec')
local rules = require('crewswap.core.rules')
print('[CrewSwap] client loaded build ' .. build.BUILD)

CSC = {
  state = {},       -- [entity id] = { controller = name or '', free = bool }, from crewswap.state
  rows = {},        -- [entity id] = Character with a crew row we have seen built
  orig = {},        -- [entity id] = { row =, color =, hover =, nameColor = } saved before any tint
  builtPlayer = {}, -- [entity id] = c.IsPlayer when its row was built (objective icons depend on it)
  probesOk = true,
  lastSwitchAt = nil,
  lastNonNil = nil, -- id of the last non-nil Game.Client.Character this round
}

local GREY = Color(110, 110, 110, 255)
local DIM = Color(165, 165, 165, 255)   -- name of a crew bot that isn't Free for this player
local LABEL = 'crewswap.label'
local TALENTS = 4   -- TabMenu.InfoFrameTab { Crew, Mission, Reputation, Submarine, Talents }
local REBUILD_EVERY = 0.5

local function log(s) print('[CrewSwap] client: ' .. s) end

local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log(name .. ' error: ' .. tostring(err)) end
  end
end

local function static(name)
  local ok, s = pcall(LuaUserData.CreateStatic, name)
  if ok then return s end
  CSC.probesOk = false
  log('missing ' .. name .. ': ' .. tostring(s))
  return nil
end

local Timing = static('Barotrauma.Timing')
local CoMgr = static('Barotrauma.CoroutineManager')
local ConvAction = static('Barotrauma.ConversationAction')
local HintMgr = static('Barotrauma.HintManager')
local TabMenuS = static('Barotrauma.TabMenu')
local GameSessS = static('Barotrauma.GameSession')
local ChatBoxS = static('Barotrauma.ChatBox')

local function now() return Timing.TotalTime end

function CSC.notify(text, isError)
  if text:sub(1, 10) ~= '[CrewSwap]' then text = '[CrewSwap] ' .. text end
  GUI.AddMessage(text, isError and Color.Red or Color.LightGreen)
  if Game.Client ~= nil then
    Game.Client:AddChatMessage(text, isError and ChatMessageType.Error or ChatMessageType.Server)
  end
end

local function crewManager()
  local gs = Game.GameSession
  return gs ~= nil and gs.CrewManager or nil
end

local function rowOf(cm, c)
  if cm == nil or cm.crewList == nil then return nil end
  return cm.crewList.Content:GetChildByUserData(c)
end

-- ---------- row styling ----------

local function saveOriginal(c, row)
  local o = CSC.orig[c.ID]
  if o ~= nil and o.row == row then return o end
  local name = row:FindChild('name', true)
  o = { row = row, color = row.Color, hover = row.HoverColor, nameColor = name and name.TextColor }
  CSC.orig[c.ID] = o
  return o
end

function CSC.styleRow(c)
  local row = rowOf(crewManager(), c)
  if row == nil then return end
  local o = saveOriginal(c, row)
  local st = CSC.state[c.ID]
  local controller = st and st.controller ~= '' and st.controller or nil
  local name = row:FindChild('name', true)
  local label = row:FindChild(LABEL, false)
  if controller then
    row.Color = GREY
    row.HoverColor = GREY
    if name then name.TextColor = GREY end
    if label == nil then
      label = GUI.TextBlock(GUI.RectTransform(Vector2(0.45, 1), row.RectTransform, GUI.Anchor.CenterRight),
        '', nil, GUI.GUIStyle.SmallFont, GUI.Alignment.CenterRight)
      label.UserData = LABEL
      label.CanBeFocused = false
    end
    label.Text = controller
    label.TextColor = GREY
  else
    if label ~= nil then row:RemoveChild(label) end
    row.Color = o.color
    row.HoverColor = o.hover
    if name then
      if st ~= nil and not st.free then name.TextColor = DIM   -- not takeable by me
      elseif o.nameColor then name.TextColor = o.nameColor end
    end
  end
end

function CSC.styleAll()
  local seen = {}
  for id, c in pairs(CSC.rows) do seen[id] = true; CSC.styleRow(c) end
  for id in pairs(CSC.state) do
    if not seen[id] then
      -- a row built before this Lua state existed (e.g. after reloadlua): adopt it
      local c = Entity.FindEntityByID(id)
      if c ~= nil and LuaUserData.IsTargetType(c, 'Barotrauma.Character') and rowOf(crewManager(), c) ~= nil then
        CSC.rows[id] = c
        CSC.builtPlayer[id] = c.IsPlayer == true
        CSC.styleRow(c)
      end
    end
  end
end

-- Postfix on AddCharacterToCrewList; ReturnValue is nil when the row already existed.
-- Must not return a value (it would replace the method's result).
function CSC.onRowAdded(cm, p)
  local row, c = p.ReturnValue, p['character']
  if row == nil or c == nil then return end
  CSC.rows[c.ID] = c
  CSC.builtPlayer[c.ID] = c.IsPlayer == true
  saveOriginal(c, row)
  CSC.styleRow(c)
end

-- Rebuild a row whose IsPlayer flipped since it was built, so vanilla re-reads it. Never mid-drag.
function CSC.rebuildRow(cm, c)
  if cm.crewList.DraggedElement ~= nil then return false end
  if c.IsDead or c.Removed then return false end
  local row = rowOf(cm, c)
  if row == nil then return false end
  local idx = cm.crewList.Content:GetChildIndex(row)
  cm:RemoveCharacterFromCrewList(c)
  cm:AddCharacter(c)
  local nrow = rowOf(cm, c)
  if nrow ~= nil then nrow.RectTransform:RepositionChildInHierarchy(idx) end
  return true
end

local function checkFlips()
  local cm = crewManager()
  if cm == nil then return end
  for id, c in pairs(CSC.rows) do
    if c.Removed or rowOf(cm, c) == nil then
      CSC.rows[id], CSC.builtPlayer[id], CSC.orig[id] = nil, nil, nil
    elseif (c.IsPlayer == true) ~= CSC.builtPlayer[id] then
      CSC.rebuildRow(cm, c)
    end
  end
end

-- ---------- click: request a body; guards for dialogue, camera transitions, cooldown ----------

local function cameraTransitionActive()
  if CoMgr.IsCoroutineRunning('CameraTransition') then return true end
  local ec = Game.Client and Game.Client.EndCinematic
  return ec ~= nil and ec.Running == true
end

local function sendRequest(id)
  local m = Networking.Start('crewswap.request')
  m:WriteUInt16(id)
  Networking.Send(m)
end

-- Returns nil for vanilla, or true after setting PreventExecution.
-- A crew bot that isn't Free for this player (another player's home under protect, someone
-- else's in own mode, unconscious) still asks the server, so its denial says why; vanilla's
-- click (camera) runs as usual. Taken rows already show who has them.
function CSC.onClick(cm, p)
  if not Game.IsMultiplayer or Game.Client == nil then return end
  local sel = p['selection']
  if sel == nil or not LuaUserData.IsTargetType(sel, 'Barotrauma.Character') then return end
  local mine = Game.Client.Character
  if mine ~= nil and mine.ID == sel.ID then return end
  local st = CSC.state[sel.ID]
  if st == nil then return end
  if not st.free then
    if st.controller == '' and not ConvAction.IsDialogOpen and not cameraTransitionActive() then
      sendRequest(sel.ID)
    end
    return
  end
  p.PreventExecution = true
  if ConvAction.IsDialogOpen then
    CSC.notify(rules.message('dialogue'), true)
  elseif cameraTransitionActive() then
    -- silently ignored: a switch now would be undone when the transition restores its character
  elseif CSC.lastSwitchAt ~= nil and now() - CSC.lastSwitchAt < rules.COOLDOWN then
    CSC.notify(rules.message('cooldown', math.ceil(rules.COOLDOWN - (now() - CSC.lastSwitchAt))), true)
  else
    sendRequest(sel.ID)
  end
  return true
end

-- ---------- own control change: detected by watching Character.ID (lastNonNil), then UI housekeeping ----------

local function try(name, fn)
  local ok, err = pcall(fn)
  if not ok then log('housekeeping ' .. name .. ': ' .. tostring(err)) end
end

function CSC.afterOwnControlChange(newChar)
  local cm = crewManager()
  if cm then try('command ui', function() cm:DisableCommandUI() end) end
  -- Inventory.DraggingItems is a copied List (no Clear); GameScreen clears it once the button is up.
  try('drag', function() Inventory.DraggingSlot = nil end)
  try('hints', function() HintMgr.OnChangeCharacter() end)
  try('talents', function()
    local tm = GameSessS.TabMenuInstance
    if tm ~= nil and TabMenuS.SelectedTab == TALENTS then tm:SelectInfoFrameTab(TabMenuS.SelectedTab) end
  end)
  try('open state', function()
    local sel = newChar.SelectedItem
    local operating = sel ~= nil and sel:GetComponentString('Controller') ~= nil
    if not operating and newChar.SelectedCharacter == nil then
      if cm then cm:ResetCrewListOpenState() end
      ChatBoxS.ResetChatBoxOpenState()
    else
      if cm then cm:AutoHideCrewList() end
      ChatBoxS.AutoHideChatBox()
    end
  end)
end

function CSC.resetControl() CSC.lastNonNil = nil end

local nextFlipCheck = 0
function CSC.think()
  local cl = Game.Client
  if cl == nil then return end
  local mine = cl.Character
  if mine ~= nil then
    -- Record the new id before any side effect, so a throwing UI call can't re-fire this every frame.
    local prev = CSC.lastNonNil
    CSC.lastNonNil = mine.ID
    if prev ~= nil and mine.ID ~= prev then
      CSC.lastSwitchAt = now()
      try('control change', function() CSC.afterOwnControlChange(mine) end)
      try('notify', function() CSC.notify('Now playing ' .. mine.Name) end)
      try('style', CSC.styleAll)
    end
  end
  if now() >= nextFlipCheck then
    nextFlipCheck = now() + REBUILD_EVERY
    checkFlips()
  end
end

-- ---------- messages ----------

function CSC.applyState(entries)
  CSC.gotState = true   -- the server has our hello: stop resending it
  local st = {}
  for _, e in ipairs(entries) do st[e.id] = { controller = e.controller, free = e.free } end
  CSC.state = st
  CSC.styleAll()
end

-- Handlers first: state sent before Receive is registered is dropped (see book: Networking).
Networking.Receive('crewswap.state', safe('state', function(msg) CSC.applyState(codec.decode(msg)) end))
Networking.Receive('crewswap.denied', safe('denied', function(msg)
  local reason = msg:ReadString()
  local extra = msg:ReadSingle()
  CSC.notify(rules.message(reason, extra), true)
end))

-- Probe-install the patches; a failure means this client can't run the UI, which the hello reports.
local function probe(id, class, method, fn, when)
  local ok, err = pcall(Hook.Patch, id, class, method, fn, when)
  if not ok then
    CSC.probesOk = false
    log('patch ' .. id .. ' failed: ' .. tostring(err))
  end
end

local okField, fieldErr = pcall(function()
  LuaUserData.MakeFieldAccessible(LuaUserData.RegisterType('Barotrauma.CrewManager'), 'crewList')
end)
if not okField then
  CSC.probesOk = false
  log('crewList access failed: ' .. tostring(fieldErr))
end

probe('crewswap.click', 'Barotrauma.CrewManager', 'CharacterClicked', function(cm, p)
  local ok, r = pcall(CSC.onClick, cm, p)
  if not ok then log('click error: ' .. tostring(r)); return end
  if r then return true end
end, Hook.HookMethodType.Before)

probe('crewswap.row', 'Barotrauma.CrewManager', 'AddCharacterToCrewList', function(cm, p)
  local ok, err = pcall(CSC.onRowAdded, cm, p)
  if not ok then log('row error: ' .. tostring(err)) end
end, Hook.HookMethodType.After)

Hook.Add('think', 'crewswap.client.think', safe('think', CSC.think))
-- Rows are built before roundStart fires, so only roundEnd forgets them.
Hook.Add('roundStart', 'crewswap.client.rs', safe('roundStart', CSC.resetControl))
Hook.Add('roundEnd', 'crewswap.client.re', safe('roundEnd', function()
  CSC.resetControl()
  CSC.rows, CSC.orig, CSC.builtPlayer = {}, {}, {}
end))

-- 2 s after load the client is usually in the server's ConnectedClients (see book: Networking).
-- A hello that lands too early (slow join, mod download) is lost, so it is resent every 5 s
-- until the first crewswap.state answers it, at most HELLO_TRIES times.
CSC.HELLO_RETRY_MS = 5000
CSC.HELLO_TRIES = 12
CSC.helloTries = 0
CSC.gotState = false
local function helloMessage(why)
  local m = Networking.Start('crewswap.hello')
  m:WriteString(build.BUILD)
  m:WriteBoolean(CSC.probesOk)
  Networking.Send(m)
  log('hello sent (' .. why .. '), probes ' .. (CSC.probesOk and 'ok' or 'FAILED'))
end

function CSC.sendHello()
  if CSC.gotState or CSC.helloTries >= CSC.HELLO_TRIES then return end
  CSC.helloTries = CSC.helloTries + 1
  if CSC.helloTries < CSC.HELLO_TRIES then   -- scheduled first: a throwing send still retries
    Timer.Wait(safe('hello', CSC.sendHello), CSC.HELLO_RETRY_MS)
  end
  helloMessage(tostring(CSC.helloTries))
end
Timer.Wait(safe('hello', CSC.sendHello), 2000)
-- The server asks again when it has no hello from us (e.g. after a server Lua reload).
Networking.Receive('crewswap.hello?', safe('hello?', function() helloMessage('asked') end))

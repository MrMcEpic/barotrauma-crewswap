-- Pure switch rules: what counts as a Free body, the pool/protect filter, and request validation.
local M = {}

M.COOLDOWN = 3

-- Pool / protect filter for one requester. A view with no owner and no home is unowned:
-- in 'own' mode the first player to take it claims it (the claim is recorded elsewhere).
function M.allowedByToggles(view, toggles, requesterKey)
  if toggles.protect and view.homeOf and view.homeOf ~= requesterKey then return false end
  if toggles.pool == 'own' then
    if view.owner == nil and view.homeOf == nil then return true end
    return view.owner == requesterKey or view.homeOf == requesterKey
  end
  return true
end

function M.isFree(view, toggles, requesterKey)
  return view.crew == true and view.isAI == true and view.alive == true
    and view.conscious == true and not view.removed and view.controller == nil
    and M.allowedByToggles(view, toggles, requesterKey)
end

-- Returns ok, reason. Reasons are checked in a fixed order; 'ok' on success.
-- The requester's own body is deliberately ignored: a downed player may still switch.
function M.validate(req, view, toggles, ctx)
  if not ctx.active then return false, 'inactive' end
  if not ctx.roundRunning or ctx.roundEnding then return false, 'round' end
  if not req.inGame or not req.synced then return false, 'joining' end
  -- No campaign character yet (a first-time joiner): vanilla only points client.CharacterInfo
  -- back at a player's own character through their CCD, so a switch now would lose it.
  if not req.hasHome then return false, 'nohome' end
  if req.voluntarySpectator then return false, 'spectating' end
  if req.traitor then return false, 'traitor' end
  if req.inDialogue then return false, 'dialogue' end
  if req.lastSwitchAt and ctx.now - req.lastSwitchAt < M.COOLDOWN then return false, 'cooldown' end
  if view == nil or not view.crew then return false, 'invalid' end
  if view.controller ~= nil then return false, 'taken' end
  if not (view.alive and view.conscious and not view.removed and view.isAI) then
    return false, 'unavailable'
  end
  if not M.allowedByToggles(view, toggles, req.key) then return false, 'not-yours' end
  return true, 'ok'
end

local TEXT = {
  inactive    = 'CrewSwap is off right now.',
  round       = 'You can only switch characters while a round is running.',
  joining     = 'Hold on, you are still joining the round.',
  spectating  = 'You cannot switch characters while spectating.',
  traitor     = 'Traitors cannot switch characters.',
  dialogue    = 'Finish the conversation before switching characters.',
  invalid     = 'That is not a crew member you can switch to.',
  taken       = 'Someone else is already playing that character.',
  unavailable = 'That character is dead, unconscious or otherwise unavailable.',
  ['not-yours'] = 'That character belongs to another player.',
  nohome      = 'You can switch once your own character has joined the crew (after you first spawn).',
  takeover    = 'You can only take on a new crew member once your own character is permanently dead.',
}

function M.message(reason, extra)
  if reason == 'cooldown' then
    return string.format('[CrewSwap] Too fast, wait %s more second(s) before switching again.', tostring(extra or M.COOLDOWN))
  end
  return '[CrewSwap] ' .. (TEXT[reason] or 'That switch was denied.')
end

return M

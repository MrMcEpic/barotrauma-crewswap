local rules = require('crewswap.core.rules')
local F = require('fakes')

local TOG = { pool = 'shared', protect = true }
local function ctx(o)
  local c = { now = 100, roundRunning = true, roundEnding = false, mpCampaign = true, active = true }
  for k, x in pairs(o or {}) do c[k] = x end
  return c
end
local function check(t, req, view, toggles, c, wantOk, wantReason)
  local ok, reason = rules.validate(req, view, toggles or TOG, c or ctx())
  t.eq(ok, wantOk, 'ok'); t.eq(reason, wantReason, 'reason')
end

return {
  ['cooldown constant is 3'] = function(t) t.eq(rules.COOLDOWN, 3) end,
  ['free bot is switchable'] = function(t) check(t, F.requester(), F.view(), nil, nil, true, 'ok') end,
  ['reason inactive'] = function(t) check(t, F.requester(), F.view(), nil, ctx{active=false}, false, 'inactive') end,
  ['reason round: not running'] = function(t) check(t, F.requester(), F.view(), nil, ctx{roundRunning=false}, false, 'round') end,
  ['denied while round is ending'] = function(t) check(t, F.requester(), F.view(), nil, ctx{roundEnding=true}, false, 'round') end,
  ['reason joining: not in game'] = function(t) check(t, F.requester{inGame=false}, F.view(), nil, nil, false, 'joining') end,
  ['reason joining: not synced'] = function(t) check(t, F.requester{synced=false}, F.view(), nil, nil, false, 'joining') end,
  ['reason nohome: no campaign character yet'] = function(t)
    check(t, F.requester{hasHome=false}, F.view(), nil, nil, false, 'nohome') end,
  ['order: joining beats nohome'] = function(t)
    check(t, F.requester{inGame=false, hasHome=false}, F.view(), nil, nil, false, 'joining') end,
  ['reason spectating'] = function(t) check(t, F.requester{voluntarySpectator=true}, F.view(), nil, nil, false, 'spectating') end,
  ['reason traitor'] = function(t) check(t, F.requester{traitor=true}, F.view(), nil, nil, false, 'traitor') end,
  ['reason dialogue'] = function(t) check(t, F.requester{inDialogue=true}, F.view(), nil, nil, false, 'dialogue') end,
  ['reason cooldown'] = function(t) check(t, F.requester{lastSwitchAt=99}, F.view(), nil, nil, false, 'cooldown') end,
  ['cooldown expires at 3 s'] = function(t) check(t, F.requester{lastSwitchAt=97}, F.view(), nil, nil, true, 'ok') end,
  ['reason invalid: nil view'] = function(t) check(t, F.requester(), nil, nil, nil, false, 'invalid') end,
  ['reason invalid: not crew'] = function(t) check(t, F.requester(), F.view{crew=false}, nil, nil, false, 'invalid') end,
  ['reason taken'] = function(t) check(t, F.requester(), F.view{controller='acct:B'}, nil, nil, false, 'taken') end,
  ['second request for taken target is denied'] = function(t)
    check(t, F.requester{key='acct:C'}, F.view{controller='acct:B'}, nil, nil, false, 'taken') end,
  ['reason unavailable: dead'] = function(t) check(t, F.requester(), F.view{alive=false}, nil, nil, false, 'unavailable') end,
  ['reason unavailable: unconscious'] = function(t) check(t, F.requester(), F.view{conscious=false}, nil, nil, false, 'unavailable') end,
  ['reason unavailable: removed'] = function(t) check(t, F.requester(), F.view{removed=true}, nil, nil, false, 'unavailable') end,
  ['reason unavailable: not AI'] = function(t) check(t, F.requester(), F.view{isAI=false}, nil, nil, false, 'unavailable') end,
  ['reason not-yours'] = function(t)
    check(t, F.requester(), F.view{homeOf='acct:B'}, nil, nil, false, 'not-yours') end,
  ['order: inactive beats round'] = function(t)
    check(t, F.requester(), F.view(), nil, ctx{active=false, roundRunning=false}, false, 'inactive') end,
  ['order: spectating beats traitor'] = function(t)
    check(t, F.requester{voluntarySpectator=true, traitor=true}, F.view(), nil, nil, false, 'spectating') end,
  ['order: cooldown beats invalid'] = function(t)
    check(t, F.requester{lastSwitchAt=99}, nil, nil, nil, false, 'cooldown') end,
  ['order: taken beats unavailable'] = function(t)
    check(t, F.requester(), F.view{controller='acct:B', alive=false}, nil, nil, false, 'taken') end,
  ['own home allowed under protect'] = function(t)
    check(t, F.requester(), F.view{homeOf='acct:A'}, nil, nil, true, 'ok') end,
  ['other\'s home blocked under protect'] = function(t)
    check(t, F.requester(), F.view{homeOf='acct:B'}, {pool='shared', protect=true}, nil, false, 'not-yours') end,
  ['other\'s home allowed when protect off'] = function(t)
    check(t, F.requester(), F.view{homeOf='acct:B'}, {pool='shared', protect=false}, nil, true, 'ok') end,
  ['own mode: other\'s bot blocked'] = function(t)
    check(t, F.requester(), F.view{owner='acct:B'}, {pool='own', protect=false}, nil, false, 'not-yours') end,
  ['own mode: own bot allowed'] = function(t)
    check(t, F.requester(), F.view{owner='acct:A'}, {pool='own', protect=false}, nil, true, 'ok') end,
  ['own mode: unowned bot allowed'] = function(t)
    check(t, F.requester(), F.view(), {pool='own', protect=true}, nil, true, 'ok') end,
  ['own mode: home of requester allowed'] = function(t)
    check(t, F.requester(), F.view{homeOf='acct:A', owner='acct:B'}, {pool='own', protect=true}, nil, true, 'ok') end,
  ['downed requester may still switch'] = function(t)
    local req = F.requester{alive=false, conscious=false, dead=true}
    check(t, req, F.view(), nil, nil, true, 'ok') end,
  ['isFree: free bot'] = function(t) t.eq(rules.isFree(F.view(), TOG, 'acct:A'), true) end,
  ['isFree: controlled/dead/unconscious/removed/non-AI/non-crew are not'] = function(t)
    for _, o in ipairs{ {controller='acct:B'}, {alive=false}, {conscious=false}, {removed=true}, {isAI=false}, {crew=false} } do
      t.eq(rules.isFree(F.view(o), TOG, 'acct:A'), false)
    end end,
  ['isFree: respects toggles'] = function(t)
    t.eq(rules.isFree(F.view{homeOf='acct:B'}, TOG, 'acct:A'), false)
    t.eq(rules.isFree(F.view{homeOf='acct:B'}, {pool='shared', protect=false}, 'acct:A'), true) end,
  ['every reason has a [CrewSwap] message'] = function(t)
    for _, r in ipairs{'inactive','round','joining','spectating','traitor','dialogue','cooldown','invalid','taken','unavailable','not-yours','nohome'} do
      local m = rules.message(r, 2)
      t.ok(m:sub(1, 11) == '[CrewSwap] ', r); t.ok(#m > 12, r)
    end end,
  ['cooldown message includes seconds'] = function(t) t.ok(rules.message('cooldown', 2):find('2', 1, true)) end,
  ['cooldown messages differ per seconds'] = function(t) t.ok(rules.message('cooldown', 2) ~= rules.message('cooldown', 1)) end,
}

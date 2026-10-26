local registry = require('crewswap.core.registry')

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

return {
  ['bind and lookup'] = function(t)
    local R = registry.new()
    t.eq(R:sidOf(7), nil, 'unbound')
    R:bind(7, 'abc')
    t.eq(R:sidOf(7), 'abc')
    t.eq(R.bySession[7], 'abc')
    local rec = R:record('abc')
    t.ok(rec ~= nil, 'record created')
    t.ok(R:record('abc') == rec, 'record reused')
    t.ok(R.chars['abc'] == rec)
  end,
  ['prune drops dead session ids'] = function(t)
    local R = registry.new()
    R:bind(1, 'a'); R:bind(2, 'b'); R:bind(3, 'c')
    R:record('b').last = 'acct:B'
    R:prune({ 1, 3 })
    t.eq(R:sidOf(1), 'a'); t.eq(R:sidOf(2), nil); t.eq(R:sidOf(3), 'c')
    t.eq(R.chars['b'].last, 'acct:B', 'records survive a prune')
  end,
  ['encode omits nils'] = function(t)
    local m = registry.encodeAttrs({ last = 'acct:A', wbal = 250 })
    t.eq(m.crewswap_last, 'acct:A')
    t.eq(m.crewswap_wbal, '250')
    t.eq(type(m.crewswap_wbal), 'string', 'numbers become strings')
    t.eq(count(m), 2, 'only non-nil fields')
    t.eq(count(registry.encodeAttrs({})), 0)
  end,
  ['encode lastAt'] = function(t)
    local m = registry.encodeAttrs({ lastAt = 1700000000 })
    t.eq(m.crewswap_lastat, '1700000000')
  end,
  ["decode turns '' into nil and numbers back"] = function(t)
    local r = registry.decodeAttrs({ crewswap_last = '', crewswap_owner = 'acct:O', crewswap_home = '',
      crewswap_wbal = '120', crewswap_wrd = '30', crewswap_lastat = '' })
    t.eq(r.last, nil); t.eq(r.home, nil); t.eq(r.lastAt, nil)
    t.eq(r.owner, 'acct:O')
    t.eq(r.wbal, 120); t.eq(type(r.wbal), 'number')
    t.eq(r.wrd, 30); t.eq(type(r.wrd), 'number')
  end,
  ['round trip of record'] = function(t)
    local rec = { last = 'acct:A', owner = 'acct:O', home = 'acct:H', wbal = 5000, wrd = 25, lastAt = 1700000123 }
    local back = registry.decodeAttrs(registry.encodeAttrs(rec))
    for k, v in pairs(rec) do t.eq(back[k], v, k) end
    t.eq(type(back.lastAt), 'number', 'lastAt is a number again')
    t.eq(count(back), count(rec))
  end,
  ['round trip of partial record'] = function(t)
    local back = registry.decodeAttrs(registry.encodeAttrs({ owner = 'acct:O' }))
    t.eq(back.owner, 'acct:O'); t.eq(count(back), 1)
  end,
  ['campaign element round trip'] = function(t)
    local m = registry.campaignElement({ campaignGuid = 'ffee', modVersion = '0.1.9' })
    t.eq(m.campaignguid, 'ffee'); t.eq(m.modversion, '0.1.9')
    local s = registry.parseCampaignElement(m)
    t.eq(s.campaignGuid, 'ffee'); t.eq(s.modVersion, '0.1.9')
    local e = registry.parseCampaignElement({ campaignguid = '', modversion = '' })
    t.eq(e.campaignGuid, nil); t.eq(e.modVersion, nil)
  end,
}

local codec = require('crewswap.core.statecodec')
local F = require('fakes')

local function roundTrip(entries)
  local b = F.buffer()
  codec.encode(b, entries)
  local out = codec.decode(b)
  return out, b
end

return {
  ['empty list round trip'] = function(t)
    local out, b = roundTrip({})
    t.eq(#out, 0)
    t.eq(b.pos, #b.data, 'every written value was read')
  end,
  ['three entries round trip with controller names'] = function(t)
    local out, b = roundTrip({
      { id = 12, controller = 'Alice', free = false },
      { id = 40, controller = '', free = true },
      { id = 65535, controller = 'Carol', free = false },
    })
    t.eq(#out, 3)
    t.eq(out[1].id, 12); t.eq(out[1].controller, 'Alice'); t.eq(out[1].free, false)
    t.eq(out[2].id, 40); t.eq(out[2].controller, ''); t.eq(out[2].free, true)
    t.eq(out[3].id, 65535); t.eq(out[3].controller, 'Carol'); t.eq(out[3].free, false)
    t.eq(b.pos, #b.data, 'every written value was read')
  end,
  ['count is written first'] = function(t)
    local b = F.buffer()
    codec.encode(b, { { id = 1, controller = '', free = true }, { id = 2, controller = '', free = true } })
    t.eq(b.data[1].t, 'UInt16'); t.eq(b.data[1].v, 2)
    t.eq(#b.data, 1 + 2 * 3)
  end,
  ['nil controller is sent as empty string and free coerced to boolean'] = function(t)
    local out = roundTrip({ { id = 7 } })
    t.eq(out[1].controller, ''); t.eq(out[1].free, false)
  end,
}

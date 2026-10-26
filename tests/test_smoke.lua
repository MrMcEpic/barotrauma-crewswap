return { ['build module loads and has expectations'] = function(t)
  local b = require('crewswap.shared.build')
  t.eq(b.EXPECT_GAME, '1.13.4'); t.eq(b.EXPECT_LUACS, '85ded59'); t.ok(type(b.BUILD) == 'string')
end }

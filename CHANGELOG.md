# Changelog

All notable changes to CrewSwap are listed here. Versions follow the `modversion` of the content
package. The full, more detailed changelog lives in the
[documentation](https://mrmcepic.github.io/barotrauma-crewswap/book/changelog.html).

## [0.9.0] - beta

First public release.

**Beta status.** All server-side logic is covered by unit tests and the in-game self-test, and the
server side passed an automated 18-scenario run against a real dedicated server. **Live switching
between two or more players has not yet been fully play-tested.** Please use it on campaigns you can
afford to restore from a backup, and report what you find.

Targets Barotrauma **1.13.4.x** and was built against **Lua for Barotrauma** (Workshop item
2559634234) at the commit recorded in `shared/build.lua`. Every player who wants to switch needs
client-side LuaCs; the server needs LuaCs installed server-side.

### Added

- Switch between crew members in a multiplayer campaign by clicking a row in the crew list,
  singleplayer-style. The body you leave becomes a working bot again and resumes its orders.
- Taken crew members are greyed out and labelled with the name of the player driving them.
- Admin settings, saved across restarts: **crew pool** (`shared` or `own`) and **home protection**
  (on by default).
- Keep playing after death by jumping into another free crew member; the round is held open for up
  to 2 minutes when every player is down but free crew remain.
- Non-home crew who die outside Permadeath come back next round instead of being deleted.
- Per-character wallets and salary; mission pay goes to the character each player is driving.
- Admin chat commands: `!crewswap status`, `pool`, `protect`, `owner` and `check`.

### Safety

- Game version gate: on any game version other than 1.13.4.x (or with sandboxed server Lua) the mod
  installs nothing and the campaign runs as vanilla. A different LuaCs build only logs a warning; the patch-install audit and
  runtime checks still guard it.
- The mod switches itself off if any patch fails to install or a required game API can't be read.
- End-of-round integrity check: a broken crew save is never written, and switching stays locked
  down until an admin runs `!crewswap check`.
- Vanilla's rolling save backups raised from 3 to 20.

### Known limitations

- Off in Ironman campaigns and in non-campaign game modes.
- See [Differences from vanilla](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/vanilla-differences.html)
  for the complete list.

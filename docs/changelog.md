# Changelog

All notable changes to CrewSwap are listed here. Versions follow the `modversion` of the content
package.

## 0.9.0 (beta)

First public release.

**Beta status.** All server-side logic is covered by unit tests and the in-game selftest
(23 checks), and the server side passed an automated 18-scenario run against a real dedicated
server. **Live switching between two or more players has not yet been fully play-tested.** Please
use it on campaigns you can afford to restore from a backup, and report what you find.

Targets Barotrauma **1.13.4.x** and was tested against **LuaCsForBarotrauma** (Workshop id
2559634234) at the commit recorded in `shared/build.lua`. Every player needs client-side LuaCs to
switch; the server needs LuaCs installed server-side.

### Features

- Switch between crew members in a multiplayer campaign by clicking a row in the crew list,
  singleplayer-style. The body you leave becomes a working bot again and resumes its orders.
- Taken crew members are greyed out and labelled with the name of the player driving them; crew you
  cannot take are dimmed.
- Two settings, changed in game by admins and saved across restarts:
  - **Crew pool**: `shared` (anyone can take any Free crew member) or `own` (you can take your own
    character, crew you hired while the pool was `own`, crew you claimed by playing them first,
    crew an admin gave you, and crew nobody has claimed yet).
  - **Home protection** (on by default): your own character can only be driven by you.
- When the character you are driving dies, jump straight into another Free crew member.
- The round is held open for up to 2 minutes when every player is down but Free crew remain.
- Non-home crew members who die outside Permadeath come back next round (with the vanilla skill
  penalty when the round saves) instead of being deleted.
- Money belongs to each character: bots keep their own wallets and salary through saves, restarts
  and switches. Mission pay at round end goes to the character each player is driving.
- Death effects (Permadeath, skill loss) apply to the character that died, not to whoever was
  driving it. In Permadeath, a player whose own character is permanently dead makes the next crew
  member they take their new character.
- Disconnecting hands your body to the AI; rejoining puts you back in the character you last played
  (protect off) or your own character.
- Admin chat commands: `!crewswap status`, `!crewswap pool shared|own`,
  `!crewswap protect on|off`, `!crewswap owner "<character>" "<player>"`, `!crewswap check`.
  Command messages never show in public chat (except when CrewSwap is off because of a version
  mismatch).

### Safety

- Version gate: on any other game version (or with sandboxed server Lua) the mod installs nothing
  and the campaign runs as vanilla. A different LuaCs build only logs a warning; the patch-install
  audit and runtime checks below still guard it.
- The mod switches itself off if any patch fails to install, a module fails to load, a player
  body spawns without AI, or the crew list or another required game API can't be read.
- Integrity check before and after vanilla saves the crew: on a failure the save is not written, the
  campaign is reloaded from the last good save, and switching and new rounds stay off until an admin
  runs `!crewswap check`.
- Vanilla's rolling save backups raised from 3 to 20.
- All CrewSwap data is stored inside the vanilla save (plus a recovery mirror file next to it), so a
  save always loads with the mod off.

### Known limitations

- CrewSwap is off in **Ironman** campaigns and in non-campaign game modes.
- `RetainExperienceForNewCharacter` is disabled while CrewSwap is active.
- Player bodies are AI characters, so player attacks are not written to the server's attack log.
- On **save-and-quit**, mission pay goes to the players' own characters, and a bot that died that
  round keeps the inventory saved from its corpse.
- The camera snaps on a switch (as with vanilla bot takeover); there is no transition.
- See [Differences from vanilla](guide/vanilla-differences.md) for the complete list.

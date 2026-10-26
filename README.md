# CrewSwap

**Switch between your crew in Barotrauma multiplayer campaigns, the way you can in singleplayer.**

CrewSwap is a Lua mod for [Barotrauma](https://barotraumagame.com/) that lets players in a multiplayer
campaign take control of any free bot crew member by clicking their row in the crew list. Hand a bot
back, hop into the medic when someone needs patching up, or jump into another crew member when your
character goes down.

- Website: <https://mrmcepic.github.io/barotrauma-crewswap/>
- Documentation: <https://mrmcepic.github.io/barotrauma-crewswap/book/>
- Download: [GitHub Releases](https://github.com/MrMcEpic/barotrauma-crewswap/releases)
- Steam Workshop (link coming soon)

> [!WARNING]
> **CrewSwap 0.9.0 is a beta.** All of the server-side logic is covered by unit tests and passed an
> 18-scenario automated test run on a real dedicated server, but live switching with two or more human
> players has **not** been fully play-tested yet. Expect rough edges, keep backups of campaigns you care
> about, and please [open an issue](https://github.com/MrMcEpic/barotrauma-crewswap/issues) if something
> behaves oddly.

## A note on how this was made

CrewSwap was built with AI assistance (Claude), under the direction and review of a real software
engineer. It started as a mod for personal use with friends and is shared here in case others enjoy
it too. If you're not comfortable using AI-assisted mods, no hard feelings at all; you don't have to
use it.

## Features

- **Click to switch.** Click a crew member's row in the crew list to take control of them. Rows
  that someone else is playing are greyed out and labelled with that player's name. Dragging rows
  and the order buttons work as usual.
- **Shared pool or own crew.** In `shared` mode any free crew member can be taken. In `own` mode
  you can take your own character, crew you own (hired in `own` mode, claimed by playing them
  first, or assigned by an admin), and crew nobody has claimed yet.
- **Home protection** (on by default). Each player's own character stays theirs: while you are
  playing someone else, other players cannot take your home character.
- **Keep playing after death.** When the character you are driving dies, pick another free crew
  member from the crew list instead of spectating.
- **Per-character wallets.** Money belongs to the character, not the player; round-end pay goes
  to the character you were driving (on save-and-quit it goes to each player's own character).
- **Dead crew come back.** Outside Permadeath, crew members who aren't anyone's own character are
  no longer deleted when they die; they return as bots at the start of the next round (with
  vanilla's death penalty after a saved round).
- **Safety first.** Version check on start-up (the mod switches itself off on a game version it
  was not built for, and warns on a different LuaCs build), a patch-install audit, an end-of-round integrity check that
  refuses to write a broken save, a lockdown mode, and 20 kept campaign backups instead of 3.
- **Ironman-aware.** CrewSwap stays off in Ironman campaigns.
- **Pure Lua, no C#.** The package ships no C#, so nobody gets a "this mod wants to run code"
  prompt. The server half does need LuaCs's server Lua to stay unsandboxed (LuaCs's C# run policy
  left at its default).

See [Differences from vanilla](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/vanilla-differences.html)
for every behaviour change while the mod is active.

## Requirements

| | Needs |
|---|---|
| Game | Barotrauma **1.13.4.x** |
| Server | [Lua for Barotrauma (LuaCsForBarotrauma)](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234) installed server-side (tested against **the build at commit `85ded59`**; other builds get a start-up warning, see [Requirements](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/requirements.html)), with its C# run policy left at its default, plus CrewSwap |
| Every player | **Client-side** Lua for Barotrauma, plus CrewSwap (downloaded automatically from the server, or subscribed on the Workshop) |

CrewSwap compares the server's LuaCs commit at start-up. LuaCs updates through the Workshop, so
on any other LuaCs build CrewSwap logs a `[CrewSwap] WARNING: built for LuaCs ...` line and keeps
going; its patch-install audit and runtime checks still switch it off if something
breaks. A different **game** version does switch it off (`OFF: version mismatch`) until an
updated release is out.

Players without client-side LuaCs can still join and play normally; they just can't switch, and
CrewSwap tells them so in chat.

## Quick install

Full instructions: [Server installation](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/server-install.html)
and [Client installation](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/client-install.html).

### Server (dedicated)

1. Install Lua for Barotrauma on the server, following the server instructions on
   [its Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234).
2. Download `CrewSwap-0.9.0.zip` from [Releases](https://github.com/MrMcEpic/barotrauma-crewswap/releases)
   and unzip it into the server's `LocalMods` folder, so you end up with `LocalMods/CrewSwap/filelist.xml`.
3. Enable the package: add `<package path="LocalMods/CrewSwap/filelist.xml"/>` under
   `<regularpackages>` in the server's `config_player.xml` (or enable it in your hosting panel, if it manages that file).
4. Start the server and look for these lines in the console (the two numbers after
   `patches installed` must match, and there must be no `[CrewSwap] FAIL` or `OFF` line):

   ```text
   [CrewSwap] server loaded build 0.9.0-beta
   [CrewSwap] running on game 1.13.4.x, LuaCs ...
   [CrewSwap] save folder: ...
   [CrewSwap] admin: config: pool=shared protect=on (defaults)
   [CrewSwap] modules loaded: ...
   [CrewSwap] patches installed: N/N
   [CrewSwap] active: false
   ```

   `active: false` is normal here: no campaign is loaded yet. After you load a multiplayer campaign
   and start a round, the console should show `[CrewSwap] round start, active: true`.

### Players

1. Install **client-side** Lua for Barotrauma as described on
   [its Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234). Keep the
   Lua for Barotrauma Workshop package itself **disabled** in your mod list, as that page explains.
2. Join a CrewSwap server; the mod downloads automatically. (Or subscribe to CrewSwap on the Workshop.)
3. Optional check: press F3 in game to open the console and look for
   `[CrewSwap] client loaded build 0.9.0-beta`.

## Quick usage

- Open the crew list and **click a crew member's row** to take control of them.
- Greyed rows with a name label are being played by someone else. A dimmed name is a crew member
  you can't take right now, such as another player's home character while home protection is on.
- There's a 3 second cooldown between switches.
- New players can switch once they have spawned in the campaign for the first time.
- Disconnecting hands your current body back to the AI; it isn't killed by the disconnect timer.

More in [Playing with CrewSwap](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/playing.html).

## Admin commands

Type these in chat. They are hidden from public chat (except when CrewSwap is off for a version mismatch; see [Troubleshooting](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/troubleshooting.html)). `status` works for everyone; the rest
need an admin.

| Command | What it does |
|---|---|
| `!crewswap` or `!crewswap status` | Shows whether CrewSwap is active, the crew pool mode and home protection. |
| `!crewswap pool shared` | Any free crew member can be taken (default). |
| `!crewswap pool own` | Players can only switch into their own character, crew they own (hired in `own` mode, claimed by playing them first, or assigned by an admin) and crew nobody has claimed. |
| `!crewswap protect on` | Players' own characters cannot be taken by others (default). |
| `!crewswap protect off` | Players' own characters can be taken while they are free. |
| `!crewswap owner "<character>" "<player>"` | Makes a connected player the owner of a crew member (names match case-insensitively, a unique prefix is enough). |
| `!crewswap check` | Re-runs the integrity check and lifts an integrity lockdown if it passes (it can't turn CrewSwap back on after a FAIL). |

Settings are saved per server in `<save folder>/CrewSwap/config.txt`. Details in
[Admin commands and settings](https://mrmcepic.github.io/barotrauma-crewswap/book/guide/admin.html).

## Building from source

```sh
lua5.2 tests/run.lua           # run the unit tests (from the repository root)
tools/package.sh 0.9.0 beta    # writes dist/CrewSwap-0.9.0.zip with BUILD 0.9.0-beta
mdbook serve                   # preview the documentation (book.toml is at the root)
```

Server and clients compare their build string, so everyone must run a copy made from the same
package. See [Contributing](https://mrmcepic.github.io/barotrauma-crewswap/book/contributing.html) and the
[Architecture](https://mrmcepic.github.io/barotrauma-crewswap/book/architecture/overview.html) section.

## Licence

CrewSwap is free software, licensed under the
[GNU Affero General Public License v3.0 only](LICENSE) (AGPL-3.0-only).

## Credits

- [Barotrauma](https://barotraumagame.com/) by FakeFish and Undertow Games, published by Daedalic
  Entertainment. CrewSwap is an unofficial fan mod and is not affiliated with or endorsed by them.
- [LuaCsForBarotrauma](https://github.com/evilfactory/LuaCsForBarotrauma) by evilfactory and
  contributors, which makes Lua mods like this possible.
- Inspired by **Multiplayer Crew Manager** by oiltanker, prior art for multiplayer crew control.
  No code was ported from it; CrewSwap is a separate implementation.

# Introduction

**CrewSwap** is a Barotrauma mod that brings singleplayer-style crew switching to the
**multiplayer campaign**. Open the crew list, click a bot's row, and you are now playing that
crew member. The character you left goes back to being a bot and carries on with whatever it
was doing. Over a campaign, every player can drop in and out of any free crew member, level
several characters, and never lose or duplicate one of them along the way.

Vanilla multiplayer gives each player exactly one character. Outside of the take-over prompt
after a permanent death, the only built-in way to control a bot is a cheat command, and that one
corrupts the campaign at the next save. CrewSwap
does it properly: the server decides every switch, and before the game saves, everything goes
back into the shape vanilla expects.

> **Beta: version 0.9.0**
>
> All of CrewSwap's server-side logic is covered by an automated unit-test suite
> and has passed an 18-scenario automated test run on a real dedicated server. What has
> **not** been fully tested yet is live switching with two or more real players on real
> clients. Expect rough edges. Before you trust it with a campaign you care about, read
> [Troubleshooting](guide/troubleshooting.md) so you know how to load a backup. Please report
> anything odd on the
> [issue tracker](https://github.com/MrMcEpic/barotrauma-crewswap/issues).

## Features

- **Click to switch.** Click a free crew member's row in the crew list to take control of them.
  Rows that someone else is playing are greyed out and labelled with that player's name.
  Dragging rows and the order buttons work as usual.
- **Shared pool or own crew.** In *shared* mode (the default), anyone can take any free crew
  member. In *own* mode you can take your own character, crew you own (hired in own
  mode, claimed by playing them first, or assigned by an admin) and crew nobody has claimed yet
  (taking one claims it).
- **Home protection** (on by default). Your own character can only be played by you. Turn it off
  and your character joins the pool while you are playing someone else.
- **Jump in on death.** When the character you are playing dies, pick another free crew member
  straight away instead of waiting for the respawn shuttle.
- **Per-character wallets.** Money belongs to the character, not to the player, and switching
  never moves it. Bots keep their wallets through saves.
- **Crew come back.** Outside Permadeath, a crew member who dies is no longer deleted for good
  the way vanilla deletes dead bots. They return as a bot at the start of the next round (after a
  saved round, with vanilla's usual death penalty to their skills).
- **Fair round-end pay.** Mission pay and round-end rewards go to the character each player is
  playing when the round ends (on save-and-quit it goes to each player's own character
  instead).
- **Safety first.** CrewSwap checks the crew before every save and refuses to write a save that
  would lose or duplicate a character. It keeps 20 rolling backups per campaign, and it switches
  itself off if the game version is not one it was built for (a different LuaCs build gets a
  warning, and every patch must still install cleanly or CrewSwap switches itself off).
- **Admin chat commands.** `!crewswap status`, `pool`, `protect`, `owner` and `check`, typed in
  game chat. See [Admin commands](guide/admin.md).
- **Stays out of the way.** CrewSwap only runs in multiplayer campaigns. It stays off in
  sandbox, mission and PvP rounds and in Ironman campaigns, and with nobody switching, a
  campaign plays just like vanilla.

CrewSwap is written in pure Lua on top of
[Lua for Barotrauma](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234)
(LuaCs) and ships no C# code, so players never see a "run C# code" prompt because of it. The
client half runs sandboxed. The server half needs LuaCs's server Lua left unsandboxed (the
default C# run policy).

## Where to start

| You are... | Read |
|---|---|
| A player joining a CrewSwap server | [Requirements](guide/requirements.md), [Client install](guide/client-install.md), [Playing](guide/playing.md) |
| Running a dedicated server | [Requirements](guide/requirements.md), [Server install](guide/server-install.md), [Admin commands](guide/admin.md) |
| Curious about what changes | [Differences from vanilla](guide/vanilla-differences.md) |
| Something went wrong | [Troubleshooting](guide/troubleshooting.md), [FAQ](guide/faq.md) |
| A developer | [Architecture overview](architecture/overview.md), [Contributing](contributing.md) |

## A note on how this mod was made

CrewSwap was built with AI assistance (Anthropic's Claude), directed and reviewed by a real
software engineer. It started as a personal project for playing Barotrauma with friends, and
it is shared here in case other crews enjoy it too.

If you'd rather not use AI-assisted mods, no hard feelings. You don't have to use it.

## Licence

CrewSwap is free software, licensed under the
[GNU Affero General Public License v3.0 only](https://www.gnu.org/licenses/agpl-3.0.html)
(AGPL-3.0-only). The source code is on
[GitHub](https://github.com/MrMcEpic/barotrauma-crewswap). If you run a modified version on a
server that other people play on, the AGPL asks you to offer them your modified source.

Barotrauma is a trademark of its respective owners. CrewSwap is a fan-made mod and is not
affiliated with or endorsed by the game's developers or publishers.

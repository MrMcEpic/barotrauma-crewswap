# FAQ

### Does every player need LuaCs?

Every player who wants to **switch** needs client-side LuaCs. Players without it can still join
and play their own character as normal. They just can't switch, and they get one chat message
telling them how to turn it on. The server needs server-side LuaCs. See
[Requirements](requirements.md).

### Do I have to subscribe to CrewSwap on the Workshop?

No. The server sends CrewSwap to you when you join. Subscribing on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3827463751) is optional.

### Will it ask me to enable C#?

Not because of CrewSwap. It's pure Lua and ships no C# code; its client half runs sandboxed.

### Can I add CrewSwap to a campaign that's already running?

Yes. CrewSwap gives every crew member a stable id the first time it saves the campaign, then
carries on from there. Before that point, vanilla rules applied. For example, bots that died
earlier are already gone.

### Can I remove it again?

Yes. Finish on a saved round end (a level transition or save-and-quit), stop the server and
disable the mod. Before every save, CrewSwap puts every player back in their own character, so
the save is in vanilla shape and vanilla loads it normally. Vanilla ignores CrewSwap's extra
data. From then on vanilla rules apply again: dead bots are deleted, and bots' wallets aren't
kept. See [Server install](server-install.md#removing-crewswap).

### What happens when Barotrauma or LuaCs updates?

**Barotrauma:** CrewSwap notices the new game version at server start and **switches itself
off**. Nothing is patched, and the campaign plays as vanilla until a matching CrewSwap release is
out. Saves made meanwhile are plain vanilla saves; when CrewSwap is back it restores its records
from its recovery file next to the save, apart from any crew it can't match unambiguously. See
[Troubleshooting](troubleshooting.md#crewswap-is-off-for-this-game-version).

**LuaCs:** a different LuaCs build only gets a warning in the server console, and CrewSwap keeps
running. If the update breaks something CrewSwap relies on, a patch fails to install or a
start-up or runtime check fails, and CrewSwap [switches itself off](troubleshooting.md#crewswap-switched-itself-off-fail).
See [Different LuaCs build](troubleshooting.md#different-luacs-build).

### Does it work with Ironman?

Not yet. CrewSwap stays off in Ironman campaigns and says so in chat once per round.

### Does it work in sandbox, mission or PvP mode?

No. CrewSwap is for the multiplayer campaign only.

### Can I control outpost NPCs, escorts, monsters or the other team?

No. Only your own crew.

### Can I use a key to cycle through characters?

Not in this version. Switching is by clicking the crew list.

### Can I get a free rename or move money by switching?

No. Switching gives no rename, and money stays in each character's own wallet.

### Who gets the mission pay?

The character each player is playing when the round ends. On save-and-quit, the players' own
characters get it instead. See [Playing](playing.md#round-end-money-and-xp).

### My own character was idle all round. Does it fall behind?

Your idle character is crew like any bot. It gets mission XP and round-end talent effects the
way bots do.

### A bot died. Is it gone?

Outside Permadeath, no. It comes back as a bot at the start of the next round, with vanilla's
usual death penalty if the round was saved. In Permadeath, every death is permanent.

### What if I disconnect while playing a bot?

The bot goes back to the AI straight away and keeps working. When you rejoin, you go back into
your own character (or, with home protection off, into the character you last played), if it's
Free.

### Can two players grab the same bot at once?

The server decides, and the first request wins. The other player gets
`[CrewSwap] Someone else is already playing that character.`

### Is it compatible with other mods?

Most content mods (items, subs, creatures) should be fine. Be careful with mods that also
change the crew list, character control, or how the campaign saves its crew. Don't combine
CrewSwap with another crew-switching mod such as *Multiplayer Crew Manager*: the two would
fight over the same save data.

### Does it need cheats or disable achievements?

No. CrewSwap doesn't use the `control` command or turn on cheats.

### Is it safe for my campaign?

CrewSwap is built around not losing or duplicating characters. It checks the crew before every
save, refuses to write a save that fails the check, and keeps 20 backups. That said, it is
**beta**: live switching with several real players hasn't been fully tested yet. Back up your
`Multiplayer` saves before you start, and read [Troubleshooting](troubleshooting.md) so you
know how to recover.

### Why is the server stuck in the lobby?

CrewSwap probably locked down after a failed integrity check. An admin should run
`!crewswap check`. See [Integrity alarm](troubleshooting.md#integrity-alarm-and-lockdown).

### Can I host from the game instead of a dedicated server?

CrewSwap is built and tested for dedicated servers. In-game hosting hasn't been tested. See
[Server install](server-install.md#hosting-from-the-game-client).

### Was this made with AI?

Yes. CrewSwap was built with AI assistance (Claude), directed and reviewed by a real software
engineer. It was made for playing with friends and is shared in case others enjoy it. If you'd
rather not use AI-assisted mods, that's completely fine. You don't have to use it.

### Where do I report bugs?

On [GitHub](https://github.com/MrMcEpic/barotrauma-crewswap/issues). See
[Reporting a problem](troubleshooting.md#reporting-a-problem) for what to include.

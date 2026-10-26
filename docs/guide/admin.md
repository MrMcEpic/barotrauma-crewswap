# Admin commands

You control CrewSwap with chat commands typed in the normal in-game chat box. Some notes
before the list:

- **Nobody else sees the commands.** CrewSwap swallows every `!crewswap` command (the word
  `!crewswap` on its own or followed by a space), from anyone, so it never appears in public chat.
  A message like `!crewswapper` isn't a command and shows as normal. The one exception: when
  CrewSwap is off because of a version mismatch (a different game version, sandboxed
  server Lua, or an unreadable game version), its chat commands are not loaded, so
  `!crewswap` messages show in chat and get no reply. Check the server console for
  `OFF: version mismatch` (see [Troubleshooting](troubleshooting.md)).
- **Replies are private.** Only the sender sees them. The exceptions are a settings change,
  which is announced to everyone, and a failed `!crewswap check`, whose problem count is
  announced to everyone.
- **Who counts as an admin:** any client with the vanilla **Manage settings** permission
  (the Admin preset includes it). Anyone can use `!crewswap status`. Everything else is
  admin-only. Anyone else gets `[CrewSwap] Only admins can change CrewSwap settings.`
- Commands and their keywords are case-insensitive. Put names that contain spaces in
  `"double quotes"`. An unclosed quote gets the general usage line back.

## Summary

```text
!crewswap status | pool shared|own | protect on|off | owner "<character>" "<player>" | check
```

| Command | Who | What it does |
|---|---|---|
| `!crewswap` or `!crewswap status` | Everyone | Shows whether CrewSwap is active and the current settings |
| `!crewswap pool shared` | Admin | Any Free crew member can be taken (default) |
| `!crewswap pool own` | Admin | Players can only take their own character, crew they own, and crew nobody has claimed yet |
| `!crewswap protect on` | Admin | Players' own characters can only be played by them (default) |
| `!crewswap protect off` | Admin | Players' own characters join the pool while their owner plays someone else |
| `!crewswap owner "<character>" "<player>"` | Admin | Gives a crew member to a player (for `own` mode) |
| `!crewswap check` | Admin | Runs the integrity check now and lifts an integrity lockdown if it passes (with a FAIL also on record, the lobby hold is released, so rounds can start again, but CrewSwap stays off (switching disabled) until the FAIL is fixed and the server restarted) |

An admin who types a malformed command gets a usage line back (other players get the
admin-only message), for example:

```text
[CrewSwap] Usage: !crewswap pool shared|own
[CrewSwap] Usage: !crewswap protect on|off
[CrewSwap] Usage: !crewswap owner "<character>" "<player>"
[CrewSwap] Usage: !crewswap status | pool shared|own | protect on|off | owner "<character>" "<player>" | check
```

## `!crewswap status`

```text
[CrewSwap] CrewSwap is active. Crew pool: shared. Home protection: on.
```

- `inactive right now` in place of `active` means CrewSwap is loaded but not running. This is
  normal before a campaign is loaded, in a non-campaign round, or under Ironman.
  It also shows during an integrity lockdown.
- If CrewSwap has switched itself off, status gives the reason instead:

  ```text
  [CrewSwap] CrewSwap is off: <reason>. Fix it and restart the server; !crewswap check cannot turn it back on.
  ```

  See [Troubleshooting](troubleshooting.md#crewswap-switched-itself-off-fail).

## `!crewswap pool shared|own`

Sets who can take which bots. Everyone sees one of:

```text
[CrewSwap] Crew pool is now "shared": any Free crew member can be taken.
[CrewSwap] Crew pool is now "own": you can only switch into characters you hired or that nobody has claimed.
```

**`shared`** (default): any Free crew member, apart from other players' characters while home
protection is on.

**`own`:** a player may take:

- their own character
- bots they own
- bots that nobody owns yet. Taking one **claims** it, and the console logs `switch: <player> claimed <character>`.

Ownership comes from three places:

1. **Hiring while the pool is `own`.** The hirer owns the new crew member. The console logs
   `admin: <player> hired <character> and now owns them`. Hires made while the pool was
   `shared` are not owned. Once the pool is `own`, whoever plays them first claims them.
2. **First play**, for anything unowned, as above.
3. **`!crewswap owner`**, below.

A replacement character bought in Permadeath becomes the buyer's own character, not a hire.

In `own` mode another player's own character is never takeable. The only exception: with
protection off, an admin has made you its owner with `!crewswap owner` (see the note below).

## `!crewswap protect on|off`

```text
[CrewSwap] Home protection is now on: players' own characters cannot be taken by others.
[CrewSwap] Home protection is now off: players' own characters can be taken when they are Free.
```

- **On** (default): each player's own character can only be played by that player.
- **Off:** while a player is playing someone else, their own character is Free for others.
  This also changes [round start and rejoin](playing.md#round-start): players go back into
  the character they last played, if it's Free.

Changing either setting takes effect immediately. The crew list updates for everyone, and
nobody is pushed out of the character they're currently playing.

If the setting can't be written to disk, you also see
`[CrewSwap] Could not save the setting to disk; it applies until the server restarts.`

## `!crewswap owner "<character>" "<player>"`

Makes a player the owner of a crew member. This matters in `own` pool mode.

```text
!crewswap owner "Kim Lee" "Alice"
[CrewSwap] Kim Lee now belongs to Alice.
```

- **Names are matched case-insensitively:** first an exact match, then a unique prefix. So
  `!crewswap owner kim ali` works if only one crew member starts with "kim" and only one
  player starts with "ali".
- The character must be **in the current round's crew**, and the player must be **connected**.
- CrewSwap must be active (a campaign round is running).
- Ownership is saved with the character in the campaign save.

Possible replies:

| Reply | Meaning |
|---|---|
| `[CrewSwap] No crew member named "<name>".` | No match. Check the spelling, or wait until that character has spawned. |
| `[CrewSwap] More than one crew member matches "<name>".` | Type more of the name. |
| `[CrewSwap] No connected player named "<name>".` | The player isn't online. |
| `[CrewSwap] More than one player matches "<name>".` | Type more of the name. |
| `[CrewSwap] That crew member has no CrewSwap record yet.` | Rare. Try again after the next save. |
| `[CrewSwap] CrewSwap is off right now.` | Only works while CrewSwap is active. |

> You *can* give a player's own character to someone else this way. With protection off and the
> pool set to `own`, the new owner can then take it while it's Free. That is usually not what
> you want.

## `!crewswap check`

Runs CrewSwap's **integrity check** on the loaded campaign right away. It checks that every
crew member is stored exactly once and that nobody has gone missing (see
[Troubleshooting](troubleshooting.md#integrity-alarm-and-lockdown)).

| Reply | Meaning |
|---|---|
| `[CrewSwap] The integrity check passed.` | All good. If an integrity lockdown was in force, it's lifted: switching works and rounds can start again. |
| `[CrewSwap] The integrity check failed. See the server console for the details.` | Still a problem. The console lists each one, and everyone sees `[CrewSwap] Integrity check failed (manual): N problem(s), see the server console.` |
| `[CrewSwap] The integrity check passed, but CrewSwap is still locked down (see the server console).` | The lockdown isn't (only) an integrity one: CrewSwap has switched itself off with a `FAIL` (a patch that didn't install, a module that didn't load, a failed audit). Any integrity alarm is cleared, but CrewSwap stays off until the problem is fixed and the server restarted. |
| `[CrewSwap] The integrity check is not available.` | The safety module didn't load. Look for a `FAIL` line in the console. |

`!crewswap check` **only lifts integrity lockdowns.** It can't turn CrewSwap back on after a
`FAIL` (a patch that didn't install, a module that didn't load). If an integrity alarm and a
`FAIL` are both in force, a passing check clears the integrity alarm only, replies with the
"still locked down" line above, and CrewSwap stays off.

## The config file

The `pool` and `protect` settings are **server-wide** (shared by every campaign on the server).
They are saved to:

```text
<save folder>/CrewSwap/config.txt
```

`<save folder>` is the path printed at start-up as `[CrewSwap] save folder: <path>`. It's the
server's Barotrauma data folder, the one that also holds `Multiplayer/`. The file is plain
text:

```text
pool=shared
protect=on
```

- Values are lowercase (`shared`, `own`, `on`, `off`); anything else falls back to the default.
  (The chat commands, by contrast, are case-insensitive.)
- **Defaults:** `pool=shared`, `protect=on`. If the file is missing, or a line is unreadable,
  the default is used for that setting.
- CrewSwap reads the file **once, at server start**. The console shows
  `[CrewSwap] admin: config: pool=shared protect=on (from file)`, or `(defaults)` when there is
  no file. To edit it by hand, stop the server first. Otherwise just use the chat commands,
  which write the file for you.

## Other files in the save folder

| Path | What it is |
|---|---|
| `<save folder>/CrewSwap/config.txt` | The settings above |
| `<save folder>/CrewSwap/selftest` | If this (empty) file exists, CrewSwap runs its in-game self-test at start-up (see [Testing](../architecture/testing.md)). Delete it afterwards. |
| `<save folder>/CrewSwap/force-integrity-fail` | A developer test switch that makes every integrity check fail (so saves are blocked and CrewSwap locks down). Never leave it in place; delete it if present. |
| `<save folder>/Multiplayer/<campaign>_CrewSwap.xml` | A recovery copy of CrewSwap's per-character data, written next to each campaign save. Leave it alone. The save itself is the source of truth. |

CrewSwap's per-character data (ids, owner, last player, bot wallets) is stored **inside the
campaign save**, so it is saved, reverted and backed up together with vanilla's data. See
[Persistence](../architecture/persistence.md).

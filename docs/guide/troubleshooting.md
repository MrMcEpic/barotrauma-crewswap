# Troubleshooting

Every message CrewSwap prints starts with `[CrewSwap]`, both in chat and in the server
console. When something looks wrong, check the **server console** first.

## Quick lookup

| You see | Go to |
|---|---|
| `CrewSwap is off until it's updated for this game version` | [Version mismatch](#crewswap-is-off-for-this-game-version) |
| `CrewSwap is off until an admin restarts the server` | [Switched itself off](#crewswap-switched-itself-off-fail) |
| `Integrity check failed (...)`, `Integrity check failed: ...` or `The round can't start: an integrity check failed` | [Integrity alarm](#integrity-alarm-and-lockdown) |
| `This server uses CrewSwap. Turn on client-side LuaCs ...` | [Client LuaCs missing](#client-side-luacs-missing) |
| `Your copy of CrewSwap is out of date ...` | [Out-of-date client](#out-of-date-client) |
| `CrewSwap is off in Ironman campaigns.` | [Ironman](#ironman) |
| `WARNING: built for LuaCs ...` (console) | [Different LuaCs build](#different-luacs-build) |
| Clicking rows does nothing | [Clicks do nothing](#clicking-a-row-does-nothing) |

## CrewSwap is off for this game version

**Chat**, at every round start:

```text
[CrewSwap] CrewSwap is off until it's updated for this game version (<reason>).
```

**Server console**, at start-up:

```text
[CrewSwap] OFF: version mismatch (<reason>)
```

There's no `patches installed` line after it. `<reason>` is one of:

| Reason | Meaning |
|---|---|
| `game 1.14.0.0` (for example) | The server runs a different Barotrauma version than this CrewSwap release was built for. |
| `server Lua is sandboxed` | C# is disabled for the server in LuaCs's settings. CrewSwap needs unsandboxed server Lua. |
| `version read failed: ...` | CrewSwap couldn't read the game version. (An unreadable LuaCs build only gives the warning in [Different LuaCs build](#different-luacs-build).) |

A different LuaCs build is **not** on this list: it only logs a warning (see
[Different LuaCs build](#different-luacs-build)).

In this state CrewSwap's chat commands are not loaded either: `!crewswap` messages (including
`!crewswap status`) show in public chat and get no reply. Check the server console for the
`OFF: version mismatch` line instead.

**Your campaign is safe.** In this state CrewSwap installs **no patches at all**, so the game
runs pure vanilla code. Vanilla writes the saves without CrewSwap's extra data (owners, last
players, bot wallets). CrewSwap's recovery file next to the save is left alone, and when a
matching CrewSwap version runs again it re-matches its records from that file. Crew it can't
match unambiguously (for example, two with the same name) start fresh. If fewer than half of the
crew can be matched, CrewSwap treats the recovery file as belonging to another campaign and starts
everyone fresh.

**To fix it:** install the CrewSwap release made for your game version. If none exists yet,
wait for one. For `server Lua is sandboxed`, set LuaCs's C# run policy on the server back to its
default.

> Don't just edit the expected versions in the mod's files to make the message go away. The
> version gate exists because each game update can change the code CrewSwap patches.
> [Contributing](../contributing.md) describes how a new version is checked properly.

## Different LuaCs build

**Server console**, at start-up:

```text
[CrewSwap] WARNING: built for LuaCs <expected>, running on <found>; continuing (patch audit and self-tests still guard)
```

`<found>` is `unknown` if the LuaCs build couldn't be read. CrewSwap was tested against one LuaCs
build (listed in [Requirements](requirements.md)), but LuaCs updates itself through the Workshop,
so a different build doesn't switch CrewSwap off. It keeps going, and the other checks still
protect the campaign: if any patch fails to install, or one of the start-up or runtime checks fails (the live crew-list check on the first campaign round, the AI-body audit, the required game API checks), CrewSwap
[switches itself off](#crewswap-switched-itself-off-fail) as usual. The optional in-game selftest
only reports problems in the console; it doesn't switch CrewSwap off. So "self-tests" in the
warning line means those always-on start-up and runtime checks, not the optional selftest.

If you see this warning and something misbehaves, put back the LuaCs build listed in
[Requirements](requirements.md) if you can, and include the warning line when you
[report it](#reporting-a-problem).

## CrewSwap switched itself off (FAIL)

**Chat**, when it happens and at every round start until the server restarts:

```text
[CrewSwap] CrewSwap is off until an admin restarts the server (see the server console).
```

**Server console:**

```text
[CrewSwap] FAIL: <reason>
```

`!crewswap status` also shows the reason (unless the failing module is CrewSwap's admin module
itself or one it depends on, in which case `!crewswap` gets no reply: read the `FAIL` line in
the console).

CrewSwap does this when it finds something it can't safely work around. Common reasons:

- `patch crewswap.<name> (...)`: a game method CrewSwap patches has changed. This usually means
  a game hotfix: the version gate accepts any 1.13.4.x revision, but a hotfix can still change
  a method.
- `loading crewswap.server.<module>: ...`: one of CrewSwap's files failed to load. A
  damaged or partial install is the usual cause.
- `non-AI body for <player>` (or `non-AI body (respawn) for <character>`): a player's body
  spawned, or respawned, without the AI it needs.
- `the crew list cannot be read: ...`: the first campaign round couldn't read the crew roster.
- Other start-up checks, for example `could not raise SaveUtil.MaxBackupCount to 20`,
  `MultiPlayerCampaign.GameOver is not accessible` or
  ``ImmutableHashSet`1 could not be registered``: the game or LuaCs build has changed. Treat
  these like a patch failure.

**Your campaign is safe.** Switching stops, and saves still carry every bit of CrewSwap data it
already had. No new switches happen and the save keeps its vanilla shape (the one exception: a
crew member with no CrewSwap id yet may be given one when a save is loaded; see
[Persistence](../architecture/persistence.md)).

**`!crewswap check` can't lift this.** That command only clears integrity lockdowns. If an
integrity alarm and a FAIL are both in force, a passing check clears the integrity alarm but
replies `[CrewSwap] The integrity check passed, but CrewSwap is still locked down (see the server
console).`. The lobby hold is released, so rounds can start again, but CrewSwap stays off
(switching disabled) until the FAIL is fixed and the server restarted.

**To fix it:**

1. Read the `FAIL` line.
2. If it looks like a one-off (for example a spawn check during an unusual round), restart
   the server and check the console for `patches installed: N/N` and no `FAIL` lines.
3. If it comes back, reinstall CrewSwap. If it still fails, please
   [report it](#reporting-a-problem) with the console lines.

## Integrity alarm and lockdown

At every saved round end (a level transition or save-and-quit), CrewSwap checks the crew twice
before the save is written. It checks that:

- no crew member is stored twice (as both a player character and a bot, or twice in one place)
- every crew member from the start of the round is still there, unless they died permanently
  (Permadeath), were fired, or were replaced on purpose (a vanilla "create new character", or a
  bot taking over as a Permadeath player's new character)
- CrewSwap's own records only refer to crew members that exist

It also checks each save as it's loaded, for the same crew member appearing twice.

### What you see

Every failed save-time or manual check first posts this to everyone (`<when>` is `pre-save` or
`post-save`; a manual `!crewswap check` uses `manual`, and the optional selftest's integrity
check uses `selftest`):

```text
[CrewSwap] Integrity check failed (<when>): <N> problem(s), see the server console.
```

After a round end:

```text
[CrewSwap] Integrity check failed: the round was not saved and the campaign was reloaded from the last good save. Switching and new rounds are off until an admin runs !crewswap check.
```

After loading a save (this check doesn't post the count line above; the console shows
`[CrewSwap] INTEGRITY FAIL (load): duplicate ...` lines and an `INTEGRITY ALARM:` line instead):

```text
[CrewSwap] Integrity check failed: this save has the same crew member twice. Switching and new rounds are off until an admin runs !crewswap check or loads a backup.
```

If anyone tries to start a round while it's locked:

```text
[CrewSwap] The round can't start: an integrity check failed. An admin must run !crewswap check.
```

The server console lists each integrity problem:

```text
[CrewSwap] INTEGRITY FAIL (<when>): <problem> <id> (<name>)
```

| Problem | Meaning |
|---|---|
| `duplicate` | The same crew member is stored more than once. |
| `missing` | A crew member from the start of the round is gone, without a permanent death or firing to explain it. |
| `moved` | A bot ended up stored as a player character, or the other way round. |
| `unknown` | CrewSwap has a record of a crew member that no longer exists. |

If there are no `INTEGRITY FAIL` lines, look for a `[CrewSwap] roundend: ... error: ...` line
(for example `roundend: restore error: ...` or `roundend: pre-save hook 1 error: ...`) or
`[CrewSwap] roundend: save blocked: a bot wallet could not be read` just before the alarm. The
save was blocked for that reason instead. What happened and the recovery are the same.

### What happened

The check failed **before** anything reached the disk, so CrewSwap **didn't write the save**.
It reloaded the campaign from the last good save, the same way vanilla handles a failed round.
**The round that just ended is lost, but nothing bad was saved.**

If the console shows `[CrewSwap] safety: INTEGRITY: reload failed: ...`, the automatic reload
didn't work: load a backup from the lobby as in step 3 below.

While locked down:

- switching is off
- no round can start, so the server stays in the lobby (vanilla would start the next round
  straight away)
- saves still keep all of CrewSwap's data

### What to do

1. An admin types **`!crewswap check`** in chat.
2. If it says `[CrewSwap] The integrity check passed.`, the lockdown is lifted. Start the round
   from the lobby as usual.
3. If it keeps failing, **load a backup:**
   - CrewSwap raises the game's rolling save backups from 3 to **20 per campaign**.
   - In the lobby, open the campaign load list, find this campaign's backups and pick an
     earlier one.
   - Run `!crewswap check` again, then start the round.
4. Please [report it](#reporting-a-problem). An integrity failure always means a bug, in
   CrewSwap or in how it interacts with something else.

## Client-side LuaCs missing

A player sees this once per connection, about 90 seconds after they first enter a round while
CrewSwap is active:

```text
[CrewSwap] This server uses CrewSwap. Turn on client-side LuaCs (LuaCs settings), then rejoin to switch between crew.
```

The server console logs `[CrewSwap] switch: <player> sent no hello (no client-side LuaCs?)`.

Their game isn't running CrewSwap's client half, almost always because client-side LuaCs isn't
installed or isn't active. They can keep playing normally, without switching. To fix it,
follow [Client install](client-install.md) and rejoin. Checklist:

- Client-side LuaCs installed with the method on the
  [Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234).
- The Lua for Barotrauma content package is **disabled** in the in-game mod list.
- After joining, the F3 console shows `[CrewSwap] client loaded build ...`.

## Out-of-date client

```text
[CrewSwap] Your copy of CrewSwap is out of date or didn't start properly — rejoin to update.
```

The player's copy of CrewSwap is a different build from the server's, or its crew-list hooks
couldn't be installed. Switching stays off for that player until it's fixed:

- **Rejoin.** The server sends its current version on joining.
- After a CrewSwap update, the **server must be restarted** before it sends the new version.
- If the F3 console shows `probes FAILED`, the player's LuaCs build likely differs from what
  CrewSwap expects. Update client-side LuaCs.

## Ironman

```text
[CrewSwap] CrewSwap is off in Ironman campaigns.
```

This appears once per round. It's expected: CrewSwap doesn't support Ironman yet and stays off,
so Ironman plays exactly as vanilla. Ironman support may come in a later version.

## Clicking a row does nothing

- **Is CrewSwap active?** Type `!crewswap status`. It must say `active`.
- **Is it a campaign round?** CrewSwap is off in sandbox, mission and PvP modes.
- **Is your client running it?** Press F3 and look for `[CrewSwap] client loaded build` and
  `hello sent (...), probes ok`.
- **Is the row actually Free?** Greyed rows with a name are taken. A dimmed name means you
  can't take it, and clicking should tell you why.
- **Camera transition?** Clicks during a cinematic are ignored on purpose.

## Row colours look wrong

Row greying and labels are cosmetic. They come from the server's crew state, which is sent on
switches, deaths, round start and settings changes (not when a bot goes unconscious or wakes up,
or is hired mid-round). If a row looks stale, it usually corrects itself on the next switch or death.
The server is always the one that decides whether a switch is allowed.

## The round won't end

If everyone is down but Free crew are left, CrewSwap holds the round open for up to 2 minutes
so someone can switch in. Watch chat for the countdown. See [Playing](playing.md#everyone-is-down).

## Reporting a problem

Please open an issue on
[GitHub](https://github.com/MrMcEpic/barotrauma-crewswap/issues) and include:

- the CrewSwap version, the game version and the LuaCs build (from the
  `[CrewSwap] running on game ...` console line)
- the respawn mode, and the pool and protect settings (`!crewswap status`)
- every `[CrewSwap]` line from the server console around the problem
- from players, the `[CrewSwap]` lines from their F3 console
- what you did and what you expected

Before posting logs, remove anything personal: IP addresses, server passwords, and player
names if you'd rather keep them private.

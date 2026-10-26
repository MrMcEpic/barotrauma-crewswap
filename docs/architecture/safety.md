# Safety

CrewSwap touches save-critical code paths: who is stored where, which dead are kept, whose wallet
holds what. This page describes the layers that stop a bug from reaching the disk, and how an admin
recovers if something does go wrong. The admin-facing version is in
[Troubleshooting](../guide/troubleshooting.md).

The layers, from the outside in:

1. **Version gate**: wrong game version (or sandboxed server Lua), no patches at all; a different
   LuaCs commit only logs a warning.
2. **Patch-install audit**: any patch that fails to resolve switches the mod off.
3. **Runtime audits**: wrong-shaped bodies or an unreadable crew list switch the mod off.
4. **Every callback is guarded**: errors are caught, logged and, on save paths, block the save.
5. **Integrity check**: storage is verified before and after vanilla's `SavePlayers`; a failure
   blocks the write, reloads the last good save and locks the mod down.
6. **Backups**: vanilla keeps 20 rolling backups instead of 3.

## 1. Version gate

Harmony patches on internal methods break when the game or LuaCs changes. CrewSwap is built and
tested against one game version and one LuaCs commit, recorded in `shared/build.lua`. Only the game
version is enforced; the LuaCs commit is advisory:

```lua
EXPECT_GAME = '1.13.4',     -- any 1.13.4.x revision
EXPECT_LUACS = '<commit>',  -- short git hash; the first 7 characters are compared
```

At load, `server/main.lua`:

- requires `CSActive == true`. Reading the versions needs unsandboxed server Lua; a sandboxed server
  counts as a mismatch;
- reads `Barotrauma.GameMain.Version` (after registering `System.Version`) and
  `AssemblyInfo.GitRevision` (the LuaCs commit, the same value LuaCs logs at start-up);
- compares them with `core/version.compare`.

On a game-version mismatch the console shows `[CrewSwap] OFF: version mismatch (game <v>)` (or
`(server Lua is sandboxed)`, or `(version read failed: ...)`), and players get one chat line per
round:
`[CrewSwap] CrewSwap is off until it's updated for this game version (...)`. **No patch is
installed and no module is loaded**, so the game runs vanilla code, saves are written by vanilla,
and CrewSwap's data in the save is simply ignored (and kept by the mirror; see
[Persistence](persistence.md#the-mirror-file)).

A different LuaCs commit, or one that can't be read (empty or missing `GitRevision`), does **not**
turn the mod off. The console shows

```text
[CrewSwap] WARNING: built for LuaCs <expected>, running on <found>; continuing (patch audit and self-tests still guard)
```

and boot carries on. LuaCs updates itself through the Workshop far more often than the game does,
and most of its updates don't touch anything CrewSwap patches. The layers below are what catch a
LuaCs change that does matter: every patch must install ([section 2](#2-patch-install-audit)) and
the start-up and runtime checks must pass (the live crew-list check on the first campaign round,
the AI-body audits, the required game API checks), or `CS.fail` turns the mod off. The opt-in
in-game selftest only prints `SELFTEST` lines; it never calls `CS.fail`. So "self-tests" in the
warning line means those always-on checks (such as `SELFTEST PASS/FAIL live-crew-list`), not the
opt-in selftest.

Clients do not run their own version gate. The game handshake already refuses a client whose game
version differs from the server's, and the LuaCs commit is not readable from sandboxed client Lua.
Instead the client feature-probes its patches and reports the result together with its `BUILD` in
its hello (see [Networking](networking.md)).

**Design decision.** A server pinned to an old game version would stop players whose clients
auto-update from joining. So the server updates with everyone, and on a new game version the mod
turns itself off until a release for that version is made. The cost is that, while off, vanilla
rules apply (for example a dead bot is lost). A LuaCs update gets a warning instead of the same
treatment: switching the mod off for every LuaCs commit would break it every time LuaCs updates,
while a LuaCs change that does break a patch is already caught by the patch-install audit.

## 2. Patch-install audit

Every server `Hook.Patch` goes through `P.patch` in `server/patch.lua`, which wraps it in `pcall`.
A patch that does not resolve (a renamed method or changed signature, typically from a game hotfix,
since the gate accepts any 1.13.4.x revision) calls `CS.fail('patch <id> (<class>.<method>): ...')`.
The console prints `patches installed: N/N` at load; anything less than all of them means the mod
is off.

Likewise a module that throws while loading, `MakePropertyAccessible(MultiPlayerCampaign, 'GameOver')`
failing, ``ImmutableHashSet`1`` not registering or `SaveUtil.MaxBackupCount` not being settable all
call `CS.fail`.

## 3. Runtime audits

- **AI bodies.** At round start and on `character.created`, any player body in a multiplayer
  campaign that is not an `AICharacter` with a `HumanAIController` is a `CS.fail`. The `hasAi` prefix
  on `Character.Create` could fail open (a Lua error in a prefix lets the original run), so the
  result is checked rather than trusted.
- **Live crew list.** On the first campaign round, `G.checkLiveList()` converts
  `CrewManager:GetCharacterInfos(true)` and checks every element is a `CharacterInfo`. The selftests
  run before any campaign is loaded, so this is the first proof that the real list converts.

### What `CS.fail` means

`CS.fail(reason)` sets `CS.active = false` and `CS.lockdown = true`, prints `[CrewSwap] FAIL: <reason>`
and announces `[CrewSwap] CrewSwap is off until an admin restarts the server (see the server console).`
now and at every round start. `!crewswap status` shows `CrewSwap is off: <reason>`.

The campaign stays safe: switching stops, and the identity layer keeps writing every id and record
it already holds (new ids are minted only by the load-time integrity snapshot and a manual check; see
[Persistence](persistence.md)). **`!crewswap check` does not lift a failure**; it
only lifts integrity lockdowns. A broken build must stay off until it is fixed and the server
restarted.

An integrity lock can be raised *after* a failure (a load-time duplicate or a revert while
`CS.failReason` is already set), which marks the lockdown as an integrity lock too. A passing
`!crewswap check` then lifts the lockdown only when `CS.failReason == nil`; with a failure on record
it clears `CS.integrityLock` alone, leaves `CS.lockdown` set and replies that CrewSwap is still
locked down. A load during that lock still lifts the lockdown for the duration of the load (so the
save-on-load carries the ids) and puts it back in the postfix. `!crewswap status` keeps showing
the failure reason.

## 4. Guarded callbacks

Most callbacks are wrapped in `pcall` (the modules' `safe(...)` and `guard(...)` helpers, or an
inline `pcall`). The few trivial flag-setting prefixes (`crewswap.retainxp.save`,
`crewswap.safety.save`, `crewswap.safety.load.pre`) are unwrapped, and `crewswap.retainxp.get` and
`crewswap.safety.lobby` return values deliberately. Errors are logged with the module name (for example `[CrewSwap] roundend: restore error: ...`; the
exact prefix varies by module). The round-end, death, safety and admin modules also count them in
an `errors` table (the crew-set-postfix selftest reads roundend's); the `*-patches` selftests read
`P.errors`, the patch-install failures. On save-critical paths an error sets `CS.blockSave`:

- the `SavePlayers` restore;
- any `onSavePlayersPre` / `onSavePlayersPost` hook (keep-dead decisions, revival, integrity checks);
- a bot wallet that cannot be read at `CampaignMode.End` or at the save itself.

Where failing *open* would be dangerous, the code fails *closed* instead. The `TAKEOVERBOT` prefix,
for example, prevents vanilla from running if its own routing throws, because vanilla's takeover
can discard a living home.

## 5. Integrity check

### What is checked

`core/integrity.lua` works on plain lists of sids, produced by `S.stores(campaign)` in
`server/safety.lua`:

- `ccd`: every CCD's info (`MultiPlayerCampaign.characterData`, made accessible with
  `MakeFieldAccessible`);
- `roster`: every `CrewManager` info, active crew plus bench;
- `table`: every sid the registry holds a record for.

`integrity.check(snapshot, now, legit)` compares the stores now with a **snapshot** taken at round
start and after every campaign load, and reports:

| Problem | Meaning |
|---|---|
| `duplicate <sid>` | The same character is in more than one place (two CCDs, a CCD and the roster, or twice in one). |
| `missing <sid>` | A character present at the snapshot has vanished. |
| `moved <sid>` | A character moved between CCD and roster (a bot stored as a player character, or the reverse). |
| `unknown <sid>` | The registry has a record for a character that exists in neither store. |

The snapshot also records **stale** sids: records whose character was already gone at the snapshot
(fired or permanently dead in an earlier round). Records are kept for the session, so stale sids
are not reported as `unknown` forever after.

### Legitimate changes

Vanilla (and the mod) remove or move characters on purpose. Those are noted by `CS.noteLegit(kind,
infoId)` during the round:

| Kind | Noted by |
|---|---|
| `permadead` | A crew death in Permadeath (postfix on `Character.KillProjSpecific`), or a home already permanently dead at the snapshot (it keeps its CCD until replaced). |
| `fired` | Prefix on `CrewManager.FireCharacter`. |
| `discarded` | Prefix on `MultiPlayerCampaign.DiscardClientCharacterData` (vanilla "create new character", and the CCD drop inside `TryTakeOverBot`). |
| `adopted` | Permadeath adoption of a new home in `SW.switch`, and the Permadeath takeover fall-through. Allows exactly one roster-to-CCD move, including the moment vanilla briefly has it in both. |

### When it runs

`CS.runCheck(label)` runs:

- **`pre-save`**: after the restore, in the `SavePlayers` prefix (only while `CS.active`, so it
  is skipped during a lockdown even though the restore still runs);
- **`post-save`**: after vanilla's `SavePlayers` (and after kept crew are put back), also only
  while `CS.active`;
- **`manual`**: when an admin types `!crewswap check`;
- **`selftest`**: the in-game selftest's `safety-runcheck` check.

Each problem is printed as `[CrewSwap] INTEGRITY FAIL (<label>): <problem> <sid> (<name>)`, and chat
gets a one-line summary: `[CrewSwap] Integrity check failed (<label>): <N> problem(s), see the server
console.`

### What a failure does

```text
 SavePlayers prefix/postfix   check fails -> CS.blockSave = true
 SaveUtil.SaveGame prefix     blockSave -> PreventExecution (nothing is written)
                              CS.saveBlocked = true
 GameServer.EndGame postfix   saveBlocked ->
                                lock(ALARM)          lockdown + integrityLock
                                MultiPlayerCampaign.LoadCampaign(DataPath, nil)
                                IncrementAllLastUpdateIds()
 TryStartGame prefix          while locked -> refuse, return GameAlreadyStarted
```

1. **Don't write.** The `SaveUtil.SaveGame` prefix sets `PreventExecution`, so nothing reaches the
   disk. The save-on-load (`isSavingOnLoading`) is never blocked: it only rewrites what was just
   loaded.
2. **Reload.** Memory already holds what `SavePlayers` did (folded CCDs, deleted inventories), so
   continuing from memory is not an option. The `GameServer.EndGame` postfix reloads the last good
   save the way vanilla's failed-round branch does, then bumps every net update id so clients
   resync.
3. **Lock before reloading.** On the server, `LoadCampaign` starts the next round itself before it
   returns. The lock is therefore set *before* the reload, or it would never reach the lobby refusal.
4. **Hold the lobby.** While an integrity lock is in force, a prefix on `GameServer.TryStartGame`
   refuses to start a round (it returns `TryStartGameResult.GameAlreadyStarted` and announces
   `The round can't start: an integrity check failed. An admin must run !crewswap check.`).
   Switching is off too (`CS.active` is false).
5. **Load-time duplicates.** If a save being loaded already holds one sid on two crew members
   (`CS.dupes`, found by the `MultiPlayerCampaign.Load` postfix), the `LoadCampaign` postfix locks
   down at once with its own alarm, and `TryStartGame` is refused even inside that load.

### Lifting a lockdown

`!crewswap check` runs the check against the current state. If it passes and the lockdown came from
an integrity failure (`CS.integrityLock`) and no failure is on record (`CS.failReason == nil`), the
lock is lifted and `CS.active` recomputed. If the mod is also off for another reason (a failed patch
or another `CS.fail`), only `CS.integrityLock` is cleared, the lockdown stays, and the reply says it
is still locked down. Because `S.holdsLobby()` needs `CS.integrityLock`, the lobby hold is
released, so rounds can start again, but CrewSwap stays off (switching disabled) until the FAIL
is fixed and the server restarted. On a game-version mismatch no `!crewswap` command is handled at all, because
no module is loaded.

A load during a lockdown (an admin loading a backup from the lobby) re-saves straight away. The
`LoadCampaign` prefix lifts the integrity lock for the duration of the load so that save-on-load
carries the ids, and the postfix puts it back. The admin then runs `!crewswap check` against the
loaded backup.

### Ordering between modules

`roundend.lua` and `safety.lua` both have prefixes on `SaveUtil.SaveGame` and postfixes on
`GameServer.EndGame`, and Harmony does not promise an order between them. The code is written to
be order-independent: the wallet prefix blocks the write itself if its commit fails, and
`CS.lastSaveBlocked` (set by safety's `SaveGame` prefix, cleared only at round start) survives
safety's `EndGame` postfix clearing `CS.saveBlocked`, so roundend's `EndGame` postfix can tell that
the save was blocked whichever runs first.

### Testing the alarm

The development-only marker `<SaveFolder>/CrewSwap/force-integrity-fail` makes every check fail with
`forced by /CrewSwap/force-integrity-fail`. Use it on a throwaway campaign to see the whole
block-reload-lock-check sequence, then delete it.

## 6. Backups

At load, `server/safety.lua` sets `SaveUtil.MaxBackupCount = 20` (vanilla keeps 3). These are
vanilla's own rolling backups, so they appear in the lobby's load list for the campaign, and an
admin can load one when the check keeps failing.

**Design decision.** Copying save files to a separate dated backup folder at every round start
was considered. Raising vanilla's count gives the same protection with no new file handling and a restore
path admins already know.

## Recovery summary

| Symptom | Cause | What lifts it |
|---|---|---|
| `OFF: version mismatch` | The game version differs from the build, server Lua is sandboxed, or the game version couldn't be read | A CrewSwap release for that version, or LuaCs's default C# run policy. |
| `WARNING: built for LuaCs ...` | The LuaCs commit differs from the one tested | Nothing needed; the mod keeps running. Put back the tested LuaCs build if something misbehaves. |
| `FAIL: <reason>` | Patch, module, audit or live-list failure | Fix the cause, restart the server (`!crewswap check` can't lift it). |
| `Integrity check failed: the round was not saved ...` | A check failed at save time | `!crewswap check`; if it keeps failing, load a backup, then `!crewswap check`. |
| `... this save has the same crew member twice ...` | The loaded save has a duplicate id | Load an older backup, then `!crewswap check`. |

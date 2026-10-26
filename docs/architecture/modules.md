# Modules

Every Lua file in the mod, what it is responsible for, and the functions other code relies on.
Paths are relative to `mod/CrewSwap/`.

## Package files

| File | Purpose |
|---|---|
| `filelist.xml` | The content package: `name="CrewSwap"`, `modversion`, `gameversion="1.13.4.0"`, `corepackage="false"`, and one `<Item>` entry for the sync file. `modversion` is stamped by `tools/package.sh`. |
| `ModConfig.xml` | Two autoruns: `Lua/crewswap/server/main.lua` with `Target="Server"` and `Lua/crewswap/client/main.lua` with `Target="Client"`. Because a `ModConfig.xml` exists, LuaCs skips the legacy `Lua/Autorun` folder scan. Everything else is reached through `require`. |
| `Content/crewswap_sync.xml` | An empty `<Items></Items>` file. Lua files do not count as multiplayer-synced content, so without at least one synced file the server would neither send the mod to clients nor require it. An item file is synced, and an empty `items` root creates no prefabs and logs no errors. |

All modules are namespaced `crewswap.*` because the `require` cache is shared by every mod.

## `shared/`

### `shared/build.lua`

Returns `{ BUILD, MODVERSION, EXPECT_GAME, EXPECT_LUACS }`.

- `BUILD` is the exact build string. The client sends it in its hello and the server compares it
  for equality, so server and clients must run copies from the same package.
- `MODVERSION` is written into the save's `<CrewSwap>` element.
- `EXPECT_GAME` (`'1.13.4'`) and `EXPECT_LUACS` (a short LuaCs commit hash) are what the version
  gate compares against. A game mismatch turns the mod off; a LuaCs mismatch only logs a warning.

In the repository, `BUILD` and `MODVERSION` hold the current release values (`'0.9.0-beta'` /
`'0.9.0'`). `tools/package.sh <version> [suffix]` re-stamps both, plus `modversion` in
`filelist.xml`, in a staged copy, so the zip always carries the version you pass.

## `core/`: pure decision modules

No game globals, no side effects beyond their own tables. Each has a matching `tests/test_*.lua`.

### `core/version.lua`

- `compare(found, expect)` → `ok, reason, warning`. The game matches when it equals `EXPECT_GAME`
  or starts with `EXPECT_GAME .. '.'` (so `1.13.4.2` matches but `1.13.40` does not); a game
  mismatch returns `false, 'game <found>'`, and takes precedence (no warning). LuaCs is compared on
  the first 7 characters of the commit hash: a different, short, empty or unreadable commit returns
  `true, nil, warning`, where `warning` is the line
  `[CrewSwap] WARNING: built for LuaCs <EXPECT_LUACS>, running on <found or 'unknown'>; continuing (patch audit and self-tests still guard)`.
  A full match returns `true, nil, nil`.

### `core/rules.lua`

The switching rules.

- `COOLDOWN = 3` (seconds between switches per player).
- `allowedByToggles(view, toggles, requesterKey)`: protect on hides other players' homes; `own`
  pool allows only bodies the requester owns, their own home, or bodies that nobody owns and that
  are nobody's home (the first player to take one claims it).
- `isFree(view, toggles, key)`: crew, an AI body, alive, conscious, not removed, no controller, and
  allowed by the toggles.
- `validate(req, view, toggles, ctx)` → `ok, reason`. Reasons in fixed order: `inactive`, `round`
  (not running or ending), `joining` (not in game or not synced), `nohome` (no campaign character
  yet), `spectating`, `traitor`, `dialogue`, `cooldown`, `invalid` (not crew), `taken`,
  `unavailable`, `not-yours`. The requester's own body state is deliberately ignored, so a downed
  player may still switch out.
- `message(reason, extra)`: the player-facing `[CrewSwap] ...` text for a reason (also used on the
  client, so both sides word denials identically). It also words the `takeover` denial, which is
  not a `validate` reason: the `TAKEOVERBOT` routing in `server/death.lua` sends it for a hire or
  bench id outside the Permadeath case.

### `core/registry.lua`

Session-to-stable-id bindings and per-character records.

- `new()` → registry with `bySession` (`CharacterInfo.ID` → sid) and `chars` (sid → record).
- `R:bind(sessionId, sid)`, `R:sidOf(sessionId)`, `R:record(sid)` (creates on demand),
  `R:prune(liveSessionIds)` (drops stale bindings, keeps records).
- `FIELDS` maps record fields to XML attributes: `last`, `owner`, `home`, `wbal`, `wrd`, `lastAt`
  → `crewswap_last`, `crewswap_owner`, `crewswap_home`, `crewswap_wbal`, `crewswap_wrd`,
  `crewswap_lastat`. `NUMERIC` marks `wbal`, `wrd` and `lastAt`. `ID_ATTR = 'crewswap_id'`.
- `encodeAttrs(rec)` / `decodeAttrs(map)`: record ↔ attribute strings.
- `campaignElement(state)` / `parseCampaignElement(map)`: the `<CrewSwap campaignguid modversion>`
  element.

### `core/mirror.lua`

Re-matching after a Lua reload or a period with the mod off.

- `rowAttrs(row)` / `parseRow(get)`: one `<c>` row of the mirror file (`id`, `on` = original name,
  `h` = `GetIdentifierUsingOriginalName()` hash, `job`, plus the record's `crewswap_*` fields).
- `match(entries, live)` → `{ [sessionId] = sid }`. Pass 1 pairs entries and live infos that share
  a unique hash; pass 2 does the same on original name for what is left. Anything ambiguous stays
  unmatched, so every sid is claimed at most once and the result does not depend on list order.

### `core/placement.lua`

Where a player goes at round start or on rejoin.

- `lastPlayed(chars, key)`: the sid whose record has `last == key` and the greatest `lastAt`.
- `roundStart(players, views, toggles)` → list of `{ key, targetId }` moves. With protect on,
  nobody moves. With protect off, each player goes to the character they last played if it is
  Free for them, is not their home, and nobody earlier in the list claimed it.
- `rejoin(player, views, toggles)` and `rejoinTarget(...)`: the same rule for one rejoining
  player, falling back to their own home body when that is Free for them (a rejoiner whose body was
  handed back to the AI otherwise has no character).

### `core/grace.lua`

The crew-down grace timer: `GRACE = 120`, `WARN_AT = 90`, and three chat lines (start, 30 s left,
end). `grace.new()` returns a state with `step(dt, vanillaDown, anyFree)` → `mask, announce`.
While vanilla would end the round and Free crew exists, `mask` is true for up to 120 s.

### `core/integrity.lua`

The storage check over plain lists of sids.

- `snapshot(stores)`: copies the CCD and roster lists and records `stale` sids (registry records
  for characters already gone at the snapshot, i.e. removals an earlier round accepted).
- `check(startSnap, nowStores, legit)` → `ok, problems`. Problems are sorted strings:
  `duplicate <sid>`, `missing <sid>`, `moved <sid>`, `unknown <sid>`. `legit` lists removals made on
  purpose this round (`permadead`, `fired`, `discarded`) and `adopted` bots that legitimately moved
  from roster to CCD. See [Safety](safety.md).

### `core/revive.lua`

What happens to a dead crew member at round end.

- `plan(info, path)`: `info = { cause = 'none'|'disconnected'|'other', permadeath, inCCD, inRoster }`,
  `path = 'transition'|'saveandquit'|'unsaved'`. Returns flags `keep`, `penalty`, `clearHealth`,
  `clearInventory`, `clearOrders`, `pendingSpawn`. Only non-home roster members outside Permadeath
  that actually died are kept. The skill penalty applies only when the round saves and the death
  was not a disconnect. The inventory is cleared only on a level transition.
- `dropsAtSave(body)`: whether vanilla `SavePlayers` itself removes this body's info (a dead bot
  with an inventory that did not die of a disconnect).

### `core/commands.lua`

The admin chat command and config file.

- `PREFIX = '!crewswap'`, `DEFAULTS = { pool = 'shared', protect = true }`.
- `parse(text)` → `nil` (not ours) or `{ op = 'status'|'check'|'pool'|'protect'|'owner'|'error', ... }`.
  Tokens split on whitespace with `"double quoted"` parts kept whole; `!crewswapper` is not a match.
- `configEncode(t)` / `configDecode(s)`: the `pool=...` / `protect=on|off` text format; unknown
  lines and bad values fall back to defaults.
- `statusText(t, info)`, `FAIL_NOTICE`, and `findByName(list, name)` (case-insensitive exact
  match, then a unique prefix; `'none'` or `'ambiguous'` otherwise).

### `core/statecodec.lua`

The `crewswap.state` payload: `encode(writer, entries)` and `decode(reader)`. Layout: `UInt16`
count, then per entry `UInt16` entity id, `String` controller name, `Boolean` free. See
[Networking](networking.md).

## `server/`: adapters

Loaded by `server/main.lua` in this order: `game`, `patch`, `selftest`, `spawn`, `identity`,
`switch`, `presence`, `roundend`, `death`, `crewdown`, `safety`, `admin`. The order matters in a
few places (noted below), because modules append to shared hook lists and patch the same methods.

### `server/main.lua` (autorun)

- Creates `CS`, carrying over the client hello tables (`clientBuild`, `clientBad`, `joinedAt`,
  `noHelloTold`) across a server Lua reload, since every client's Lua keeps running.
- `CS.fail(reason)`: switch the mod off for the rest of the session (sets `lockdown`, records
  `failReason`, prints `[CrewSwap] FAIL: <reason>`, announces `FAIL_NOTICE` now and every round
  start).
- The version gate (`checkVersions`, see [Safety](safety.md)). On a game-version mismatch (or
  sandboxed server Lua) it registers a single `roundStart` chat notice and returns before any
  module loads. A different or unreadable LuaCs commit prints a `[CrewSwap] WARNING: built for
  LuaCs ...` line and boot continues.
- `CS.recomputeActive(campaign)`: computes `CS.campaignOk` and `CS.active`, and sends the Ironman
  notice once per round.
- Loads the server modules (a missing module is skipped; any other load error is a `CS.fail`),
  prints `patches installed: N/N`, and schedules the in-game selftest when its marker file exists.

### `server/game.lua` (`G`)

The game adapter everything else uses.

- `G.list(x)` / `G.iterate(x)`: converts any CLR collection (a copied table, an iterator function or
  a userdata enumerable such as a LINQ result) into a plain Lua array.
- `G.accountKey(client)`: `AccountId.StringRepresentation`, or `'addr:<address>'` when there is no
  account id (matching how vanilla keys CCDs).
- `G.clients()`, `G.campaign()` (the `MultiPlayerCampaign` or nil), `G.isCrew(ch)`,
  `G.controllerOf(ch)`, `G.homeOf(ch)`, `G.homeBodyOf(client)` (the live body of the client's CCD
  info, searched each time so it survives respawns and mid-round joins).
- `G.view(ch)` and `G.crewViews()`: plain views `{ id, sid, alive, conscious, removed, crew, isAI,
  controller, controllerName, homeOf, owner, name }` for the core modules. Crew means a Team1 human
  whose info is a CCD info (a home) or is in `CrewManager:GetCharacterInfos(true)` (bots and the
  bench). Stable ids are only minted while `CS.active`.
- `G.tell(client, text)`, `G.announce(text)`, `G.isAdmin(client)` (`ClientPermissions.ManageSettings`),
  `G.now()` (`Timing.TotalTime`), `G.isPermadeath()`, `G.toggles()`.
- `G.checkLiveList()`: on the first campaign round, proves the real crew list converts; on failure
  the mod switches itself off (`SELFTEST FAIL live-crew-list`).

### `server/patch.lua` (`P`)

`P.patch(id, class, method, types, fn, when)` wraps every server `Hook.Patch` in `pcall`. A patch
that does not resolve means the game is not what the build was made for, so it calls `CS.fail`.
`P.errors[id]` and `P.summary()` feed the selftest and the `patches installed` line.

### `server/selftest.lua`

`M.add(name, fn)` registers an in-game check; `M.run()` prints `SELFTEST PASS|FAIL|SKIP` lines and a
summary. See [Testing](testing.md).

### `server/spawn.lua`

- Prefix on `Character.Create` (`crewswap.forceai`): sets `hasAi = true` for remote-player spawns
  with an info, in a campaign.
- `S.isAIBody(ch)`: an `AICharacter` with a `HumanAIController`.
- Audits on `roundStart` and `character.created`: a player body without AI in a multiplayer
  campaign is a `CS.fail`.

### `server/identity.lua`

Stable ids and campaign state. See [Persistence](persistence.md).

- `CS.sidOfInfo(info)`: the sid for an info, taken from the binding, from an id just read from XML
  (`CS.pending`), or freshly minted (`CS.newGuid()`).
- `CS.liveCrewInfos(campaign)`: bots and bench, every CCD info, and Ironman's backup list.
- `M.writeMirror`, `M.readMirror`, `M.bindMissing(infos, allowMint)`.
- Patches on `CharacterInfo.Save`, the `CharacterInfo` XML constructor, `MultiPlayerCampaign.Load`
  and `MultiPlayerCampaign.Save` (prefix and postfix), plus a reload-recovery block that runs at
  load time.

### `server/switch.lua` (`SW`)

- `SW.request(client, ch, source)`: build the requester and context, `rules.validate`, then
  `SW.switch`; on denial `SW.deny`.
- `SW.switch(client, target)`: the switch routine (see [Lifecycle](lifecycle.md#switch)).
- `SW.release(client)`: hand the client's body back to the AI.
- `SW.sendState(client)`, `SW.broadcastState()`: per-client `crewswap.state`.
- `CS.isVoluntarySpectator(c)`: a lobby spectator, as opposed to one a permadeath kill set.
- The `crewswap.hello` and `crewswap.request` receivers, the hello watchdog, and the
  "no client-side LuaCs" notice. See [Networking](networking.md).

### `server/presence.lua`

- `client.disconnected` (a prefix on vanilla's disconnect, so `client.Character` is still set):
  record the client as last controller, then `SW.release` so the body reverts to AI instead of
  freezing.
- Postfix on `GameServer.OnInitializationComplete` queues a joining client; a `think` poll (every
  0.5 s, for up to `JOIN_WINDOW = 180` s) places them with `placement.rejoinTarget` once they are in
  game and synced and the round is not ending.
- `roundStart`: `placement.roundStart` moves for everyone present.

### `server/roundend.lua`

The round-end restore, kept dead crew and per-character wallets.

- `CS.restoreAll()`: everyone out of borrowed bodies, then everyone back into their home body.
- Patches on `GameSession.EndRound`, `MultiPlayerCampaign.SavePlayers` (prefix and postfix),
  `MultiPlayerCampaign.End`, `GameSession.GetSessionCrewCharacters`,
  `CrewManager.RemoveCharacterInfo`, `CampaignMode.End` (prefix and postfix), `GameServer.EndGame`,
  `SaveUtil.SaveGame` and `CrewManager.InitRound`.
- `CS.onSavePlayersPre` / `CS.onSavePlayersPost`: hook lists other modules append to; any error in
  them blocks the save. Because `roundend` loads before `safety`, its post-save hook (putting kept
  crew back) runs before the post-save integrity check.
- `CS.reviveKept(path)`, `R.applyRevive(info, actions)`, `CS.snapshotWallets()`,
  `CS.commitWallets()`.

### `server/death.lua`

- The kill redirect: prefix and postfix on `Character.KillProjSpecific`, plus a `think` safety net
  that gives the driver back if vanilla threw between them.
- Undriven permadeath for a home the AI was running.
- `RespawnManager.RespawnCharacters` prefix: let go of a dead borrowed corpse before respawn.
- `RetainExperienceForNewCharacter` off (`SaveExperiencePoints` skipped,
  `GetSavedExperiencePoints` returns 0).
- `TAKEOVERBOT` routing (`GameServer.ReadTakeOverBotMessage`) and the `Client.TryTakeOverBot`
  postfix.
- `CS.onDriverDeath(client, body, disconnected)`.

### `server/crewdown.lua`

Holds the round open while Free crew exists, using `core/grace`. A prefix on `GameServer.Update`
sets `UsingFreeCam` on every client so vanilla's crew-down test sees "someone is up"; a postfix and
a `think` hook clear it again. Details in [Lifecycle](lifecycle.md#crew-down-grace).

### `server/safety.lua`

The integrity safety net. See [Safety](safety.md).

- `CS.runCheck(label)`, `CS.noteLegit(kind, infoId)`, `S.stores(campaign)`, `S.holdsLobby()`.
- Raises `SaveUtil.MaxBackupCount` to 20.
- Patches on `Character.KillProjSpecific`, `CrewManager.FireCharacter`,
  `MultiPlayerCampaign.DiscardClientCharacterData`, `SaveUtil.SaveGame`, `GameServer.EndGame`,
  `MultiPlayerCampaign.LoadCampaign` (prefix and postfix) and `GameServer.TryStartGame`.

### `server/admin.lua` (`A`)

- `A.load()` / `A.save()`: `config.txt` in `<SaveFolder>/CrewSwap/`, written via a `.tmp` file and
  a move.
- `A.onChat(text, client)` on the `chatMessage` hook: parses with `commands.parse`, runs the
  command, and returns `true` so the message never shows in public chat (for every sender).
- `A.run(client, cmd)`: `status` for everyone; `pool`, `protect`, `owner` and `check` for admins.
- Postfix on `CampaignMode.TryHireCharacter`: in `own` pool mode the hirer owns the new hire.

## `client/main.lua` (autorun)

Runs on clients only (`if not CLIENT then return end`) and keeps its state in `CSC`.

- `CSC.onClick(cm, p)`: prefix on `CrewManager.CharacterClicked`. Sends a switch request for a Free
  row and suppresses vanilla's click; see [Networking](networking.md#click-handling).
- `CSC.onRowAdded(cm, p)` (postfix on `CrewManager.AddCharacterToCrewList`), `CSC.styleRow(c)`,
  `CSC.styleAll()`: greys taken rows and labels them with the controller's name, dims crew that are
  not Free for this player, and restores the original colours otherwise.
- `CSC.rebuildRow(cm, c)`: rebuilds a row whose `IsPlayer` flag flipped since it was built (vanilla
  only builds objective icons for rows that were bots at creation); never mid-drag.
- `CSC.think()`: detects the client's own control change through `Game.Client.Character`, then
  `CSC.afterOwnControlChange(newChar)` does the housekeeping singleplayer's character selection does
  and multiplayer skips: close the command UI, clear inventory drag state, `HintManager.OnChangeCharacter`,
  refresh an open Talents tab, and reset or auto-hide the crew list and chat box.
- `CSC.applyState(entries)`, `CSC.notify(text, isError)`, `CSC.sendHello()`.
- Probe-installs both patches and `MakeFieldAccessible(CrewManager, 'crewList')`, and looks up seven
  static classes (`Timing`, `CoroutineManager`, `ConversationAction`, `HintManager`, `TabMenu`,
  `GameSession`, `ChatBox`); any failure sets `CSC.probesOk = false`, which the hello reports to
  the server.

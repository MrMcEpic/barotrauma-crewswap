# Lifecycle

This page follows a campaign from server start to save, in the order things happen. Method names
are the real patch targets; see [Patches](patches.md) for the full list.

## Load and boot

`ModConfig.xml` autoruns `server/main.lua` on the server and `client/main.lua` on each client.

On the server, `server/main.lua`:

1. Prints `[CrewSwap] server loaded build <BUILD>`.
2. Creates the global `CS` table. After a server Lua reload it carries over what the clients'
   hellos said, because the clients' Lua keeps running and would never resend on its own.
3. Defines `CS.fail` and a `roundStart` hook that repeats the failure notice while one is recorded.
4. **Version gate.** Requires `CSActive == true` (unsandboxed server Lua), registers `System.Version`
   and `AssemblyInfo`, reads `Barotrauma.GameMain.Version` and `AssemblyInfo.GitRevision`, prints
   `[CrewSwap] running on game <v>, LuaCs <rev>`, and compares them with `core/version`. On a
   game-version mismatch (or sandboxed server Lua, or an unreadable game version) it prints
   `[CrewSwap] OFF: version mismatch (...)`, registers a once-per-round chat notice and **returns**:
   no module is loaded and no patch is installed. A different (or unreadable) LuaCs commit only
   prints `[CrewSwap] WARNING: built for LuaCs <expected>, running on <found>; continuing (patch
   audit and self-tests still guard)` and boot carries on.
5. Defines `CS.recomputeActive` and a `roundStart` hook that recomputes it.
6. Loads the server modules in dependency order. Each module installs its patches and hooks at
   load time and registers its selftest checks.
7. Prints `modules loaded: ...` and `patches installed: N/N` (36 on the current build), then
   computes `CS.active`.
8. If `<SaveFolder>/CrewSwap/selftest` exists, runs the in-game selftest one second later.

If the server Lua is reloaded mid-campaign, `server/identity.lua` notices a loaded campaign it has
not seen and re-matches every crew member to its stable id from the mirror file, minting nothing
(see [Persistence](persistence.md#recovery-after-a-lua-reload-or-a-mod-off-gap)).

On a client, `client/main.lua` registers its `crewswap.state` / `crewswap.denied` handlers first (a
server message that arrives before its handler is registered is dropped), probe-installs its two
patches, registers the `crewswap.hello?` handler, and sends its hello two seconds later (all
handlers are in place before the first hello goes out). See [Networking](networking.md).

## Campaign load

`MultiPlayerCampaign.Load` runs whenever a campaign is loaded: a fresh load from the lobby, the
reload vanilla does after a failed round, or a backup an admin picks.

- While vanilla builds each `CharacterInfo` from XML, the postfix on the
  `CharacterInfo(ContentXElement, Identifier)` constructor reads `crewswap_id` and the `crewswap_*`
  record fields into `CS.pending[info.ID]`.
- The `MultiPlayerCampaign.Load` postfix reads `<CrewSwap campaignguid>`, builds a fresh registry,
  binds every live crew info to its pending sid, records duplicate sids in `CS.dupes`, and fills
  any gaps from the mirror. It logs `identity: load bound N of M crew, campaign <guid>`.
- The `MultiPlayerCampaign.LoadCampaign` postfix (in `safety.lua`) takes the integrity baseline
  and, if the save holds the same sid on two crew members, locks down at once.

## Round start and spawning

As vanilla spawns bodies:

- `Character.Create` prefix (`spawn.lua`): for a remote-player spawn with an info in a campaign,
  `p['hasAi'] = true`. Every campaign crew body is therefore an `AICharacter`.
- `CrewManager.InitRound` postfix and the `character.created` hook (`roundend.lua`): each roster
  bot's wallet balance and salary are restored from its record. `character.created` covers bots
  created inline (the first round of a campaign) and bench spawns, which never pass through
  `InitRound`.

Then the `roundStart` hooks run:

- `CS.recomputeActive()`; the console shows `[CrewSwap] round start, active: true|false`.
- On the first campaign round, `G.checkLiveList()` proves the real crew list converts.
- The spawn audit: any connected client whose body is not an AI body is a `CS.fail`.
- Round-end flags are reset; kept dead crew and staged wallets from the last round are cleared.
- `safety.lua` clears the save-block flags, resets the list of legitimate removals and takes the
  round-start integrity snapshot.
- **Placement** (`presence.lua`): with protect **on**, everyone stays in their home body. With
  protect **off**, each player is moved into the character they last played (the record with
  their account key in `last` and the latest `lastAt`), if it is Free for them.
- `SW.broadcastState()` sends every client with client-side LuaCs its view of the crew.

## Switch

```text
 client                                   server
 ------                                   ------
 click a Free crew row
 CharacterClicked prefix
   PreventExecution
   guards: dialogue? camera transition?
           3 s cooldown (local)
   crewswap.request(UInt16 entity id)  -->
                                          SW.request
                                            stale/bad client? -> 'inactive'
                                            rules.validate(req, G.view(ch), toggles, ctx)
                                          SW.switch(client, target)
                                            SetClientCharacter(client, nil)
                                            old:ClearInputs(); old.AIController:Reset()
                                            SetClientCharacter(client, target)
                                            record.last / lastAt; own-pool claim
                                            Permadeath: adopt as new home?
                                          SW.broadcastState()
                                      <-- crewswap.state (to every client that said hello)
 think: Game.Client.Character changed
   housekeeping, "Now playing <name>",
   restyle rows
```

Points worth knowing:

- **Two `SetClientCharacter` calls.** Vanilla sends `ControlEventData(null)` for the body being left
  only when a client is set to `nil`; a direct body-to-body switch skips it and leaves a stale
  "is a player" flag on other clients (breaking crew-list markers and the death prompt's bot list).
  Releasing first and then binding avoids that.
- **`ClearInputs()` and `AIController:Reset()`** on the old body make it pause briefly and then
  pick up its orders again, the way singleplayer does.
- **Never `TryTakeOverBot`, never `RenamingEnabled`.** Vanilla's takeover discards the client's CCD,
  moves salary and allows a free rename.
- **Validation is entirely server-side.** The client's guards only spare a round trip.
  `rules.validate` checks, in order: the mod is active, a round is running and not ending, the
  requester is in game and synced, they have a campaign character (`nohome` otherwise), they are
  not a voluntary spectator, not a traitor, not in a conversation, and off cooldown; and that the
  target is crew, has no controller, is alive, conscious, not removed, an AI body, and allowed by
  the toggles.
- **First come, first served.** Requests are handled one at a time on the server's main thread;
  the second request for the same body finds a controller and is denied with `taken`.
- **A permadeath-set spectator is un-spectated.** A Permadeath kill sets `SpectateOnly` on the
  driver in vanilla, and vanilla's ownership loop would kill the new body at once. `SW.switch`
  clears it, but a player who *chose* to spectate in the lobby cannot switch in.
- **No home yet, no switch.** A first-time joiner has no CCD until they spawn once.
  `SetClientCharacter` points `client.CharacterInfo` at the target, and only a CCD ever points it
  back, so switching now would lose their character. Both `rules.validate` and `SW.switch` refuse.
- **Own-pool claim.** In `own` mode, the first player to take a character with no owner (and that
  is nobody's home) becomes its owner.
- **Permadeath adoption.** If the switching player's home is permanently dead and the target is
  nobody's home, `adoptHome` makes it their new home: `SetClientCharacterData` builds a CCD from the
  target's info, the info is removed from the `CrewManager` roster (so it lives in exactly one
  store), and the integrity check is told this move is legitimate (`adopted`).

On the client, `CSC.think()` notices that `Game.Client.Character` changed. It records the new id
*before* any side effect (so a throwing UI call cannot re-fire every frame), sets the local
cooldown, runs the housekeeping listed in [Modules](modules.md#clientmainlua-autorun), shows
`[CrewSwap] Now playing <name>` and restyles the rows.

## Death

Vanilla's `Character.KillProjSpecific` finds "the player who died" by looking for the client whose
`c.Character` is the dying body, and applies every death effect to *that client's* CCD:
`ApplyPermadeath`, `SpectateOnly = true`, `SaveExperiencePoints` for RetainExperience, the Ironman
disk write and the traitor message. After a switch, that is the wrong character.

CrewSwap redirects it:

1. **Prefix** (`crewswap.kill.pre`): if the body is crew and driven, remember
   `{ driver, body, cause, balance }` in `CS.deathCtx[ch.ID]` and set `driver.Character = nil`, which
   hides the driver from all three of vanilla's lookups.
2. Vanilla kills the body with nobody to blame.
3. **Postfix** (`crewswap.kill.post`): give the driver their body back (they stay attached to the
   corpse until they switch or respawn) and apply the effects to the character that died:
   - re-point `driver.CharacterInfo` at their home info with a raw assignment, so vanilla's
     mid-round respawn spawns their home and not a second copy of the borrowed character;
   - in Permadeath, unless the death was a disconnect: if the dead info has a CCD (it is someone's home), call `ApplyPermadeath` on
     that CCD and pay the body's wallet into the campaign bank, because `ApplyPermadeath` drops the
     CCD wallet; a bot just gets `PermanentlyDead = true`; then bump the `CharacterInfo` net flag;
   - send the traitor notice to the driver if a traitor did it;
   - broadcast state so the dead player sees which crew are Free.
4. A `think` hook restores the driver if vanilla threw inside `KillProjSpecific` and the postfix
   never ran.

Related pieces:

- **Undriven permadeath.** Vanilla only makes a death permanent through a driving client. When the
  AI was running a player's home (its owner was playing someone else), the postfix applies
  permadeath itself (again skipped when the cause of death is a disconnect), so "the character who died is permanently dead" holds for everyone.
- **Respawn keeps the corpse.** `RespawnManager.RespawnCharacters` despawns each client's current
  body. Outside Permadeath, a prefix first detaches a client from a dead *borrowed* body, so the
  corpse stays in the world (with its items) instead of being despawned.
- **The vanilla takeover request.** The Permadeath death prompt offers "take over a bot", which
  sends `TAKEOVERBOT`. A prefix on `GameServer.ReadTakeOverBotMessage` peeks the info id. For a
  crew member already in the world it becomes a normal CrewSwap switch request. For a hire or bench
  id, vanilla runs only in Permadeath and only when the player has no CCD or their home is
  permanently dead (and with `client.CharacterInfo` pointed back at the home first); otherwise it
  is refused. If the routing itself errors, vanilla is still prevented, because failing open here
  could discard a living home. A postfix on `Client.TryTakeOverBot` records the result as the
  player's new home.
- **RetainExperienceForNewCharacter** is off while active: the prefix on
  `MultiPlayerCampaign.SaveExperiencePoints` skips it and `GetSavedExperiencePoints` returns 0.

## Crew-down grace

Vanilla's `GameServer.Update` ends the round when every connected client is
`!UsingFreeCam and (no character, dead, or incapacitated)`. With switching, that is too early:
there may be Free crew to jump into.

`server/crewdown.lua` reproduces vanilla's test term for term (`vanillaWouldBeDown`). When vanilla
would end the round **and** at least one in-game client could take a Free crew member, the
`core/grace` timer runs for up to 120 s with three chat lines (start, 30 seconds left, nobody
switched in). While it is open, the `GameServer.Update` prefix sets `UsingFreeCam = true` on every
client for the duration of that one `Update` call, so vanilla sees "someone is up" and resets its
own timers. The postfix clears the flag again, and a `think` hook clears it too in case `Update`
threw and Harmony skipped the postfix.

Masking the input of vanilla's check, rather than reimplementing its several crew-down branches,
keeps every branch (Permadeath, AutoRestart, the campaign's 2 s / 120 s timers) unchanged. When the
grace ends without a switch, the round ends exactly as vanilla would have. A real admin free-cam is
respected, because a client that was already in free-cam counts as "up" in vanilla too.

## Disconnect and rejoin

- **Disconnect.** LuaCs's `client.disconnected` fires as a prefix on vanilla's disconnect, while
  `client.Character` is still set. CrewSwap records the client as the body's last controller and
  releases it. Because the client no longer owns a body, vanilla never marks it disconnected, so the
  body reverts to a working bot instead of freezing and being killed after `KillDisconnectedTime`.
  It also stops "disconnect to dodge death".
- **Rejoin.** A postfix on `GameServer.OnInitializationComplete` queues the client (LuaCs's
  `client.connected` reports the last connected client, which can be the wrong one when two join
  together). A `think` poll waits until the client is in game, synced and the round is not ending,
  then applies `placement.rejoinTarget`: the character they last played if protect is off and it is
  Free, otherwise their own home body if it is Free for them.
- **New players** spawn through vanilla. Until they have spawned once they have no CCD, and switch
  requests are refused with `nohome`.

## Round end and save

On a level transition, `GameSession.EndRound` runs mission pay, round-end talents and
`GameMode.End` (`MultiPlayerCampaign.End` sets `GameOver`, then calls `CampaignMode.End`). After it
returns, the transition calls `MultiPlayerCampaign.SavePlayers` and then `SaveUtil.SaveGame`. On
save-and-quit the order is reversed: `SavePlayers` and `SaveGame` run first, and `GameServer.EndGame`
then runs `EndRound` / `End` (see [the save-and-quit path](#the-save-and-quit-path)). CrewSwap hooks
each step; the table follows the level-transition order, which is the one the `crewswap.endround`
and `crewswap.endguard` rows describe:

| Step | Patch | What CrewSwap does |
|---|---|---|
| `GameSession.EndRound` | prefix `crewswap.endround` | `CS.roundEnding = true` (no switches or rejoin moves from now on); snapshot each client's home body, because `CampaignMode.End` despawns dead bodies before `SavePlayers`. |
| Mission pay, talents | postfix `crewswap.crewset` on `GameSession.GetSessionCrewCharacters` | Add released home bodies (alive bots with a CCD) to the crew set wherever bots are included, so an idle home gets mission XP and round-end talents like any bot. Pay itself goes to whoever each player is driving. |
| `CampaignMode.End` | prefix/postfix `crewswap.endguard` | Raise the keep-dead guard and **stage** a snapshot of every bot wallet. |
| (inside `End`) | prefix `crewswap.keepdead` on `CrewManager.RemoveCharacterInfo` | While the guard is up, skip vanilla's removal of a dead non-home crew member and record it in `CS.keptDead`. |
| `MultiPlayerCampaign.End` | postfix `crewswap.gameover` | Correct `GameOver` on save-and-quit (below). |
| `SavePlayers` | prefix `crewswap.restore` | **Restore** (below), then the pre-save hooks: keep-dead decisions for the bodies `SavePlayers` will drop, and the pre-save integrity check. |
| `SavePlayers` | postfix `crewswap.restore.post` | Put kept crew back in the roster, revive them, run the post-save integrity check. |
| `MultiPlayerCampaign.Save` | prefix/postfix | Mint ids for new crew, write `<CrewSwap>`, write the mirror. |
| `CharacterInfo.Save` | postfix | Write `crewswap_*` attributes on each `<Character>`. |
| `SaveUtil.SaveGame` | prefixes | Commit staged wallets into records; block the write if a check failed. |
| `GameServer.EndGame` | postfixes | Revive kept crew on an unsaved end; reload the last good save if a write was blocked. |

### The restore

`CS.restoreAll()` runs in the `SavePlayers` prefix:

1. Everyone leaves any body that is not their home. A live borrowed body is released with
   `SW.release` (it must not still be a client's character, because `SavePlayers` snapshots items
   only for bots and then deletes every inventory); a dead or removed one is just let go.
2. A living home goes back to its owner with `SetClientCharacter` (releasing whoever was driving
   it first).
3. A dead home is bound raw (`c.Character = h; c.CharacterInfo = h.Info`), never left nil, because
   vanilla builds a dead player's CCD item data from `client.Character`.
4. A client with no home body (never spawned, or benched) keeps no character.

If the restore throws, `CS.blockSave` is set and the save will not be written.

### Why the restore is in `SavePlayers` and not at round end

The restore must run **after** mission pay and round-end talent effects (so they reach the body
each player was actually driving), must cover the **save-and-quit** path (which calls
`SavePlayers` without a normal round end), and must be a no-op on a failed-round reload (LuaCs's
`roundEnd` hook also fires as a prefix on `GameSession.LoadPreviousSave`). A prefix on
`MultiPlayerCampaign.SavePlayers` meets all three.

### Kept dead crew and revival

Outside Permadeath, a dead non-home crew member is kept rather than deleted (`core/revive.plan`
decides). There are two removal sites:

- `CampaignMode.End`'s dead-body loop calls `CrewManager.RemoveCharacterInfo`, which the
  `crewswap.keepdead` prefix can skip.
- `SavePlayers` removes dead bots too, but no patch on `RemoveCharacterInfo` fires for that call
  site at runtime on a dedicated server (the tiny method is inlined into `SavePlayers`' patched replacement). So
  the `SavePlayers` prefix decides up front, using `revive.dropsAtSave`, which bodies vanilla will
  drop, and the postfix puts any kept info vanilla removed back with `CrewManager.AddCharacterInfo`.

Each kept info is then revived with `R.applyRevive`: the vanilla skill penalty
(`ApplyDeathEffects`) when the round saves and the death was not a disconnect, otherwise just
clearing the cause of death; health data cleared; orders cleared; the dead `Character` reference
dropped; and `PendingSpawnToActiveService = true` so they spawn alive next round. A revive failure
blocks the save, since `CrewManager.SaveMultiplayer` would otherwise drop the unrevived info.

### The save-and-quit path

Save-and-quit differs from a level transition in three ways the code handles explicitly:

- **Order.** `SavePlayers` runs *before* `MultiPlayerCampaign.End`, while `GameSession.IsRunning`
  is still true. `End` sets `GameOver` from "no in-game client has a living character"; after the
  restore, a player whose home is dead or benched has no living character, which would skew it.
  The restore records `CS.restoredBeforeEnd` and whether anyone was alive *before* restoring, and
  the `MultiPlayerCampaign.End` postfix puts back that pre-restore value. It never recomputes
  `GameOver` from a Free-crew rule.
- **Pay.** Mission pay is distributed while the round is closed down, after the restore, so on
  save-and-quit the wallets that receive it are the home bodies'. This is a deliberate trade-off;
  deferring pay across the save was judged not worth the save-critical complexity.
- **Corpse inventory.** On a level transition, `CampaignMode.End` despawns dead bodies first, so a
  kept bot's items are already in a duffel bag in the world and its saved inventory is cleared on
  revival. On save-and-quit, vanilla saves a dead character's inventory from the corpse and deletes
  the world items, so no duffel exists. A bot revived after save-and-quit therefore keeps the
  inventory vanilla saved from its corpse, matching what vanilla does for a dead player's character
  on that path. Nothing is duplicated either way.

### Unsaved round ends

A vote to end, a crew-down failure or an admin end without saving never reaches `SavePlayers`.
The `GameServer.EndGame` postfix revives kept crew on the `unsaved` path (no skill penalty, since
vanilla only penalizes deaths when the round saves) unless a save was just blocked (the campaign is
about to be reloaded anyway), then drops the staged wallets, so bot wallets revert together with
the player characters' CCD wallets.

## After the round

The next `roundStart` resets `CS.roundEnding`, the kept-dead list, staged wallets and the
save-block flags, and the cycle starts again. On the client, the `roundEnd` hook forgets the
crew-list rows (they are rebuilt before the next `roundStart` fires) and the control tracker.

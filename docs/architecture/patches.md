# Patches and LuaCs gotchas

CrewSwap changes vanilla behaviour only through `Hook.Patch` (Harmony prefixes and postfixes driven
from Lua) and `Hook.Add` (LuaCs events). This page lists every patch, why it exists, and the LuaCs
behaviours that shaped how they are written.

Every server patch is installed through `P.patch(id, class, method, types, fn, when)` in
`server/patch.lua`; the id is the first column below. "Before" is a prefix, "After" a postfix.
All 36 server patches are installed at load. Patches are never removed, so every callback is gated on mod state: most on `CS.active`; the
identity layer on `CS.campaignOk` (and the XML constructor / `MultiPlayerCampaign.Load` postfixes
not at all, because they run before activity is known); the round-end restore on
`CS.active or CS.lockdown`, so a lockdown save still gets the vanilla shape; and the
safety/save-blocking patches on their own block and lock flags, so they still work during a
lockdown. A few others gate on the state they handle (the kill postfix on a pending death
context, the game-over postfix on a restore that already ran). The end-round prefix
(`crewswap.endround`) sets `CS.roundEnding` ungated and uses the restore's `CS.active or
CS.lockdown` gate only for the home snapshot. The wallet commit (`crewswap.wallets.save`) is gated
on the save's own flags (`isSavingOnLoading`, `CS.blockSave`), with activity checked inside the
wallet snapshot. Don't "fix" these gates to `CS.active`: the differences are what keep saves safe. Cleanup callbacks that only lower flags or clear per-round state (`crewswap.endguard.post`,
`crewswap.endgame`, `crewswap.crewdown.post`, and the safety revert/load postfixes) are
deliberately ungated, so state never sticks after a lockdown.

## Server patches

### Bodies and identity

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.forceai` | `Barotrauma.Character.Create` (the 10-parameter overload: `CharacterPrefab, Vector2, String, CharacterInfo, UInt16, Boolean, Boolean, Boolean, RagdollParams, Boolean`) | Before | Set `hasAi = true` for campaign remote-player spawns, so every crew body is an `AICharacter` that can be handed back to the AI. |
| `crewswap.ci.save` | `Barotrauma.CharacterInfo.Save(XElement)` | After | Add `crewswap_id` and the record's attributes to the `<Character>` element vanilla returns. |
| `crewswap.ci.ctorxml` | `Barotrauma.CharacterInfo..ctor(ContentXElement, Identifier)` | After | Read them back when an info is built from XML (into `CS.pending`). |
| `crewswap.mpc.load` | `Barotrauma.MultiPlayerCampaign.Load(XElement)` | After | Read `<CrewSwap>`, rebuild the registry, detect duplicate ids, fill gaps from the mirror. `GameMode` is not set yet here, so it works on the patch instance. |
| `crewswap.mpc.save.pre` | `Barotrauma.MultiPlayerCampaign.Save(XElement, Boolean)` | Before | Returns early unless `CS.campaignOk`. Detect a new campaign; bind every live crew member to a sid (minting new ones only while active) before `CharacterInfo.Save` runs. |
| `crewswap.mpc.save.post` | same | After | Write `<CrewSwap>` into the `MultiPlayerCampaign` element; write the mirror file. |

### Switching, joining and the crew-down window

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.join` | `Barotrauma.Networking.GameServer.OnInitializationComplete(NetworkConnection, String)` | After | Reliable "this client finished joining", used for rejoin placement. LuaCs's `client.connected` reports the last connected client, which can be the wrong one when two join together. |
| `crewswap.crewdown.pre` | `Barotrauma.Networking.GameServer.Update(Single)` | Before | While the grace window is open, set `UsingFreeCam` on clients so vanilla's crew-down test sees someone up. |
| `crewswap.crewdown.post` | same | After | Clear the flags again (a `think` hook does too, in case `Update` threw). |

### Round end, keep-dead and wallets

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.endround` | `Barotrauma.GameSession.EndRound` | Before | Mark the round as ending; snapshot each client's home body before `CampaignMode.End` despawns the dead. |
| `crewswap.crewset` | `Barotrauma.GameSession.GetSessionCrewCharacters` | After | Add released home bodies to the crew set when bots are included, so idle homes get mission XP and round-end talents like bots. |
| `crewswap.endguard` | `Barotrauma.CampaignMode.End(CampaignMode+TransitionType)` | Before | Raise the keep-dead guard; stage bot wallets. |
| `crewswap.endguard.post` | same | After | Lower the guard. |
| `crewswap.keepdead` | `Barotrauma.CrewManager.RemoveCharacterInfo(CharacterInfo)` | Before | While the guard is up, skip the removal of a dead non-home crew member (`PreventExecution`). |
| `crewswap.gameover` | `Barotrauma.MultiPlayerCampaign.End(CampaignMode+TransitionType)` | After | On save-and-quit, put back the pre-restore `GameOver` value. |
| `crewswap.restore` | `Barotrauma.MultiPlayerCampaign.SavePlayers` | Before | The restore, then keep-dead decisions and the pre-save integrity check. |
| `crewswap.restore.post` | same | After | Put kept crew back, revive them, post-save integrity check. |
| `crewswap.endgame` | `Barotrauma.Networking.GameServer.EndGame` | After | On an unsaved end, revive kept crew without a penalty and drop staged wallets. |
| `crewswap.wallets.save` | `Barotrauma.SaveUtil.SaveGame(CampaignDataPath, Boolean)` | Before | Commit staged wallets into records for a save that is really written. |
| `crewswap.wallets.init` | `Barotrauma.CrewManager.InitRound` | After | Restore bot wallets at round start. |

### Death

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.kill.pre` | `Barotrauma.Character.KillProjSpecific` | Before | Hide the driver (`driver.Character = nil`) so vanilla's driver-keyed death effects (`ApplyPermadeath`, `SpectateOnly`, RetainExperience, the traitor message) do not hit the wrong character. |
| `crewswap.kill.post` | same | After | Give the driver back and apply the effects to the character that died; undriven permadeath. |
| `crewswap.respawn.detach` | `Barotrauma.Networking.RespawnManager.RespawnCharacters(RespawnManager+TeamSpecificState)` | Before | Outside Permadeath, let go of a dead borrowed corpse so respawn does not despawn it. |
| `crewswap.retainxp.save` | `Barotrauma.MultiPlayerCampaign.SaveExperiencePoints` | Before | Skip it: RetainExperience is keyed per client, which switching would turn into free XP. |
| `crewswap.retainxp.get` | `Barotrauma.MultiPlayerCampaign.GetSavedExperiencePoints` | Before | Return 0 (an `int` method: the number is the Lua return value). |
| `crewswap.takeover` | `Barotrauma.Networking.GameServer.ReadTakeOverBotMessage` | Before | Route vanilla `TAKEOVERBOT` through the CrewSwap switch; let hire/bench ids through only where they cannot discard a living home. |
| `crewswap.takeover.post` | `Barotrauma.Networking.Client.TryTakeOverBot` | After | When vanilla did take a bot over, record it as the player's new home. |

### Safety

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.safety.kill` | `Barotrauma.Character.KillProjSpecific` | After | Note a Permadeath crew death as a legitimate removal. |
| `crewswap.safety.fire` | `Barotrauma.CrewManager.FireCharacter(CharacterInfo)` | Before | Note a firing as legitimate. |
| `crewswap.safety.discard` | `Barotrauma.MultiPlayerCampaign.DiscardClientCharacterData` | Before | Note vanilla's CCD discard ("create new character", takeovers) as legitimate. |
| `crewswap.safety.save` | `Barotrauma.SaveUtil.SaveGame(CampaignDataPath, Boolean)` | Before | Prevent the disk write when a check failed. |
| `crewswap.safety.revert` | `Barotrauma.Networking.GameServer.EndGame` | After | After a blocked write: lock down, reload the last good save. |
| `crewswap.safety.load.pre` | `Barotrauma.MultiPlayerCampaign.LoadCampaign(CampaignDataPath, Client)` | Before | Lift an integrity lock for the duration of a load so save-on-load writes the ids. |
| `crewswap.safety.load` | same | After | Put the lock back; take a new baseline; lock on duplicate ids in the loaded save. |
| `crewswap.safety.lobby` | `Barotrauma.Networking.GameServer.TryStartGame` | Before | Refuse to start a round while an integrity lock holds (including while it is lifted for a load), or inside a load whose save has duplicate ids. |

### Admin

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.hire.owner` | `Barotrauma.CampaignMode.TryHireCharacter` | After | In `own` pool mode the hirer owns the new hire (not a Permadeath replacement, which becomes the buyer's home). |

## Client patches

Installed directly with `Hook.Patch` inside `pcall` by `client/main.lua` (a failure sets
`CSC.probesOk = false` instead of switching anything off, and the hello reports it):

| Id | Target | When | Why |
|---|---|---|---|
| `crewswap.click` | `Barotrauma.CrewManager.CharacterClicked` | Before | A click on a Free crew row sends a switch request and prevents vanilla's click. A click on a not-Free, undriven row also sends a request (so the denial explains why) but lets vanilla's click run. |
| `crewswap.row` | `Barotrauma.CrewManager.AddCharacterToCrewList` | After | Remember each row and style it (greyed and labelled when taken, dimmed when not Free for this player). |

The client also calls `LuaUserData.MakeFieldAccessible` on `CrewManager.crewList` (through a
`RegisterType` of `CrewManager`) to reach the crew list's content, and looks up seven static
classes with `CreateStatic` (`Timing`, `CoroutineManager`, `ConversationAction`, `HintManager`,
`TabMenu`, `GameSession`, `ChatBox`). Any of these failing also sets `CSC.probesOk = false`.

## Events (`Hook.Add`)

| Event | Used for |
|---|---|
| `roundStart` | Active recompute, notices, spawn audit, live-list check, placement, state broadcast, integrity snapshot, per-round resets (server); control tracker reset (client). |
| `roundEnd` | Client only: forget crew-list rows. Not used on the server, because LuaCs also fires it on `GameSession.LoadPreviousSave`. |
| `think` | Join poll, hello watchdog, death and crew-down safety nets (server); control-change detection and row rebuilds (client). |
| `chatMessage` | `!crewswap` commands; returning `true` swallows the message. |
| `client.disconnected` | Release the body; forget the client's hello state. |
| `character.created` | Respawn AI audit; bot wallet restore for bodies created outside `InitRound`. |
| `character.death` | Broadcast state when a crew member dies. |

## Accessibility and registration

Server Lua must register some types before use, and a few private members are opened:

- `LuaUserData.RegisterType` for `System.Version`, `AssemblyInfo`, `System.Guid`,
  `Barotrauma.MultiPlayerCampaign`, `Barotrauma.SaveUtil`, `Barotrauma.IO.Directory`,
  ``System.Collections.Immutable.ImmutableHashSet`1`` (the open generic; closed types inherit it)
  and `Barotrauma.Networking.GameServer+TryStartGameResult`.
- `MakeFieldAccessible(MultiPlayerCampaign, 'characterData')`: the list of CCDs.
- `MakePropertyAccessible(MultiPlayerCampaign, 'GameOver')`: it has a private setter.
- Selftests also register `Barotrauma.CrewManager`, `Barotrauma.CampaignMode`,
  `Barotrauma.CharacterCampaignData`, `Barotrauma.Wallet` and `Barotrauma.Networking.IReadMessage`
  to probe their members.
- Enum tables come from `LuaUserData.CreateEnumTable` for `Barotrauma.MultiPlayerCampaign+NetFlags`,
  `Barotrauma.Networking.RespawnMode`, `GameServer+TryStartGameResult` and `Barotrauma.CharacterType`.

## LuaCs gotchas

These were learned from the LuaCs source for the targeted build and from testing. Most of them fail
*silently* if ignored, so they are worth reading before touching any patch.

### Read arguments with brackets

Arguments live in the parameter table under their exact C# parameter names, which are
case-sensitive: `p['characterInfo']`, `p['causeOfDeath']`, `p['isSavingOnLoading']`. An unknown or
misspelt name throws inside the patch (and, in a prefix, fails open). The table also has members of
its own: `ReturnValue`, `PreventExecution`, `OriginalReturnValue`.

In Lua `p.x` and `p['x']` compile to the same lookup, so this is a convention rather than a
different operation, but it is one the code follows everywhere: **brackets for the patched
method's arguments, dots for the table's own members.** That makes it obvious at a glance which
names must match the C# signature exactly, and keeps an argument that happens to share a name with
a member from being misread.

### Bare `return` on non-void methods

A callback's own return value becomes the method's result on a non-void method. `return nil` is
not "no value": it sets the result to null (and a null for a value-type return faults). End
callbacks with a bare `return` or no return at all, and only return a value deliberately:

- `crewswap.retainxp.get` returns `0` to replace an `int`;
- `crewswap.safety.lobby` returns `TryStartGameResult.GameAlreadyStarted`;
- the client's `crewswap.click` returns `true` after setting `PreventExecution`.

This is why most callbacks are wrapped by a helper (`safe`, `guard`) or an inline `pcall` and
return nothing. The few trivial flag-setting prefixes (`crewswap.retainxp.save`,
`crewswap.safety.save`, `crewswap.safety.load.pre`) are unwrapped, and `crewswap.retainxp.get`,
`crewswap.safety.lobby` and the client's `crewswap.click` return values deliberately.

### Numbers need wrappers when written back

Writing a Lua number into a parameter stores a boxed double, and the write-back does no numeric
conversion, so an `int`, `ushort` or `float` parameter throws `InvalidCast`. Wrap them
(`Int32(x)`, `UInt16(x)`, `Single(x)`), or prefer the callback's return value, which is converted
properly. CrewSwap currently writes back only a Boolean (`p['hasAi'] = true`), which needs no
wrapper.

### `pcall` (almost) every patch

- A wrong signature after a game update throws at `Hook.Patch` time. `P.patch` catches it and turns
  it into `CS.fail`.
- A Lua error inside a **prefix fails open**: the original method still runs. Never let save-critical
  safety depend on a prefix succeeding without a later check. This is why the spawn audit verifies
  `forceai`, and why the post-save integrity check exists at all.
- Postfixes run even when a prefix set `PreventExecution`, so a postfix checks the module's own
  state or `p.OriginalReturnValue` rather than assuming the original ran.

### Enums are numbers

Enum values reach Lua as numbers (or as boxed values of the enum type, which compare equal).
Compare against `CauseOfDeathType.Disconnected`, `CharacterTeamType.Team1` or a
`LuaUserData.CreateEnumTable('Barotrauma.Networking.RespawnMode')` entry, never against
`tostring(x) == 'Name'`. Flag enums are tested arithmetically (the crew-set postfix uses
`ty % 2 == 1` for the `Bot` flag). The selftest `enum-numbers` checks this assumption.

### CLR collections arrive as copies, iterators or userdata

A C# `List<T>` reaches Lua as a **copied** table: mutating it changes nothing in the game
(`Inventory.DraggingItems` has no usable `Clear` for this reason). Converted `IEnumerable`s arrive
as iterator functions, and some results (a LINQ `Concat`, an immutable set) arrive as userdata
enumerables. Always go through `G.list(x)`, which handles all three, and never mutate the result
expecting the game to see it. Immutable collections return a new instance from `Add`, so the
crew-set postfix assigns `p.ReturnValue = result:Add(ch)`.

### Interface parameter types do not resolve

A parameter-type string naming an interface (for example `Barotrauma.Networking.IReadMessage`) never
matches. Where the method name is unique, omit the type list entirely (as for
`ReadTakeOverBotMessage`). Overloads need the full list with CLR names: nested types use `+`
(`Barotrauma.CampaignMode+TransitionType`), and by-ref parameters a `ref ` or `out ` prefix.

### `Hook.RemovePatch` is broken

In the targeted LuaCs build, `Hook.RemovePatch` passes the class name as the identifier, so it only
removes a patch whose identifier happens to equal its class name. CrewSwap never unpatches; it gates
every callback on mod state instead (see the top of this page). (A Lua reload or server stop clears all Lua patches anyway.)

### Inlined methods can bypass a patch

A tiny method that the JIT inlines into its caller is not patched at that call site. CrewSwap hit
this with `CrewManager.RemoveCharacterInfo` inside `SavePlayers`, and works around it by deciding in
the `SavePlayers` prefix and repairing in its postfix (see
[Lifecycle](lifecycle.md#kept-dead-crew-and-revival)).

### Other things to know

- **Private methods on a base class** are not found; name the declaring class.
- **Coroutine bodies** cannot be usefully patched (only the enumerator factory is); hook the
  observable effects instead.
- **Time** is `LuaUserData.CreateStatic('Barotrauma.Timing').TotalTime`.
- **`require` is shared by every mod**, hence the `crewswap.` prefix on every module.
- **Sandboxed client Lua** can still `Hook.Patch` any game type, but can only register
  `Barotrauma.*` and a few system types; `AssemblyInfo`, for example, is out of reach.

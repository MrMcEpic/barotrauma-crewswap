# Architecture overview

This part of the book is for people who want to read, review or change the CrewSwap code. It
assumes you know Barotrauma's multiplayer campaign from the player side and have at least skimmed
the LuaCs documentation. The player and admin guides describe *what* the mod does; these pages
describe *how* and, just as importantly, *why*.

The code under `mod/CrewSwap/` is the source of truth. If a page here disagrees with it, the code
wins, and a pull request fixing the page is very welcome.

## The problem

Vanilla multiplayer gives each player exactly one character. Outside Permadeath's "take over a
bot" prompt, the only built-in way to control a bot is the cheat-flagged `control` console command,
which needs `enablecheats` (and so disables achievements). Worse, it corrupts the campaign: at round end `MultiPlayerCampaign.SavePlayers`
saves the bot as the player's own character, removes it from the crew, and erases the player's
real character.

CrewSwap's job is to make switching feel like singleplayer while guaranteeing that the campaign
save never loses or duplicates a character.

## Goals

- **Switch by clicking a crew-list row.** Mid-round, a player can take any *Free* crew member.
- **The body you leave keeps working.** It becomes a bot again and carries on with its orders,
  inventory and what it was doing.
- **Everything belongs to the character.** Skills, XP, talents, inventory, health and money stay
  with each character through switches, round ends, save-and-quit and server restarts.
- **Death is not the end of your turn.** When the character you are driving dies, you can jump
  into another Free crew member.
- **Two toggles**: the crew *pool* (`shared` or `own`) and *home protection* (on or off).

## Anti-goals

These are failures even if switching "works":

1. **Losing a levelled character.** Nothing may drop a character from the save except permanent
   death (Permadeath) or firing. Outside Permadeath this is stricter than vanilla, which deletes
   dead bots.
2. **Duplicating a character.** No character may be saved twice or spawn twice.
3. **Breaking normal play.** With nobody switching, a campaign behaves like vanilla. Players
   without the mod are told why they cannot switch instead of silently desyncing.
4. **Free stuff from switching.** No free renames, no money moved between characters and no XP
   inflation from talents that vanilla tracks per player.

## Constraints

- **Pinned versions.** The build targets Barotrauma 1.13.4.x and was tested against one LuaCs
  commit (`EXPECT_GAME` and `EXPECT_LUACS` in `shared/build.lua`). On a game-version mismatch the
  mod installs no patches and the campaign runs as plain vanilla; a different LuaCs commit only
  logs a warning, and the patch-install audit and self-tests are the guard (see
  [Safety](safety.md)). Because of this, nothing the mod stores may ever be *required* to load or
  play a save.
- **Pure Lua, sandboxed on clients.** No `<Assembly>`, no `RunUnrestricted="true"`. Clients run sandboxed Lua
  unless they opt into C#; shipping any C# or unrestricted Lua forces a per-session prompt, and a
  player who declines silently runs without the *whole* package. Sandboxed Lua still has
  `Hook.Patch`, `Networking` and every auto-registered `Barotrauma.*` type, which is all CrewSwap
  needs. Server-side Lua runs unsandboxed (the version check relies on that). Client code works in
  both modes, because whether a client is sandboxed depends on its history.
- **The server is authoritative.** Clients only *ask*. Every decision that touches the campaign is
  made, validated and logged on the server.
- **Admin control is in-game chat.** Many hosting setups ignore the dedicated server's stdin
  console, so all admin commands are `!crewswap ...` chat messages.

## The core design: "home + pool"

CrewSwap keeps vanilla's storage exactly as it is and only moves **control** during a round.

- Each player's **home** character stays where vanilla keeps it: in that client's
  `CharacterCampaignData` (CCD), keyed by account id.
- Every other crew member stays in the `CrewManager` roster (active crew plus the reserve bench).
- During a round, any client may drive any Free crew body.
- **Before vanilla saves**, the mod puts storage back into the shape vanilla expects: every client
  back in their own home body, borrowed bodies left as bots. Vanilla's own save path then stays
  responsible for inventory, health, orders and skills.

This is the least invasive model that avoids losing or duplicating characters. An earlier C# mod
for the same idea (Multiplayer Crew Manager) instead turned every crew member into a fake client
CCD and suppressed crew-manager saving, which made campaigns hard to convert back to vanilla.
"Home + pool" means a CrewSwap campaign is always a valid vanilla campaign: turn the mod off and
the save simply loads.

Everything else in the mod exists to make that one restore safe:

```text
               round running                         round ends
   +------------------------------------+   +-------------------------------+
   |  any client  --drives-->  any Free |   |  GameSession.EndRound         |
   |  crew body (AI-capable)            |   |   mission pay -> driven body  |
   |                                    |   |  CampaignMode.End             |
   |  vanilla storage untouched:        |   |   dead NON-home crew kept     |
   |    homes  -> CCDs                  |   |  MultiPlayerCampaign          |
   |    others -> CrewManager roster    |   |    .SavePlayers  (prefix)     |
   |                                    |   |   RESTORE: everyone home,     |
   |  death effects redirected to the   |   |   borrowed bodies -> bots     |
   |  character that actually died      |   |   integrity check (pre/post)  |
   +------------------------------------+   |  SaveUtil.SaveGame            |
                                            |   blocked if a check failed   |
                                            +-------------------------------+
```

## Why every crew body is spawned AI-capable

Vanilla spawns a client's own body as a plain `Character` with `hasAi: false`. A plain body has no
`HumanAIController`, so when its player switches away it would stand still forever and never count
as a bot. CrewSwap forces `hasAi = true` for campaign player spawns (a prefix on
`Barotrauma.Character.Create`), so *every* crew body is an `AICharacter`. Vanilla already supports
an `AICharacter` driven by a remote player: the AI is suspended while `IsRemotePlayer` is set and
resumes on its own when control is cleared. An audit at round start and on every
`character.created` checks that it really worked and switches the mod off if not.

The trade-off: player bodies are AI characters, so attacks made by players are not written to the
server's attack log, and nearby bots react to an attack on a player body as they would to one on a
bot. Both are listed in [Differences from vanilla](../guide/vanilla-differences.md).

## Components

The Lua lives under `mod/CrewSwap/Lua/crewswap/` and is split by *where it runs* and *whether it
touches the game*:

```text
 shared/   build.lua          version stamp + expected game/LuaCs versions
 core/     pure Lua: plain tables in, plain tables out. No game globals. Unit-tested.
           rules  registry  mirror  placement  grace  integrity  revive
           commands  statecodec  version
 server/   adapters: every server game call and every Hook.Patch
           main (autorun, version gate, CS.active)
           game (views of live objects)   patch (Hook.Patch wrapper)   selftest
           spawn  identity  switch  presence  roundend  death  crewdown  safety  admin
 client/   main.lua (autorun): crew-list click, row styling, housekeeping, messages
```

Data flows one way across the core/adapter boundary: an adapter reads live game objects, turns
them into plain *views* (for example `G.crewViews()` in `server/game.lua`), asks a core module for
a decision, then applies the decision to the game. That keeps every decision testable with stock
`lua5.2`, without a game in sight. See [Modules](modules.md) for each file and
[Testing](testing.md) for how this is exercised.

Global mutable state lives in two tables: `CS` on the server (set up by `server/main.lua`) and
`CSC` on the client (set up by `client/main.lua`). Modules expose functions on these tables when
another module needs to call them across a dependency edge (for example `CS.sidOfInfo`,
`CS.runCheck`, `CS.noteLegit`).

## The `CS.active` switch

Patches cannot be removed reliably at runtime (`Hook.RemovePatch` is broken in the targeted LuaCs
build; see [Patches](patches.md)). So instead of unpatching, every callback is gated on mod state: most on `CS.active`; the
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

The main flags:

```lua
CS.campaignOk = CS.versionOk and isMultiplayerCampaign and not ironman
CS.active     = CS.campaignOk and not CS.lockdown
```

`CS.recomputeActive()` in `server/main.lua` recomputes it at load, at every round start, after a
campaign load and before every save. `CS.campaignOk` deliberately ignores a lockdown: while the mod
is locked down, the identity layer still writes back the ids and records it already holds, so a
vanilla save during a lockdown never throws away CrewSwap's data.

## Design decisions worth knowing up front

- **Ironman is off.** Vanilla has no Ironman game-over; Ironman only adds an immediate per-character
  disk write keyed on the *driver*. Supporting it properly means writing bot deaths to disk
  mid-round and inventing a campaign-over state: new save-critical code for a mode the authors did
  not need. While Ironman is on, CrewSwap stays inactive for that campaign and says so in chat.
- **Money is per character.** Vanilla only persists wallets for player CCDs. CrewSwap stores every
  bot's balance and salary on its own record, so switching never moves money. See
  [Persistence](persistence.md).
- **Non-home crew come back.** Vanilla deletes every dead bot. Outside Permadeath, CrewSwap keeps a
  dead non-home crew member in the roster, applies vanilla's death skill penalty, and has them
  spawn alive next round, just as a player's character would.
- **RetainExperienceForNewCharacter is disabled.** Vanilla tracks it per client, so with switching
  it would hand a borrowed body's XP to the player's next character.
- **The vanilla "take over a bot" request is routed through CrewSwap** for crew already in the
  world, because vanilla's `TryTakeOverBot` discards the client's CCD, and after a switch that could
  be a living home.
- **No custom backup copies.** Instead of copying save files around, the mod raises vanilla's own
  rolling backup count to 20, which admins can already restore from the lobby.
- **Not kicking players without client-side LuaCs.** They can still play the campaign as vanilla;
  they are told once how to enable switching.

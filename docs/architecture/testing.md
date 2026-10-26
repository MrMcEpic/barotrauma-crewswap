# Testing

CrewSwap is tested at three levels:

1. **Unit tests** (294 at 0.9.0) run off-game with stock Lua 5.2 against the pure core modules
   and, with fake game globals, against the server and client adapters.
2. **An in-game selftest** (23 checks plus one live check) proves, on a real server, that every API
   the mod relies on exists and behaves as assumed.
3. **Manual play tests** with real clients, following the checklist table below.

At 0.9.0 the server-side logic has passed all unit tests, all selftests and an automated
18-scenario run against a real dedicated server (transitions, save-and-quit, unsaved ends, kept
dead crew, wallets through restarts and Lua reloads, Permadeath, Ironman, firing, lockdown and
recovery). **Live two-player switching has not yet been fully play-tested**, which is why the
release is labelled beta.

## Unit tests

### Running them

From the repository root:

```sh
lua5.2 tests/run.lua
```

On Debian or Ubuntu, `sudo apt install lua5.2`. The runner prints `PASS <name>` / `FAIL <name>: ...`
for every test, then `N passed, M failed`, and exits non-zero on any failure.

Why Lua 5.2: LuaCs runs MoonSharp, which implements Lua 5.2 semantics (all numbers are doubles, no
integer division operator, no `utf8` library, `goto` and `bit32` available). Testing against stock
5.2 catches the same syntax and semantics mistakes. Do not use 5.3+ features in mod code.

### How the runner works

`tests/run.lua` sets `package.path` to `mod/CrewSwap/Lua/?.lua;tests/?.lua;...`, so tests load the
real modules with the same `require('crewswap.core.rules')` names the game uses. It runs every
`tests/test_*.lua` in sorted order. Each file returns a table of named test functions; each function
gets a small assertion helper `T`. An illustrative test file (the test names are examples, not
real tests in the suite):

```lua
local rules = require('crewswap.core.rules')
local revive = require('crewswap.core.revive')
local F = require('fakes')

return {
  ['dead crew is not Free'] = function(T)
    T.eq(rules.isFree(F.view({ alive = false }), { pool = 'shared', protect = true }, 'acct:A'), false)
  end,
  ['revive.plan rejects an unknown cause'] = function(T)
    T.err(function() revive.plan({ cause = 'bogus' }, 'transition') end)
  end,
}
```

- `T.eq(actual, expected, msg)`, `T.ok(value, msg)`, `T.err(fn, msg)` (expects `fn` to raise).

### Pure core modules

The `core/` modules take and return plain tables, so their tests are direct: build an input, call
the function, compare the output. They cover, for example, the order of denial reasons, own-pool
claiming, placement with competing claims, the mirror's two-pass match with ambiguous keys, every
integrity problem kind with and without legitimate removals, and every revive path.

### `tests/fakes.lua`

Shared doubles:

- `F.view(o)`: a Free, eligible crew view; override any field with `o`.
- `F.requester(o)`: an eligible switch requester.
- `F.buffer()`: a network message double with `Write*`/`Read*` for `UInt16`, `String`, `Boolean` and
  `Single`. A read of the wrong type, or past the end, raises, so codec mismatches fail loudly.

### Adapter tests with fake game globals

The server and client modules call game globals (`Game`, `Hook`, `LuaUserData`, `Networking`,
`Character`, `Client`, ...). Their tests (`test_switch.lua`, `test_roundend.lua`, `test_death.lua`,
`test_safety.lua`, `test_client.lua` and others) build a small fake world in `_G` per test:

- clear the module from `package.loaded` and re-require it, so each test starts clean;
- install fakes that record what the module did (`Hook.Add` and `Hook.Patch` capture the callbacks,
  `SetClientCharacter` records calls, `Networking.Send` records messages);
- call the captured callbacks directly, the way the game would, and assert on the recorded effects.

`LuaUserData.IsTargetType` is faked by giving fake objects a `types` set, so code that checks
`IsTargetType(ch, 'Barotrauma.AICharacter')` works unchanged. These tests cover the call sequences
that matter: the two-step `SetClientCharacter`, the restore order, keep-dead and revive on each save
path, wallet staging and commit, the kill redirect, the block-reload-lock sequence and the client's
click guards.

What unit tests cannot prove: that a patch target resolves in the real game, that a CLR type
converts the way the fake assumes, or how vanilla code reacts. That is the selftest's job.

## In-game selftest

### Enabling it

Create an empty file named `selftest` in the `CrewSwap` folder of the server's save folder
(`Game.SaveFolder`, the folder that contains `Multiplayer/`):

```sh
touch "<SaveFolder>/CrewSwap/selftest"
```

Restart the server. One second after load, the server console shows a line per check and a summary:

```text
[CrewSwap] SELFTEST PASS timing
[CrewSwap] SELFTEST PASS enum-numbers
...
[CrewSwap] SELFTEST done: 23 passed, 0 failed, 0 skipped
```

Delete the file to turn it off. The selftest runs before any campaign is loaded; it creates
throwaway `CharacterInfo` objects and temporary files and cleans up after itself, but
`config-roundtrip` briefly rewrites `config.txt` (and puts the real settings back), so run it on a
test server or between sessions.

### The checks

Each module registers its own checks with `ST.add(name, fn)`. A check returns `true` (PASS),
`'skip', why` (SKIP), or anything else / raises (FAIL).

| Module | Checks |
|---|---|
| `selftest` | `timing` (`Timing.TotalTime` is a number), `enum-numbers` (`CauseOfDeathType.Disconnected` is a number) |
| `game` | `list-convert` (`G.list` on `Character.CharacterList` and a plain table) |
| `spawn` | `create-sig-resolves` |
| `identity` | `ci-save-attr` (`CharacterInfo.Save` writes `crewswap_*`), `ci-ctor-read` (the XML constructor reads them back), `mirror-io` (mirror write/read round trip, no `.tmp` left) |
| `switch` | `state-encode`, `ccd-api` (`SetClientCharacterData`, `GetClientCharacterData`, `RemoveCharacterInfo` exist), `crew-views` |
| `presence` | `join-patch-resolves` |
| `roundend` | `roundend-patches`, `crew-set-add` (immutable set `Add`/`Contains`/`Count` behave), `crew-set-postfix` (the flag enum arrives as a usable number), `revive-apply` (the revive on a real `CharacterInfo`) |
| `death` | `death-patches`, `death-api` (`ApplyPermadeath`, `Bank`, `IncrementLastUpdateIdForFlag`, wallet and `IReadMessage` members) |
| `safety` | `safety-patches`, `safety-backups` (`MaxBackupCount` is 20), `safety-api`, `safety-runcheck` |
| `admin` | `config-roundtrip`, `hire-signature` |

Separately, on the first round of any campaign, `G.checkLiveList()` prints
`SELFTEST PASS live-crew-list` or `SELFTEST FAIL live-crew-list` (which also switches the mod off).
This one always runs, with or without the marker file.

### Other console lines worth checking after a change

- `[CrewSwap] patches installed: 36/36`
- `[CrewSwap] round start, active: true` in a campaign round
- no `[CrewSwap] FAIL` lines and no `... error:` lines
- `identity: save: minted 0 new ids for N crew` on saves after a restart (non-zero only right after
  new hires)

## Manual test checklist

The behaviours that need real players are tested by hand on a throwaway campaign. The table below
*is* the checklist: each row is an area to play through, with the chat and console lines described
on the guide pages ([Playing](../guide/playing.md), [Admin commands](../guide/admin.md),
[Troubleshooting](../guide/troubleshooting.md)) as the expected results.

| Area | What is checked |
|---|---|
| Install and handshake | The client downloads the mod and logs the same build as the server; `hello sent ... probes ok`; a client without client-side LuaCs gets the 90 s notice and is not kicked. |
| Activity | Active in a normal multiplayer campaign; inactive (with the notice) in Ironman; inactive in sandbox and mission rounds, including a sandbox round right after a campaign; the version-mismatch and FAIL notices. |
| Switching | Click a bot to take it; "Now playing"; taken rows greyed and labelled; the body you left resumes its orders; 3 s cooldown; dragging rows and order buttons do not switch; two players clicking the same bot at once; no switching during the round-end summary; first-time joiners must spawn once. |
| Presence | Disconnect hands the body to the AI (and it is not killed later); rejoin with protect on and off; round-start placement with protect on (everyone home) and off (last played). |
| Round end | Level transition and save-and-quit with players in borrowed bodies: everyone stored once, items and skills kept; idle homes get mission XP. |
| Dead crew | A dead bot comes back next round with the skill penalty (transition) or without (unsaved end); items in a duffel bag after a transition. |
| Wallets | A bot's money survives a transition and a restart; an unsaved end reverts it with the player characters'. |
| Death | Death in a borrowed body: corpse stays, switch on at once; vanilla respawn of the home; Permadeath: the dead character is permanently dead, the driver is not made a spectator, homes' money banked, a new home adopted; undriven permadeath. |
| Crew down | The 120 s grace window with its three messages; switching in cancels it; nobody switching ends the round as vanilla. |
| Safety | The forced integrity failure: nothing written, reload, lobby held, `!crewswap check` lifts it; data kept through a lockdown; firing and permadeath across two rounds produce no false alarm; vanilla "create new character" produces no false alarm. |
| Admin | Commands never appear in chat; non-admins refused; settings persist across a restart; own pool: hiring, first-play claims, `owner` reassignment, hires made before own mode. |
| Restarts | A server restart and a Lua reload mid-campaign keep every character's id, level and money. |

If you run any of these rows on your own server, an issue per row describing what you saw (with the relevant
`[CrewSwap]` console lines) is extremely helpful, especially for the two-player items.

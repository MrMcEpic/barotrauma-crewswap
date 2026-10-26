# Networking

The client half of CrewSwap is small: it shows which crew members are taken, turns a click on a
Free row into a request, and tidies up after the player's own control changes. Everything else is
decided on the server. The two halves talk through LuaCs `Networking` messages.

## How the mod reaches clients

The whole `mod/CrewSwap/` folder is a content package that the server requires and sends to every
joining client (or that players subscribe to on the Workshop). Lua files do not count as
multiplayer-synced content, so the package contains one synced file,
`Content/crewswap_sync.xml`, an empty `<Items></Items>` item file. That is enough for the game to
treat the package as required and to offer the download.

The package hash covers content files, the name and `modversion`, **not** the Lua. A code change
without a `modversion` change would let clients keep a cached copy with stale scripts. That is why
every release gets a new `modversion` (stamped by `tools/package.sh`) and why the client and server
also compare `BUILD` in the hello.

A client without client-side LuaCs still receives the package but never runs its Lua. It can play
the campaign as vanilla; it just cannot switch.

## Messages

All messages are reliable LuaCs net messages. Characters are identified by **entity id**
(`Character.ID`, a `UInt16`). Account ids and stable ids are never sent to clients; the only
player-identifying data that goes out is the controller's display name, which every client can see
in the crew list anyway.

| Name | Direction | Payload | Meaning |
|---|---|---|---|
| `crewswap.hello` | client → server | `String` BUILD, `Boolean` probesOk | "My CrewSwap Lua is running, this is my build, and my patches installed." |
| `crewswap.hello?` | server → client | (empty) | "I have no hello from you, please send one." |
| `crewswap.state` | server → client | `UInt16` count, then per crew member: `UInt16` entity id, `String` controller name (`''` if none), `Boolean` free | The crew as this client should see it. |
| `crewswap.request` | client → server | `UInt16` entity id | "I want to drive this character." |
| `crewswap.denied` | server → client | `String` reason, `Single` extra | A request was refused; `extra` is the seconds left for `cooldown`, otherwise 0. |

The `crewswap.state` layout is implemented once, in `core/statecodec.lua`, and used by both sides.

## Hello and state sync

LuaCs drops a server-to-client message that arrives before the client's Lua has registered a
handler for it, and a client message sent before the server lists the sender as connected is lost.
The handshake is shaped around both:

```text
 client                                       server
 ------                                       ------
 load: register crewswap.state / denied
       handlers FIRST
 probe-install patches (sets probesOk)
 register crewswap.hello? handler
 +2 s: crewswap.hello(BUILD, probesOk)  -->   clientBuild[key] = BUILD
       (resent every 5 s, up to 12 times,     BUILD ~= server BUILD or not probesOk:
        until the first crewswap.state)         clientBad[key] = true, tell "out of date"
                                         <--  crewswap.state (this client's view)
 applyState: gotState = true, stop resending
```

- **Why resend.** A hello that lands before the client is in the server's connected list (a slow
  join, a mod download) is lost. The client resends every `HELLO_RETRY_MS = 5000` ms, at most
  `HELLO_TRIES = 12` times, until any `crewswap.state` answers.
- **Why the server asks.** A server Lua reload forgets every hello, while the clients' Lua keeps
  running and would never resend. So the server's `think` watchdog sends `crewswap.hello?` to any
  in-game client it has no hello from, every `HELLO_ASK_EVERY = 5` s, at most `HELLO_ASKS = 12`
  times; the client answers with a fresh hello. The hello tables also survive a server Lua reload
  (`server/main.lua` copies them), and any carried-over hello from a different build is marked bad.
- **No client-side LuaCs.** If a client has been in game for `NO_HELLO_AFTER = 90` s with no hello
  while the mod is active, it is told once:
  `[CrewSwap] This server uses CrewSwap. Turn on client-side LuaCs (LuaCs settings), then rejoin to switch between crew.`
  It is not kicked.
- **Stale or broken copies.** A hello whose `BUILD` differs from the server's, or whose probes
  failed, marks the client bad. It is told
  `[CrewSwap] Your copy of CrewSwap is out of date or didn't start properly — rejoin to update.`,
  and every request it sends is denied as `inactive`.
- **Rejoining starts over.** `client.disconnected` forgets the client's hello state; the new
  session sends a fresh hello.

### When state is sent

`SW.broadcastState()` sends every client that has said hello its own view of the crew: after every
switch and release, on every round start, on any crew death (`character.death`), after a driver
dies, around the round-end restore, after a vanilla bot takeover, after a switch that failed, and when an
admin changes `pool`, `protect` or an owner.
`SW.sendState(client)` answers a hello. Clients that never said hello get nothing (nothing would
read it).

The state is **per client** because Free depends on who is asking: under protect, another player's
home is not Free for you; in `own` mode, someone else's character is not Free for you. The server
computes `rules.isFree(view, toggles, requesterKey)` for each recipient. When the mod is inactive,
nothing is Free.

## Click handling

`CSC.onClick` is a prefix on `Barotrauma.CrewManager.CharacterClicked`, the method the crew-list
row's own click path calls (the per-row order button and right-click menus use other paths, so
they stay vanilla).

```text
 click on a row
   not multiplayer, no client, not a Character?  -> vanilla
   my own current character?                     -> vanilla
   no state for it (not crew / mod not running)? -> vanilla
   not Free for me:
     nobody drives it and no dialogue/camera
     transition?   -> send request (the server's denial says why), vanilla click still runs
     otherwise     -> vanilla (the row already shows who has it)
   Free:
     PreventExecution
     conversation open?        -> local "Finish the conversation..." message
     camera transition?        -> ignore silently
     within 3 s of last switch -> local "Too fast, wait N more second(s)..." message
     otherwise                 -> crewswap.request(id)
```

Design decisions in the click path:

- **Ask anyway for dimmed rows.** A crew member that is not Free for this player (another player's
  protected home, someone else's in `own` mode, unconscious) still sends a request so the server's
  denial tells the player *why*. The cost is a denial message per click while the mod is inactive,
  which is accepted as useful feedback.
- **No switch during a camera transition.** `CameraTransition` restores its previous character when
  it ends, which would undo the switch and desync input. The client checks
  `CoroutineManager.IsCoroutineRunning('CameraTransition')` and the end-of-round cinematic.
- **Dragging is safe.** Rows can be reordered by dragging. Vanilla's list treats a drag as a
  reorder and only reports a click for a press and release in the same position, so a drag never
  sends a request. Row rebuilds are also
  skipped while a row is being dragged.
- **The client cooldown is a courtesy.** It saves a round trip; the server enforces the same 3 s.

## Row styling

`CSC.onRowAdded` (postfix on `CrewManager.AddCharacterToCrewList`, whose return value is the new
row, or nil if the row already existed) records the row and its original colours. `CSC.styleRow`
then:

- **taken** (state has a controller name): row, hover and name greyed, plus a right-aligned label
  with the controller's name;
- **not Free for this player**: name dimmed;
- otherwise: the original colours.

Vanilla only builds objective icons for rows that were bots when created, so every 0.5 s
`checkFlips` rebuilds (remove and re-add at the same index) any row whose character's `IsPlayer`
changed since it was built. Rows built before the client's Lua started (for example after a client
`reloadlua`) are adopted from the state on the next restyle.

## Own control change

`CSC.think` watches `Game.Client.Character`. When it changes from one non-nil character to another,
the client sets its local cooldown, shows `[CrewSwap] Now playing <name>` and runs the housekeeping
that singleplayer's character selection does and multiplayer skips: close the command UI, clear the
inventory drag slot, `HintManager.OnChangeCharacter()`, refresh an open Talents tab, and reset or
auto-hide the crew list and chat box depending on whether the new body is operating something. Each
step is wrapped separately, so one failing call cannot block the others or re-fire every frame.

## Denials

Server-side denials use `crewswap.denied` for clients that said hello (shown on screen and in chat,
in red) and a private server chat line for clients that did not. The wording comes from
`core/rules.message`, shared by both sides, so the client never needs its own copy of the text.

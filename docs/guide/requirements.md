# Requirements

## Versions

| Component | Version CrewSwap 0.9.0 was built for |
|---|---|
| Barotrauma | **1.13.4.x** (any 1.13.4 revision) |
| Lua for Barotrauma (LuaCs) | tested against the build at commit **`85ded59`**; other builds get a warning ([Workshop item 2559634234](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234)) |

CrewSwap reaches deep into the campaign's save code, so it is strict about the game version.
When the server starts, CrewSwap reads the real game version and the LuaCs build.

- **Game version.** If it doesn't match, CrewSwap **turns itself off completely**. It installs
  nothing and tells players in chat, and the campaign carries on as plain vanilla. See
  [Version mismatch](troubleshooting.md#crewswap-is-off-for-this-game-version).
- **LuaCs build.** LuaCs updates itself through the Workshop, so a different build doesn't turn
  CrewSwap off. It logs a warning in the server console and keeps going. Its other checks still
  guard the campaign: if any patch fails to install, or one of the start-up or runtime checks fails (the live crew-list check on the first campaign round, the AI-body audit, the required game API checks), CrewSwap switches itself off
  (the optional in-game selftest only reports problems in the console and doesn't switch it off). See [Different LuaCs build](troubleshooting.md#different-luacs-build).

> When Barotrauma updates, CrewSwap stays off until a matching CrewSwap release comes out. This
> is on purpose: a mod that patches save code should never guess. If something misbehaves after a
> LuaCs update, put back the tested LuaCs build if you can and report it.

## Game modes

| Mode | CrewSwap |
|---|---|
| Multiplayer campaign: respawn modes MidRound, BetweenRounds, None | Active |
| Multiplayer campaign: Permadeath (Ironman off) | Active |
| Multiplayer campaign: Ironman | **Off** (vanilla Ironman rules apply) |
| Sandbox, mission and PvP rounds | Off |
| Singleplayer | Not applicable (the game already lets you switch) |

MidRound and Permadeath get the most testing. BetweenRounds and None are supported, but they get
lighter testing.

## Who needs what

| | LuaCs | CrewSwap |
|---|---|---|
| **Dedicated server** | Server-side LuaCs installed | In the server's `LocalMods` folder and enabled ([Server install](server-install.md)) |
| **Every player who wants to switch** | Client-side LuaCs installed ([Client install](client-install.md)) | Downloaded automatically from the server on joining (subscribing on the Workshop is optional) |
| **Players without client-side LuaCs** | none | Can still join and play normally; they just can't switch |

Some more detail:

- **The server must run unsandboxed Lua.** That is the LuaCs default. If an admin has turned
  off C# for the server in LuaCs's settings (run policy *Disabled*), server Lua is sandboxed.
  CrewSwap then logs `server Lua is sandboxed` and stays off.
- **Clients run sandboxed Lua.** CrewSwap's client half is pure sandboxed Lua and ships no C#.
  Players never need to accept a "run C# code" prompt for CrewSwap.
- **Players without client-side LuaCs are never kicked.** Once per connection, about 90
  seconds after they first enter a round while CrewSwap is active, they get one chat line
  explaining how to turn on client-side LuaCs. They get no notice in a non-campaign round,
  under Ironman or while CrewSwap is off.
- **Mod downloads must be allowed** on the server (the vanilla server setting, on by default),
  so joining players receive CrewSwap automatically.

## Platforms

- **Server:** any platform the Barotrauma dedicated server and LuaCs support (Windows or Linux).
  CrewSwap itself is plain Lua and has no platform-specific parts.
- **Clients:** Windows and Linux. The current LuaCs client installer (a Steam launch option)
  does not support macOS. See [Client install](client-install.md).

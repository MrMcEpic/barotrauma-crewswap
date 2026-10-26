# Server install

This page covers a **dedicated server**, which is what CrewSwap is built and tested on. See
[Hosting from the game client](#hosting-from-the-game-client) at the end for the in-game
"Host server" button.

Before you start, **back up your server's multiplayer saves** (the `Multiplayer` folder in the
server's Barotrauma data folder). CrewSwap is beta software.

## 1. Install LuaCs on the server

CrewSwap needs the server-side part of
[Lua for Barotrauma](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234)
(LuaCs). Follow the dedicated-server instructions on the LuaCs Workshop page or in the
[LuaCs GitHub repository](https://github.com/evilfactory/LuaCsForBarotrauma). Many hosting
panels also have a LuaCs option for Barotrauma servers.

Check two things:

- **Ideally, use the LuaCs build CrewSwap was tested against** (see [Requirements](requirements.md)).
  A different build only logs a warning at start-up, and CrewSwap keeps running as long as every
  patch installs. Step 4 below shows how to check this from the console.
- **Leave LuaCs's C# run policy at its default.** CrewSwap's server half needs unsandboxed
  server Lua. If C# is disabled for the server, CrewSwap stays off.

## 2. Put CrewSwap in `LocalMods`

Download the CrewSwap release and copy the `CrewSwap` folder into your server's `LocalMods`
folder, which sits next to the server executable. The result should look like this:

```text
<server folder>/
  LocalMods/
    CrewSwap/
      filelist.xml
      ModConfig.xml
      Content/crewswap_sync.xml
      Lua/crewswap/...
```

A few rules:

- The folder must be named `CrewSwap`, and `filelist.xml` must be directly inside it.
- Copy only the mod folder. Don't put the repository's `tests/` or `docs/` folders on the
  server. The server sends everything in the mod folder to every joining player.
- **Never put your own files in `LocalMods/CrewSwap`.** CrewSwap keeps its settings and
  runtime files in the server's save folder instead (see [Admin commands](admin.md#the-config-file)).

`Content/crewswap_sync.xml` is an empty item file. It is there on purpose: it makes CrewSwap a
*synced* content package, so the server requires it and sends it to players who don't have it.

## 3. Enable it

A dedicated server reads its enabled content packages from **`config_player.xml`** in the
server's working folder, not from `serversettings.xml`. **Stop the server first**, then add
CrewSwap under `<regularpackages>`:

```xml
<contentpackages>
  <corepackage path="Content/ContentPackages/Vanilla.xml" />
  <regularpackages>
    <!-- LuaCs, if your install lists it here (LuaCs adds itself when it is missing) -->
    <package path="LocalMods/CrewSwap/filelist.xml" />
    <!-- your other mods -->
  </regularpackages>
</contentpackages>
```

Keep the server setting that allows mod downloads switched on (it is on by default), so
players receive CrewSwap when they join.

If your hosting panel manages `config_player.xml` for you, enable the mod in the panel instead,
and check after the next restart that the line is still there.

## 4. Start the server and check the console

Start the server and look for these lines in the server console or log:

```text
[CrewSwap] server loaded build <build>
[CrewSwap] running on game 1.13.4.<n>, LuaCs <revision>
[CrewSwap] save folder: <path>
[CrewSwap] admin: config: pool=shared protect=on (defaults)
[CrewSwap] modules loaded: game, patch, selftest, spawn, identity, switch, presence, roundend, death, crewdown, safety, admin
[CrewSwap] patches installed: N/N
[CrewSwap] active: false
```

- `LuaCs <revision>` is the LuaCs commit as LuaCs reports it, which may be a full hash; with the
  tested build it starts with `85ded59`.
- `patches installed: N/N`, with both numbers the same, means every patch went in.
- If the LuaCs build isn't the tested one, a `[CrewSwap] WARNING: built for LuaCs ...` line
  follows the `running on game` line. CrewSwap keeps running; see the warning signs below.
  If LuaCs's build can't be read, the revision is blank and the warning says `running on unknown`.
- `active: false` is normal at this point, because no campaign is loaded yet.
- Note the **save folder** path. CrewSwap's config file and in-game self-test switch live in
  a `CrewSwap` folder inside it.

Then load or start a multiplayer campaign and start a round. You should see:

```text
[CrewSwap] round start, active: true
```

**Warning signs:**

| Console line | Meaning |
|---|---|
| `[CrewSwap] OFF: version mismatch (...)` and no `patches installed` line | Wrong game version (or the version couldn't be read): CrewSwap is off. See [Troubleshooting](troubleshooting.md#crewswap-is-off-for-this-game-version). |
| `[CrewSwap] OFF: version mismatch (server Lua is sandboxed)` | C# is disabled for the server in LuaCs. |
| `[CrewSwap] WARNING: built for LuaCs <expected>, running on <found>; ...` | A different LuaCs build than the one tested. CrewSwap keeps running; check that `patches installed` shows both numbers the same. See [Troubleshooting](troubleshooting.md#different-luacs-build). |
| `[CrewSwap] FAIL: <reason>` | CrewSwap switched itself off. See [Troubleshooting](troubleshooting.md#crewswap-switched-itself-off-fail). |
| No `[CrewSwap]` lines at all | The mod isn't enabled, or LuaCs isn't running on the server. |

## 5. Tell your players

Every player who wants to switch needs **client-side LuaCs**. Point them to
[Client install](client-install.md). Players without it can still join and play, but they
can't switch.

## Updating CrewSwap

1. Stop the server.
2. Replace `LocalMods/CrewSwap` with the new version. Your settings live in the save folder,
   so you lose nothing.
3. Start the server and check the console as in step 4.

The server packs the mod for download **once, at start-up**, so a new version only reaches
players after a restart. Players get it automatically when they next join. Anyone who is still
running an old copy is told in chat to rejoin.

## Removing CrewSwap

End the session on a **saved** round end (a level transition or save-and-quit). Before every
save, CrewSwap puts every player back in their own character, so the save is in vanilla shape.
Then stop the server and remove the `config_player.xml` line. The campaign keeps loading in
vanilla, which ignores CrewSwap's extra save data. From then on vanilla rules apply again:
dead bots are deleted, and bots' money isn't kept. See the [FAQ](faq.md).

## Hosting from the game client

CrewSwap is built and tested for **dedicated servers**. The server half needs LuaCs running
server-side with unsandboxed Lua. Whether that works on a server started with the in-game
"Host server" button depends on how LuaCs is installed on the host's machine, and it hasn't
been tested. If you try it, enable CrewSwap in the host's mod list as you would any other mod,
and check the host's console for the lines in step 4. If you see
`[CrewSwap] round start, active: true`, it is running.

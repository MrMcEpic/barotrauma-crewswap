# Client install

To switch between crew members, you need **client-side Lua for Barotrauma (LuaCs)**. CrewSwap
itself downloads automatically when you join a server that runs it.

## 1. Install client-side LuaCs

1. Subscribe to
   [Lua for Barotrauma on the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2559634234).
2. Follow the install instructions on that Workshop page. **The current method is a Steam
   launch option.** You add the launch option shown on the Workshop page to Barotrauma's
   launch options in Steam (Library, right-click Barotrauma, **Properties**, **Launch
   Options**). It installs client-side LuaCs when the game starts. Copy the option exactly from
   the Workshop page. It can change between LuaCs versions, so it isn't reproduced here.
3. **Keep the Lua for Barotrauma content package _disabled_ in the in-game mod list.** You need
   the subscription for the installer, but you shouldn't tick the package as an enabled mod.

> **macOS:** the launch-option installer doesn't support macOS. See the Workshop page for the
> current state of macOS support.

### The older method

Before the launch option existed, you installed client-side LuaCs by hosting a server with the
LuaCs-patched executable and running `install_cl_lua` in its console. If the Workshop page
still describes this for your platform, it works too. Prefer whatever the Workshop page
currently recommends.

### Do I need to enable C#?

**Not for CrewSwap.** CrewSwap's client half is pure sandboxed Lua and ships no C#. If the game asks you to enable C# for
the session, the request comes from a different mod on that server.

## 2. Get CrewSwap

You don't need to do anything. When you join a server that runs CrewSwap, the game offers to
download it like any other server mod. Accept the download.

You can also subscribe to CrewSwap on the Steam Workshop if you like. If your copy differs from
the server's, the game uses the server's version for that session.

## 3. Check that it's working

Join the server, then open the in-game console with **F3**. You should see:

```text
[CrewSwap] client loaded build <build>
[CrewSwap] client: hello sent (1), probes ok
```

- A second line like `hello sent (2)` a few seconds later is fine. The client retries until the
  server answers.
- `probes FAILED`, or a `[CrewSwap] client: patch ... failed`, `crewList access failed` or
  `missing <class>` line, means CrewSwap couldn't set
  up its crew-list hooks on your client. Usually your LuaCs build doesn't match. See
  [Troubleshooting](troubleshooting.md).
- No `[CrewSwap]` lines at all means client-side LuaCs isn't running.

If it isn't working, you'll get one of these chat messages: the first once per connection, about 90 seconds after you first enter a round while CrewSwap is active, the
second as soon as you join:

| Message | What to do |
|---|---|
| `[CrewSwap] This server uses CrewSwap. Turn on client-side LuaCs (LuaCs settings), then rejoin to switch between crew.` | Client-side LuaCs isn't installed or isn't active. Go back to step 1, then rejoin. |
| `[CrewSwap] Your copy of CrewSwap is out of date or didn't start properly — rejoin to update.` | Your copy differs from the server's, or failed to start. Rejoin. If it keeps happening, update LuaCs and unsubscribe/resubscribe CrewSwap. |

You can keep playing
normally either way. You just can't switch until it's fixed.

Now read [Playing](playing.md).

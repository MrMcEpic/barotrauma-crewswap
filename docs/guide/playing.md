# Playing

This page is for players. It assumes client-side LuaCs is installed
([Client install](client-install.md)) and the server runs CrewSwap in a multiplayer campaign.

## A few words first

- Your **own character** (your *home*) is the one you created or were given for this campaign.
  It is still yours, and the save stores it as yours.
- Every other crew member is a **bot**. They are the crew in the crew list, including any
  you hire.
- A crew member is **Free** for you when it is alive, conscious, nobody is playing it, and the
  server's settings let you take it (see [pool and protect](#who-you-can-take)).

## Switching

Open the **crew list**, the vanilla list of crew portraits on the left side of the screen, and
**click a Free crew member's row**. The server checks the request. Within a moment you are
playing that character, and you see:

```text
[CrewSwap] Now playing <name>
```

The character you left becomes a bot again right away. It keeps its inventory and its orders,
pauses for a moment, and carries on with what it was doing.

CrewSwap tidies up after each switch the way singleplayer does: it closes the command wheel,
drops any item you were dragging, refreshes an open Talents tab, and updates the hints.

### What the rows mean

| Row looks like | Meaning | Clicking it |
|---|---|---|
| Normal colours | Free for you | Switches you into that character |
| **Greyed out**, with a player's name on the right | That player is playing it | Nothing from CrewSwap; the game's usual click behaviour |
| Normal row, **dimmed name** | A crew member you can't take right now | You get a chat line saying why (for example, it belongs to another player) |
| Your own current character | You | The game's usual click behaviour |

**Dragging rows to reorder them still works.** A drag doesn't count as a click, so it never
switches you. **The order (command) button** on each row works as usual too, so you can give
orders to bots without taking them over.

### Cooldown

You can switch once every **3 seconds**. Click too soon and you get:

```text
[CrewSwap] Too fast, wait 2 more second(s) before switching again.
```

### When you can't switch

| Message | Why |
|---|---|
| `[CrewSwap] Finish the conversation before switching characters.` | You're in a conversation dialogue. |
| `[CrewSwap] You can only switch characters while a round is running.` | The round is ending, or hasn't started. |
| `[CrewSwap] Hold on, you are still joining the round.` | You haven't finished joining or syncing yet. |
| `[CrewSwap] You can switch once your own character has joined the crew (after you first spawn).` | You're new to this campaign and haven't spawned yet. |
| `[CrewSwap] You cannot switch characters while spectating.` | You chose to spectate in the lobby. |
| `[CrewSwap] Traitors cannot switch characters.` | You're the traitor this round. |
| `[CrewSwap] Someone else is already playing that character.` | Another player took it first, possibly in the same instant. |
| `[CrewSwap] That character is dead, unconscious or otherwise unavailable.` | It isn't in a state you can take. |
| `[CrewSwap] That character belongs to another player.` | Pool or protect settings stop you taking it. |
| `[CrewSwap] That is not a crew member you can switch to.` | It isn't part of your crew (for example, an outpost NPC). |
| `[CrewSwap] CrewSwap is off right now.` | CrewSwap is inactive (type `!crewswap status` to see why), or your copy is out of date or failed to start. In that case you'll also have seen "Your copy of CrewSwap is out of date..."; update it and rejoin. |

A click during a camera transition (for example, the end-of-level cinematic) is quietly
ignored, because the transition would undo the switch.

**A downed character doesn't stop you.** You can switch out of a body that is unconscious or
dying, just like in singleplayer.

## Who you can take

The server admin sets two options (see [Admin commands](admin.md)). `!crewswap status` shows
them to anyone.

**Home protection on** (the default): other players can't take your own character, and you
can't take theirs. Bots are fair game.

**Home protection off:** while you're playing someone else, your own character is Free for
the others, and theirs are Free for you. A player who leaves mid-round leaves their body as a
bot, and with protection off others can take it for the rest of that round. From the next
round, characters of players who are offline don't spawn at all (vanilla behaviour).

**Pool `shared`** (the default): any Free crew member can be taken, apart from protected homes.

**Pool `own`:** each bot belongs to a player.

- A bot you **hire** while the pool is `own` is yours.
- A bot nobody owns yet (the starting crew, or anything hired before `own` mode was turned on)
  belongs to **the first player who plays it while the pool is `own`**.
- You can always take your own character.
- In `own` mode, another player's own character is off limits. The only exception: with
  protection off, an admin has made you its owner with `!crewswap owner`.
- Admins can reassign a bot with `!crewswap owner`.

Changing these settings never kicks anyone out of the character they're playing. It only
affects new switches.

## When your character dies

When the character you're playing dies, the crew list updates and you can **click any Free
crew member** to keep playing straight away.

- The death counts against **the character that died**, not you. Any death penalty or
  permanent death applies to that character. Being the one who drove it doesn't make you a
  spectator.
- The **body stays where it died**, so you can go back for the gear.
- **Nobody Free?** (MidRound respawn) Then the usual vanilla respawn brings back your own
  character. If your own character is still alive but someone else is playing it (protection
  off), you wait until somebody Free turns up.

### Everyone is down

Normally the round ends soon after every player's character is dead or down. With CrewSwap, if
there are still Free crew members, the round is held open for **2 minutes** so someone can
switch in:

```text
[CrewSwap] Everyone is down. Pick a crew member from the crew list within 2 minutes or the round ends.
[CrewSwap] 30 seconds left to pick a crew member.
[CrewSwap] Nobody switched in — the round will end.
```

Switching into anyone cancels the countdown. If nobody does, the round ends as vanilla would.

### Bots who die come back

Outside Permadeath, a crew member who dies is **not** gone for good, unlike vanilla bots. They
come back as a bot at the start of the next round:

- after a **saved** round end, with vanilla's usual death penalty to their skills
- after an **unsaved** round end (a failed round, or a vote to end), with no penalty, because
  the round is rolled back anyway

Characters you **fire** are still removed, as in vanilla.

### Permadeath

With Permadeath on (and Ironman off):

- Every crew death is permanent: bots, your own character, or another player's character,
  whoever was playing it.
- If **your own character** dies for good, the next crew member you take who isn't another
  player's character becomes **your new character**. It is stored as yours from then on.
- The game's "take over a bot" prompt after death still works. CrewSwap handles it as a
  normal switch. Hiring a new character from that prompt is allowed only once your own
  character is permanently dead (or when you have no character in this campaign yet). Otherwise you get
  `[CrewSwap] You can only take on a new crew member once your own character is permanently dead.`

## Joining, leaving and rejoining

- **New to the campaign?** You spawn as your own character as usual. Once you've spawned, you
  can switch.
- **Leaving mid-round:** the character you were playing goes back to being a bot straight away
  and keeps working. Vanilla wouldn't do that: it would leave the body frozen and kill it after
  a while. This also means disconnecting is no escape from a fight.
- **Rejoining:**
  - with protection **off**: you go back into the character you last played, if it's still Free
  - otherwise: you go back into your own character, if it's Free
  - This happens as soon as you have finished loading into the round (CrewSwap waits up to
    3 minutes, and never moves anyone while the round is ending). If it doesn't, click a Free
    row to switch.

## Round start

- **Protection on:** everyone starts the round in their own character.
- **Protection off:** everyone starts in the character they last played, if it is Free.
  Otherwise they start in their own character.

## Round end, money and XP

- **Mission pay and round-end rewards** go to the character you're playing when the round
  ends. Crew nobody was playing get what vanilla bots get.
  - Exception: on **save-and-quit**, pay goes to the players' own characters.
- Just before the game saves, CrewSwap puts every player back in their own character, and the
  bots stay bots. This is what keeps the save clean.
- **Money belongs to the character.** Each crew member has their own wallet and salary
  setting, and switching never moves money. A bot's wallet is kept through saves. If the round
  ends without saving, everyone's wallets go back to the last save, bots' included.
- **XP and skills belong to the character too.** Your own character only gets XP from what
  it does. While you play someone else, your own character is idle crew and gets mission XP and
  round-end talent effects like a bot does.

For the full list of changes from vanilla, see [Differences from vanilla](vanilla-differences.md).

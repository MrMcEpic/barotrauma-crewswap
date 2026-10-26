# Differences from vanilla

Everything on this page applies **only while CrewSwap is active**: a multiplayer campaign
round, Ironman off, and a matching game version. (A different LuaCs build only logs a warning;
see [Troubleshooting](troubleshooting.md#different-luacs-build).) When CrewSwap is inactive (no
campaign, Ironman, or a version mismatch), the game plays as vanilla. The exceptions:

- the 20-backup count (see [Saving and backups](#saving-and-backups)), which applies whenever
  CrewSwap is loaded on a matching game version, even when it is inactive;
- the `!crewswap` chat commands, which are handled whenever CrewSwap is loaded, except on a
  version mismatch (see [Chat](#chat));
- during an integrity lockdown, the save safeguards described in
  [Troubleshooting](troubleshooting.md#integrity-alarm-and-lockdown): the server is held in the
  lobby and saves still keep CrewSwap's data.

With nobody switching, a CrewSwap campaign plays almost exactly like vanilla. Most of the
differences below only show up once players start moving between characters, or when crew die.

## Switching and control

- **Players can take control of Free crew members** by clicking their row in the crew list
  ([Playing](playing.md)). Vanilla only allows this through the cheat-flagged `control`
  command, which also damages the save.
- **Switching gives no free rename** and **never moves money** between characters.
- **Player bodies are AI-capable characters.** Vanilla spawns players' characters as plain
  characters with no AI, so a body a player left would just stand there. CrewSwap spawns every
  campaign crew body with an AI that is paused while a player drives it. Two side effects:
  - Attacks made by players aren't written to the server's attack log the way vanilla logs
    player attacks.
  - Nearby bots react to an attack on a player's body the way they react to an attack on a bot.
- **Your idle character is crew.** While you play someone else, your own character is a bot
  for the round. It gets mission XP and round-end talent effects as bots do. An admin with the
  vanilla permission to manage bot talents can edit its talents like a bot's.

## Round start, joining and leaving

- **With home protection off**, players start each round in the character they last played,
  if it's Free, instead of always in their own character.
- **Disconnecting hands the body back to the AI** right away. Vanilla leaves a disconnected
  player's body frozen, then kills it after a timeout. With CrewSwap the character keeps working.
- **Rejoining** puts you back in the character you last played (protection off) or your own
  character, if Free. Vanilla returns you only to a body you still control.
- **New players can switch only after their first spawn** in the campaign.

## Death

- **Death effects go to the character that died, not to whoever was driving it.** In vanilla,
  permanent death and the skill penalty are keyed on the player driving the body. With CrewSwap
  they apply to the character itself, whether that's a bot, your own character, or another
  player's. (The "Retain Experience" talent effect is switched off instead; see [Money and XP](#money-and-xp).)
- **A death never makes you a spectator.** You can switch to another Free crew member straight
  away.
- **A borrowed body stays in the world** when vanilla respawns you (outside Permadeath). It
  isn't despawned along with you.
- **Dead crew members come back (outside Permadeath).** Vanilla deletes every dead bot at round
  end, for good. CrewSwap keeps them and brings them back as bots at the start of the next
  round, with health reset and orders cleared:
  - after a saved round end they also take vanilla's usual death penalty to skills. After a
    level transition their items are in the duffel bag left where they died. After a
    save-and-quit they keep them.
  - after an unsaved round end there is no skill penalty.
  - Fired crew are still removed as in vanilla.
- **The round doesn't end while someone could switch in.** Vanilla ends the round shortly after
  every player is dead or down. CrewSwap holds it open for up to **2 minutes** while Free crew
  remain, and announces this in chat at the start, with 30 seconds left, and at the end. If
  nobody switches in, the round ends as vanilla would.

## Permadeath

- **Every crew death is permanent**, including the death of a player's own character that the
  AI was running while its owner played someone else. Vanilla only applies permanent death
  through the player driving the body.
- **A permanently dead player's character's wallet goes to the campaign bank** at the moment of
  death.
- **A player whose own character is permanently dead** makes the next crew member they take
  (one that isn't another player's character) their new character.
- **The vanilla "take over a bot" request** is handled as a CrewSwap switch for crew already in
  the world. Hiring or bench take-overs from that prompt reach vanilla only once the player's own
  character is permanently dead (or when the player has no character in this campaign yet). Otherwise CrewSwap refuses them, because vanilla would discard
  the player's living character.

## Money and XP

- **Every character has their own wallet**, bots included. Vanilla only keeps wallets for
  players' characters, so a bot's money is lost. CrewSwap saves bots' wallets and salary
  settings with the campaign.
- **Bots' money follows the save.** A round that ends without saving gives bots back their last
  saved wallets, as it does for players' characters.
- **Mission pay goes to the character each player is playing** when the round ends.
  - On **save-and-quit** it goes to the players' own characters instead, because they're
    restored before the pay is handed out on that path.
- **The "Retain Experience" talent effect is off** (`RetainExperienceForNewCharacter`). Vanilla
  saves the XP of whatever body a player drives when it dies, and gives it to that player's next
  new character. With switching, that would hand a bot's XP to the player's own character. While
  CrewSwap is active nothing is saved, and any XP saved for this from before reads as zero. A
  character always keeps its own XP.

## Saving and backups

- **Before every save, every player goes back into their own character**, and borrowed
  characters stay bots. The save is therefore always in the shape vanilla expects.
- **Integrity check before writing.** If a save would lose or duplicate a crew member, CrewSwap
  **refuses to write it**, reloads the last good save, and holds the server in the lobby until
  an admin runs `!crewswap check`. See [Troubleshooting](troubleshooting.md#integrity-alarm-and-lockdown).
- **20 rolling save backups instead of 3.** Unlike everything else on this page, this applies to
  every campaign on the server whenever CrewSwap is loaded on a matching game version, including
  Ironman and non-campaign sessions where CrewSwap is otherwise inactive.
- **Extra data in the save.** CrewSwap adds `crewswap_*` attributes to each character and a
  `<CrewSwap>` element to the campaign. Vanilla ignores them. It also writes a
  `<campaign>_CrewSwap.xml` recovery file next to the save.

## Chat

- `!crewswap` commands (the word `!crewswap` on its own or followed by a space) never appear in public chat ([Admin commands](admin.md)),
  except when CrewSwap is off because of a version mismatch: then its commands aren't loaded.
- CrewSwap shows short `[CrewSwap]` chat lines: switch confirmations (shown by your own client)
  and denials, the 2-minute countdown, settings changes, integrity alarms and lobby notices, and
  notices when it is off or your client can't switch.

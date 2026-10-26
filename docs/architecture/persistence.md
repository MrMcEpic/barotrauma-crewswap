# Persistence

CrewSwap's rule for storage is simple: **vanilla's save is the source of truth, and CrewSwap's
data rides inside it.** Mod state saves, reverts and backs up exactly when the campaign does, and a
save is always loadable without the mod.

## What vanilla stores (and CrewSwap leaves alone)

| Data | Where vanilla keeps it |
|---|---|
| A player's home character | That client's `CharacterCampaignData` (CCD), keyed by account id (falling back to address). The CCDs are written to `<campaign>_CharacterData.xml` next to the `.save`. Each CCD carries the character's info, inventory, health, orders and wallet. |
| Every other crew member | The `CrewManager` roster (active crew plus the reserve bench), saved inside the campaign `.save`. |
| Rolling backups | Vanilla's own numbered backups of the save, managed by `SaveUtil`. CrewSwap raises `SaveUtil.MaxBackupCount` to 20. |

CrewSwap never moves a character between these stores during play. The only moves it makes are
ones vanilla itself would make, and each is reported to the integrity check:

- Permadeath **adoption**: a player whose home is permanently dead takes a crew member who is
  nobody's home. `adoptHome` (in `server/switch.lua`) creates their new CCD from that info with
  `MultiPlayerCampaign.SetClientCharacterData` and removes the info from the roster.
- Vanilla's own `TryTakeOverBot` (only reached in Permadeath, when the player has no home yet or
  their home is permanently dead), which does the same thing.

## Stable ids

`CharacterInfo.ID` is reassigned every time a save is loaded, so it is only a per-session handle.
Anything CrewSwap persists about a character needs an identity that survives save, load, restarts
and renames. CrewSwap gives every crew `CharacterInfo` a random 32-hex-digit GUID, called a
**sid** in the code (`CS.newGuid()` uses `System.Guid.NewGuid():ToString('N')`, falling back to
`math.random` if `System.Guid` is unavailable).

The in-memory registry (`core/registry.lua`, held in `CS.reg`) has two maps:

- `bySession`: `CharacterInfo.ID` → sid, rebuilt after every load.
- `chars`: sid → record, where a record is:

| Field | XML attribute | Meaning |
|---|---|---|
| `last` | `crewswap_last` | Account key of the last player who drove this character. |
| `lastAt` | `crewswap_lastat` | `os.time()` of that switch, in seconds. A player's "last played" character is the record with their key in `last` and the greatest `lastAt`. |
| `owner` | `crewswap_owner` | Account key of the owner in `own` pool mode (the hirer, the first player to take an unclaimed character, or whoever an admin assigned). |
| `home` | `crewswap_home` | Account key of the player whose home this became through a takeover or Permadeath adoption. Informational only (kept for diagnostics); the live home is always taken from the CCD. |
| `wbal` | `crewswap_wbal` | Bot wallet balance. |
| `wrd` | `crewswap_wrd` | Bot salary (reward distribution). |

An **account key** is `AccountId.StringRepresentation`, or `addr:<address>` for a client without an
account id, which is how vanilla keys CCDs too. Vanilla saves already contain these account ids in
the CCD file; CrewSwap adds no new kind of personal data. Stable ids never leave the server; the
network protocol uses entity ids only.

`CS.sidOfInfo(info)` is the one way to get a sid. It returns the existing binding, or adopts the
sid just read from XML for that info (`CS.pending`), or mints a new GUID (counted in `CS.minted`).
`CS.sidOfInfo` itself mints unconditionally; its callers decide. The save path (`bindMissing` in
the `MultiPlayerCampaign.Save` prefix) and `G.view` mint only while `CS.active`, so a campaign
played while the mod is inactive stays vanilla. The exceptions are the integrity stores used by the
load-time snapshot and by a manual `!crewswap check`: both mint an id for any unbound crew info
even during a lockdown. The load-time snapshot does so only in a non-Ironman campaign on a matching
version. The manual check (and the `safety-runcheck` selftest) can mint in-memory ids in any
multiplayer campaign, Ironman included; those ids are only ever saved where `CS.campaignOk` holds,
so an Ironman save stays vanilla.

## Where CrewSwap data lives in the save

### `crewswap_*` attributes on `<Character>`

A postfix on `Barotrauma.CharacterInfo.Save(XElement)` adds `crewswap_id` plus the record's
attributes to the `<Character>` element vanilla just built. Because vanilla uses the same method for
both CCD infos and roster bots, every crew member carries its sid and record wherever vanilla puts
it: in `<campaign>_CharacterData.xml` for homes and inside the `.save` for bots.

```xml
<Character name="Kim Lee" ... crewswap_id="3f2a...9c" crewswap_last="..." crewswap_lastat="1700000000"
           crewswap_wbal="500" crewswap_wrd="25" />
```

A postfix on the `CharacterInfo(ContentXElement infoElement, Identifier npcIdentifier)` constructor
reads them back into `CS.pending[info.ID]`. It is not gated on `CS.active`, because it runs during
campaign load, before the mod knows whether the campaign is one it handles.

### `<CrewSwap>` in `<MultiPlayerCampaign>`

The postfix on `MultiPlayerCampaign.Save(XElement, Boolean)` adds one element:

```xml
<MultiPlayerCampaign ...>
  ...
  <CrewSwap campaignguid="<32 hex>" modversion="0.9.0" />
</MultiPlayerCampaign>
```

`campaignguid` identifies the campaign for the mirror file (below). `modversion` records which
release last wrote the save. The `MultiPlayerCampaign.Load` postfix reads it back.

### When ids are written

- The `MultiPlayerCampaign.Save` **prefix** recomputes `CS.active`. If the campaign object is one it
  never saw load (`CampaignID` differs), it is a new campaign: a fresh registry and a new campaign
  GUID. It then binds every live crew info (`bindMissing`), minting ids for new hires and homes only
  while active, logs `identity: save: minted N new ids for M crew`, and prunes stale session
  bindings. After a restart or reload, existing crew must show `minted 0`.
- During a **lockdown** (see [Safety](safety.md)) every id and record the mod already holds is still
  written, because `CS.campaignOk` ignores lockdowns. Only minting waits for `CS.active`. Otherwise
  the next vanilla save during a lockdown would drop the mod's data for good.

## The mirror file

After every real save (not the save-on-load), the `MultiPlayerCampaign.Save` postfix writes a
**recovery mirror** next to the save:

```text
Multiplayer/
  MyCampaign.save                  vanilla
  MyCampaign_CharacterData.xml     vanilla (CCDs)
  MyCampaign_CrewSwap.xml          CrewSwap mirror
```

```xml
<CrewSwapMirror campaignguid="<32 hex>">
  <c id="<sid>" on="<original name>" h="<identifier hash>" job="<job id>"
     crewswap_last="..." crewswap_wbal="500" ... />
  ...
</CrewSwapMirror>
```

It is written to `<path>.tmp` first and then moved into place, so a crash never leaves half a file.

The mirror is **never the source of truth**. It exists for two situations where the save
attributes are not enough:

### Recovery after a Lua reload or a mod-off gap

- **Lua reload mid-campaign.** A reload empties the registry while the infos stay loaded in memory
  (their XML was read long ago). At load, `server/identity.lua` sees a campaign object it has not
  seen and calls `bindMissing(infos, false)`: it re-matches the live infos to mirror rows with
  `core/mirror.match` and logs `identity: re-matched N of M from the mirror`. Nothing is minted.
- **A save written while the mod was off.** A game-version mismatch or a sandboxed server means vanilla
  wrote the save without any `crewswap_*` attributes. The mirror still holds each character's sid
  *and* record, so they are restored when the mod comes back.

`mirror.match` pairs rows to live infos first by `CharacterInfo.GetIdentifierUsingOriginalName()`
(a hash vanilla derives from the original name, the head preset, the hair, beard, moustache and
face-attachment choices, and the job; it changes if any of those change) and then, for whatever is left, by the original name alone. A pair is made only where
exactly one row and one live info share the key. Ambiguous cases stay unmatched and get new ids
later. The job is stored in the row but is not a match key.

A save with no `<CrewSwap>` element adopts the mirror's campaign GUID only if the mirror re-matches
at least half of the unbound crew. That guards against a stale mirror left behind by a deleted
campaign that had the same name.

## Per-character wallets

Vanilla persists a wallet only through a CCD. A bot's wallet lives on its body and is lost at save.
Because money is per character in CrewSwap, every roster bot's wallet is stored on its record:

1. **Stage.** In the `CampaignMode.End` prefix, `CS.snapshotWallets()` copies each bot's
   `Wallet.Balance` and `Wallet.RewardDistribution` into `CS.walletStage`, keyed by sid. If any body
   cannot be read, the save is blocked rather than written with a stale wallet.
2. **Commit.** In the `SaveUtil.SaveGame` prefix of a save that is really being written (not the
   save-on-load, not a blocked save), `CS.commitWallets()` re-snapshots the live wallets and moves
   the stage into the records. A failure there also blocks the write. The re-snapshot is needed
   because on save-and-quit the save is written **before** `CampaignMode.End` runs, so there is no
   stage yet: the commit's own re-snapshot is what writes the wallets, and the stage taken
   afterwards at `End` is dropped by the `GameServer.EndGame` postfix.
3. **Discard.** On an unsaved end, the `GameServer.EndGame` postfix drops the stage.
4. **Restore.** In the `CrewManager.InitRound` postfix and on `character.created`, each roster bot
   with a stored `wbal` gets `Balance` set, `ForceUpdate()` called, and `SetRewardDistribution(wrd)`.

**Design decision: stage, then commit.** Committing at `CampaignMode.End` would let an unsaved end
(which continues from memory) keep bot earnings while player characters' CCD wallets revert to the
last save. Staging keeps money-per-character consistent: everything reverts together.

Home wallets stay vanilla's (in the CCD). When a home dies for good in Permadeath, vanilla's
`ApplyPermadeath` drops the CCD wallet; CrewSwap pays that balance into the campaign bank first
(`homePermadeath` in `server/death.lua`).

## The config file

Server-wide settings, not per campaign:

```text
<SaveFolder>/CrewSwap/config.txt
```

`<SaveFolder>` is the game's save folder (`Game.SaveFolder`), the folder that contains
`Multiplayer/`. The format is two `key=value` lines:

```text
pool=shared
protect=on
```

Missing file, unreadable file, unknown keys and bad values all fall back to the defaults
(`pool=shared`, `protect=on`). The file is rewritten (via `.tmp` and a move) whenever an admin
changes a setting. If writing fails, the setting still applies until the server restarts and the
admin is told.

The same folder holds two optional marker files: `selftest` (run the in-game selftest at load; see
[Testing](testing.md)) and `force-integrity-fail` (development only: makes every integrity check
fail; see [Safety](safety.md)). Nothing is ever written inside the mod's own folder, because that
folder ships to every client.

## Per-campaign vs per-session state

| State | Lifetime |
|---|---|
| sids, records (owner, last played, wallets) | Per campaign, in the save. |
| Campaign GUID | Per campaign, in the save. |
| `pool`, `protect` | Server-wide, `config.txt`. |
| Who is driving whom | Per round, in memory only. The restore puts everyone home before every save. |
| Kept dead, staged wallets, integrity snapshot | In memory, reset by round start or load. |
| Hello state (client builds, join times) | In memory, reset when that client disconnects. Client builds, bad flags, join times and the no-LuaCs-notice flag are carried over a server Lua reload; the hello-ask counter is not. |
| Switch cooldowns | In memory, time-based: they expire after 3 s (or are reset by a server Lua reload). |

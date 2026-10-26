# Publishing CrewSwap to the Steam Workshop

Barotrauma mods are published from the game client itself. These are maintainer notes for doing
that with a release build.

Files in this folder:

- `description.bbcode`: the Workshop description, in Steam BBCode. Paste it into the description box.
- `preview.png`: the Workshop preview image (640x640 PNG, well under the game's 1 MB limit).

## Before you start

- You need a Steam account that owns Barotrauma, with the game at the version CrewSwap targets
  (1.13.4.x).
- Build the release package from a clean checkout of the release tag:

  ```sh
  tools/package.sh 0.9.0 beta      # -> dist/CrewSwap-0.9.0.zip, BUILD 0.9.0-beta
  ```

  **Publish the contents of this zip, not the raw `mod/CrewSwap` folder.** The server and every
  client compare their `BUILD` string at hello time; a Workshop copy whose `BUILD` differs from the
  copy on servers shows up as an outdated client and cannot switch.

## Publishing (first time)

1. Unzip the package into the game client's `LocalMods` folder, so that
   `<Barotrauma install folder>/LocalMods/CrewSwap/filelist.xml` exists. (In Steam: right-click
   Barotrauma > Manage > Browse local files.)
2. Start Barotrauma. From the main menu open **Mods**, then the **Publish** tab.
3. Select **CrewSwap** from the list of local mods.
4. Under **Preview image**, click **Browse** and pick `workshop/preview.png`.
5. Set the title to `CrewSwap` and paste `workshop/description.bbcode` into the description box.
6. The **Version** box is pre-filled from `filelist.xml` (and the game bumps it automatically if
   it matches the version already on the Workshop). Make sure it says the release version, e.g.
   `0.9.0`, matching `MODVERSION` in the package.
7. Fill in the change note (copy the release's changelog entry), pick tags, and set **Visibility**
   (Private or Friends-only first is a good idea for a smoke test), then click **Publish**.
8. When it finishes, the game may open the Steam overlay to ask you to accept the Steam Workshop
   legal agreement; the item stays hidden until you do.

## After publishing

1. On the item's Workshop page (in a browser or the Steam overlay), open **Add/Remove Required
   Items** and add **Lua for Barotrauma** (Workshop id `2559634234`) as a required item. The game's
   publish screen has no field for this.
2. Check the description renders properly and set visibility to Public when you're happy.
3. After the first publish the game rewrites the local `LocalMods/CrewSwap/filelist.xml`, adding
   `steamworkshopid="<id>"` (and saving the version you entered). Copy that attribute back into
   `mod/CrewSwap/filelist.xml` in the repository and commit it, so later builds update the same item
   instead of creating a new one. Replace the "Steam Workshop (link coming soon)" placeholders in
   `README.md` and `landing/index.html` (the disabled Steam Workshop button) with the real link, and
   add it to the book's `docs/guide/client-install.md` (step 2) and `docs/guide/faq.md`.

## Updating an existing item

Same steps with the new package: unzip it into `LocalMods` over the old copy (keep
`steamworkshopid` in `filelist.xml`, which a package built after step 3 above already carries),
open **Mods > Publish**, select CrewSwap (the button now reads **Update**), set the version and
change note and publish. Re-select the preview image only if you want to change it.

## What's uncertain

These notes follow the game's publish screen as it exists in the Barotrauma source at the time of
writing (Mods menu > Publish tab: preview image browse, title, description, version, change note,
tags, visibility). Menu labels can change between game versions. Points worth checking on the
first publish:

- Whether the in-game description box keeps every BBCode tag intact (it should; Steam does the
  rendering). If not, edit the description on the Workshop page afterwards.
- The exact wording and position of **Add/Remove Required Items** on the Workshop page.
- That `ModProject.Save` keeps `filelist.xml` otherwise unchanged; diff it before committing.

Barotrauma does not use a fixed file name for the Workshop thumbnail: you pick any PNG or JPEG
under 1 MB in the publish screen, so the mod folder deliberately ships no preview image.

# Contributing

Thanks for wanting to help. Bug reports, play-test results and pull requests are all welcome at
[github.com/MrMcEpic/barotrauma-crewswap](https://github.com/MrMcEpic/barotrauma-crewswap).

The most valuable contribution right now is **two-player testing**: the server side is well
covered, but live switching between several players has not been fully play-tested yet. If you
try it, an issue saying what worked and what didn't (with the `[CrewSwap]` lines from the server
console and the client's F3 console) helps a great deal.

Before changing code, read the [Architecture overview](architecture/overview.md) and
[Patches and LuaCs gotchas](architecture/patches.md). Most of the subtle bugs this mod could have
are about save paths and silent LuaCs behaviour, and those pages explain both.

## Repository layout

```text
mod/CrewSwap/          the mod itself; this folder is what ships (to the server and every client)
  filelist.xml, ModConfig.xml, Content/crewswap_sync.xml
  Lua/crewswap/{shared,core,server,client}/
tests/                 off-game unit tests (run.lua, fakes.lua, test_*.lua)
tools/package.sh       builds a release zip
book.toml              mdBook configuration (src = "docs")
docs/                  this documentation (mdBook sources: SUMMARY.md, guide/, architecture/)
theme/                 extra CSS for the book
landing/               the landing page served at the site root (the book is served under /book/)
workshop/              Steam Workshop description and assets
README.md, CHANGELOG.md, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, LICENSE
                       root project files (CHANGELOG.md feeds the GitHub release notes)
.github/ISSUE_TEMPLATE/, .github/PULL_REQUEST_TEMPLATE.md   issue and PR templates
.github/workflows/     ci.yml (tests, package, XML), docs.yml (book + Pages), release.yml (tag-driven release)
```

`dist/` (release zips), `book/` (the built book, written by `mdbook build`) and `_site/` (the
assembled Pages site) are build outputs; they are gitignored and never committed.

## Development setup

You need:

- **Lua 5.2** for the unit tests (`sudo apt install lua5.2` on Debian/Ubuntu; most package managers
  have a `lua5.2` or `lua@5.2` package). LuaCs runs MoonSharp, which implements Lua 5.2, so stick to
  5.2 features.
- **bash** and **zip** for packaging.
- **mdBook** if you edit the documentation (`mdbook serve` from the repository root previews it locally).
- For in-game testing: a Barotrauma dedicated server and client of the targeted version, with
  LuaCsForBarotrauma installed server-side and client-side LuaCs enabled on the client. See
  [Requirements](guide/requirements.md).

## Running the tests

From the repository root:

```sh
lua5.2 tests/run.lua
```

All tests must pass before a pull request is merged. The runner exits non-zero on any failure, so
it works as a CI step too. See [Testing](architecture/testing.md) for how the tests are structured
and how to write new ones.

## Packaging

```sh
tools/package.sh 0.9.0          # BUILD = 0.9.0
tools/package.sh 0.9.0 beta     # BUILD = 0.9.0-beta
```

`tools/package.sh <version> [build-suffix]` copies `mod/CrewSwap` to a staging folder (your working
tree is never modified), stamps `MODVERSION` and `BUILD` into `Lua/crewswap/shared/build.lua` and
`modversion` into `filelist.xml`, and writes `dist/CrewSwap-<version>.zip` with a single top-level
`CrewSwap/` folder.

Two things to keep in mind:

- **Bump the version for every code change you deploy.** The game's package hash ignores Lua files,
  so clients with a cached copy of the same `modversion` would keep running old scripts.
- **The server and every client must run copies of the same package.** The client's hello carries
  `BUILD` and the server refuses switch requests from any other build. The Workshop upload should be
  the contents of the zip.

### Testing a build on a server

1. Stop the server.
2. Unzip `dist/CrewSwap-<version>.zip` into the server's `LocalMods/` folder (replacing any older
   `CrewSwap/`).
3. Make sure the package is enabled for the server (see [Server installation](guide/server-install.md)).
4. Start the server and check the console for `[CrewSwap] server loaded build <BUILD>`,
   `patches installed: 36/36` (or the current total) and no `FAIL` lines.
5. Optionally enable the [in-game selftest](architecture/testing.md#in-game-selftest).

Use a throwaway campaign for testing anything save-related, and keep a copy of the server's
`Multiplayer/` saves.

## Releasing

Releases are cut by pushing a tag. Three GitHub Actions workflows are involved:

- `ci.yml` runs on pushes to `main` that touch code (docs-only and prose-only changes are
  skipped), on every pull request and on manual dispatch: the Lua 5.2 unit tests, a
  `tools/package.sh 0.0.0 ci-1` package smoke test and an XML well-formedness check of the mod.
- `docs.yml` runs when `docs/`, `book.toml`, `theme/` or `landing/` change: it builds the book with
  mdBook (any mdBook warning fails the build), puts the landing page at the site root and the book
  under `/book/`, and deploys the result to GitHub Pages on pushes to `main`.
- `release.yml` runs when a `v*` tag is pushed: for example, pushing `v0.9.0-beta` runs the tests,
  runs `tools/package.sh 0.9.0 beta` and attaches `CrewSwap-0.9.0.zip` to a GitHub release. A tag
  with a `-suffix` becomes the `BUILD` suffix and is marked as a pre-release.

The GitHub release notes come from the matching `## [x.y.z]` section of the root `CHANGELOG.md`
(for `v0.9.0-beta`, the `## [0.9.0]` section). If that section is missing, the release only gets a
link to the book's changelog, so add the section before you push the tag.

Tag the 0.9.0 beta as `v0.9.0-beta`. A plain `v0.9.0` tag would publish it as a full release with
a `BUILD` of `0.9.0`, which doesn't match the in-tree `0.9.0-beta`.

One-time setup for a fork or fresh repo: in the GitHub repo, set **Settings > Pages > Source** to
"GitHub Actions", or the Pages deploy job fails.

## Coding conventions

**Structure**

- Put decisions in `core/` as pure functions over plain tables, with unit tests. Keep `server/` and
  `client/` modules as thin adapters that read the game, call core, and apply the result.
- Namespace every module `crewswap.<area>.<name>`: the `require` cache is shared by every mod.
- Never write runtime files inside `mod/CrewSwap/`: that folder ships to every client. Server data
  goes under `Game.SaveFolder .. '/CrewSwap/'` or next to the campaign save.
- Pure, sandboxed Lua only: no `<Assembly>`, no `RunUnrestricted="true"`. Client code must work both
  sandboxed and unsandboxed.

**Patches**

- Install every server patch with `P.patch(...)`, never a bare `Hook.Patch`, so a failure to resolve
  switches the mod off cleanly.
- Gate every callback on mod state, normally `CS.active` (identity: `CS.campaignOk`); keep the
  existing non-`CS.active` gates on the restore, safety and load paths as they are (see
  [Patches](architecture/patches.md)). Patches are never removed.
- Wrap every callback body in `pcall` (the existing `safe` / `guard` helpers) and end with a bare
  `return`. Return a value only when you mean to replace a non-void method's result.
- Read arguments as `p['exactCSharpName']`; read the table's own members with dots
  (`p.ReturnValue`, `p.PreventExecution`).
- On a save-critical path, an error must set `CS.blockSave`, not be swallowed.
- Compare enums with enum tables, never with strings. Convert CLR collections with `G.list`. See the
  full list of [gotchas](architecture/patches.md#luacs-gotchas).
- Add a selftest check (`ST.add`) for any new game API or patch target you rely on.

**Text and logging**

- Player-facing text starts with `[CrewSwap]` and uses Canadian English (colour, behaviour,
  licence as a noun, -ize endings). Code identifiers keep the game's US spelling.
- Module log lines use `[CrewSwap] <module>: <message>`, so they are easy to grep. Status and
  start-up lines are the exceptions: for example `FAIL:`, `OFF:`, `WARNING:`, `INTEGRITY ...`,
  `SELFTEST ...`, the grace countdown, the boot lines (`server loaded build`, `running on game`,
  `save folder:`, `modules loaded:`, `patches installed:`, `active:`) and `round start, active: ...`. Every
  console line starts with `[CrewSwap]`.
- Keep the denial wording in `core/rules.lua` so the server and client stay in sync.

**Style**

- Two-space indentation, `local` everything, short comments that explain *why* (vanilla behaviour,
  a LuaCs quirk) rather than *what*.
- Match the surrounding code; small, focused changes are easier to review than broad rewrites.

## Updating for a new game or LuaCs version

When the game updates, CrewSwap switches itself off (`OFF: version mismatch`). When LuaCs updates,
it only logs `[CrewSwap] WARNING: built for LuaCs <expected>, running on <found>; continuing (patch
audit and self-tests still guard)` and keeps running, relying on the patch-install audit and the
start-up and runtime checks to catch a breaking change. Either way, supporting the new version properly is careful
work, because a patch that still *resolves* can still be *wrong*:

1. Read the game and LuaCs changelogs.
2. For every patch in [Patches](architecture/patches.md), check the target method in the new source:
   signature, parameter names, and the behaviour the patch depends on (for example the order of
   steps inside `GameSession.EndRound`, or what `SavePlayers` removes).
3. Update `EXPECT_GAME` and/or `EXPECT_LUACS` in `mod/CrewSwap/Lua/crewswap/shared/build.lua`.
4. Run the unit tests, deploy to a test server, run the selftest, and play through the save-related
   rows of the [manual test checklist](architecture/testing.md#manual-test-checklist) on a
   throwaway campaign.

Never bump the expected versions without re-checking: the game version gate is what keeps a broken
build from touching anyone's campaign, and the LuaCs warning is what tells admins they are running
an untested combination.

## Pull requests

- Describe what the change does and why. For behaviour changes, say what you tested in game (server
  only, or with clients; which respawn mode; which round-end path).
- Include unit tests for new or changed logic. Keep `lua5.2 tests/run.lua` green.
- Update the relevant pages in `docs/` and add an entry to both changelogs: the root `CHANGELOG.md`
  (which feeds the GitHub release notes) and the book's [Changelog](changelog.md).
- Do not include personal details (server addresses, account ids, player names) in code, tests,
  logs or screenshots you attach. Use placeholders such as `Alice`, `Bob` or
  `your-server.example.com`.
- AI-assisted contributions are fine, just as the mod itself was built with AI assistance; please
  review and test what you submit as carefully as anything you wrote by hand.

## Licence

CrewSwap is licensed under the **GNU Affero General Public License v3.0 only** (AGPL-3.0-only); see
the `LICENSE` file. By submitting a contribution you agree that it is licensed under the same terms.

In practice, for a Barotrauma mod: you may use, study, modify and share it. If you distribute a
modified version (for example on the Workshop), or run a modified version on a server that other
people play on, the AGPL asks you to make your modified source available to those people under the
same licence. Since the mod's Lua is sent to every client anyway, the simplest way is to publish your
fork openly and link to it.

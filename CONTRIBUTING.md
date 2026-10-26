# Contributing to CrewSwap

Thanks for your interest! The full contributor guide (repository layout, development setup,
running the tests, packaging, and the LuaCs gotchas worth knowing before you touch a patch) lives
in the documentation:

**[docs/contributing.md](docs/contributing.md)**, also published at
<https://mrmcepic.github.io/barotrauma-crewswap/book/contributing.html>.

## The short version

- Be kind. We follow the [Contributor Covenant](CODE_OF_CONDUCT.md).
- The most useful contribution right now is **two-player testing**. If you try CrewSwap with
  friends, [open an issue](https://github.com/MrMcEpic/barotrauma-crewswap/issues/new/choose)
  saying what worked and what didn't, with the `[CrewSwap]` lines from the server console and the
  client's F3 console.
- Small, focused pull requests are easier to review than large ones. For anything substantial,
  open an issue first so we can agree on the approach.
- Run the tests before you push: `lua5.2 tests/run.lua` must end with `N passed, 0 failed`.
- Update the relevant pages under `docs/` and add an entry to [CHANGELOG.md](CHANGELOG.md) (it feeds
  the GitHub release notes) and to `docs/changelog.md` when behaviour changes.
- Prose uses Canadian English (colour, behaviour, licence as a noun). Code identifiers keep the
  game's own spelling.
- Security problems go through a private report, not a public issue. See [SECURITY.md](SECURITY.md).

## Licence

CrewSwap is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0-only).
By submitting a contribution you agree that it is licensed under the same terms.

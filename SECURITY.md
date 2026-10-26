# Security Policy

## Supported Versions

Only the latest release is supported with fixes. If you're running an older version, please
upgrade before reporting.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| Older   | :x:                |

## Reporting a Vulnerability

**Please do not open public issues for security vulnerabilities.**

Report privately through GitHub's private vulnerability reporting:

1. Go to <https://github.com/MrMcEpic/barotrauma-crewswap/security/advisories/new>
2. Fill out the form with as much detail as you can
3. Submit. Only the repository maintainers will see the report.

If that page doesn't load (for example, private reporting hasn't been switched on yet), contact the
maintainer through their GitHub profile at <https://github.com/MrMcEpic> and ask for a private
channel. Please don't post details in public issues, pull requests or comments until a fix is out.

## What to Include

- A clear description of the problem and its impact (what can a malicious player or client do?)
- The CrewSwap build line from the server console (`[CrewSwap] server loaded build ...`), the Barotrauma
  version and the Lua for Barotrauma version
- Steps to reproduce, or a proof of concept
- A suggested fix, if you have one

## Response Expectations

- **Acknowledgement** within 72 hours
- **Initial assessment** within one week
- **Fix or mitigation plan** within two weeks for serious issues

This is a hobby project shared with the community, not a funded product. Response times are best
effort, but reports are taken seriously.

## Scope

In scope:

- The mod under `mod/CrewSwap/`, in particular anything a client can send to the server to take
  control of a character it shouldn't, corrupt or delete campaign saves, move money, or crash the
  server
- The release packaging (`tools/package.sh`) and the GitHub Actions workflows

Out of scope:

- Vulnerabilities in Barotrauma itself or in Lua for Barotrauma (report those upstream)
- Problems that require server admin rights, since admins already control the server
- Modified forks or builds not produced from this repository

## Credit

Reporters who want public credit are named in the release notes once the fix ships. Reporters who
prefer to stay anonymous are respected.

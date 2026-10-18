# Releasing Arkab

How a version gets from `main` to somebody's hall, what each downloaded
file is, and - because none of it has happened yet - what the first release
has to prove.

## Cutting a release

One commit on `main`:

1. `mix.exs`: the new `version:`.
2. `CHANGELOG.md`: rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
   (and start a new, empty `## [Unreleased]` above it).

Push. `.github/workflows/release.yml` builds every target, starts each one
and looks at its answer, and then - only if every target passed - tags
`vX.Y.Z` at that commit and publishes the release with the changelog
section as its notes.

It publishes when **both** are true: `mix.exs` names a version without a
GitHub release, and the changelog has a section for exactly that version.
A version without notes publishes nothing (the run says so in a notice and
stays green); so does a push that changes neither. That second condition is
the one difference from OpenPairings, where the version alone decides.

`v0.1.0` exists only as a tag (the one Alnasl pins as a library) and never
had a release; the first published release is 0.2.0.

Do not tag by hand. If you do, the tag must be `v` + the version in
`mix.exs`, or the workflow refuses.

There is no way to un-release. A wrong release is followed by a right one
with a higher number; installed copies move forward only.

## What a release holds

All names are without a version, so that
`https://github.com/teapot-chess/Arkab/releases/latest/download/<name>`
is a link that stays right. The version is inside each file.

| File | What it is | Who asks for it by name |
|---|---|---|
| `Arkab-Setup.exe` | The Windows installer (Velopack, per user, one click) | the download page |
| `arkab-windows-x86_64-portable.zip` | The same release as a folder; installs nothing | the download page |
| `arkab-linux-x86_64.tar.gz` | The Linux release, PCs | `install.sh`, `update.sh`, the download page |
| `arkab-linux-aarch64.tar.gz` | The Linux release, 64-bit Raspberry Pi and other arm64 | the same |
| `arkab-macos-aarch64.zip` | `Arkab.app` for Apple Silicon (M1 and later), zipped with `ditto` | the download page; a Mac copy's update notice (its size) |
| `install.sh` | The one-line installer | `curl ... \| sudo sh` |
| `update.sh`, `uninstall.sh` | Copies of what the archive carries, for reading | nobody; a person |
| `SHA256SUMS` | Checksums of everything above and below | `install.sh`, `update.sh` |
| `releases.win.json` | Velopack's feed: which Windows versions exist | every installed Windows copy |
| `ArkabApp-X.Y.Z-full.nupkg` | The Windows program as Velopack fetches it | the same, via the feed |
| `ArkabApp-X.Y.Z-delta.nupkg` | The difference from the release before (from the second release on) | the same |

Never rename `releases.win.json` or a `.nupkg`, and never change the pack
id `ArkabApp`: installed copies look for those names, and one that cannot
find them stays on its version for ever without saying why.

## Where things are built from

| | |
|---|---|
| `mix.exs`, `releases/0` and `release_extras/1` | one release, `arkab`; per system, the files beside `bin/` |
| `config/runtime.exs`, `lib/arkab/data_home.ex` | where an installed copy keeps its data, and the refusal to keep it anywhere an installer owns |
| `rel/env.sh.eex`, `rel/env.bat.eex` | Erlang distribution off by default |
| `rel/windows/launcher.c` | `Arkab.exe`: starts the release, opens the browser, is the stop button, applies an update |
| `rel/windows/build_launcher.ps1` | compiles it with `zig cc` (run by `mix release`) |
| `rel/windows/build_installer.ps1` | `vpk pack`, with the checks that keep data out of harm's way |
| `rel/windows/build_icon.py` | draws `Arkab.ico` from the mark; run by hand when the mark changes |
| `rel/linux/install.sh`, `update.sh`, `uninstall.sh` | the Linux installation |
| `rel/linux/arkab.service`, `arkab-update.path`, `arkab-update.service` | the service, and the root-owned updater a page can ask but not command |
| `rel/macos/build_app.sh`, `launcher.sh`, `Info.plist` | `Arkab.app` around the release: its launcher (window, Stop), the checks that it links nothing but the system |
| `rel/macos/sign_and_notarize.sh`, `entitlements.plist` | Developer ID signing and notarisation, once the Apple account exists (below) |
| `lib/arkab/updates.ex`, `updates/checker.ex` | the check, the notice, the hand-over; the status page shows it |
| `tools/release_notes.sh` | the changelog section of one version |

## Signing the Mac app

Not done yet: there is no Apple Developer account. The macOS jobs build
`Arkab.app` **ad-hoc signed** (Apple Silicon requires a signature on every
binary; Gatekeeper still asks the arbiter once, see `docs/macos.md`).

The signing step is already in `release.yml`, and skips itself while the
secret `APPLE_CERTIFICATE_P12_BASE64` is empty. Once the account exists,
add these repository secrets and nothing else changes:

| Secret | What |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | the *Developer ID Application* certificate with its private key, exported as `.p12`, then base64 |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12`'s password |
| `APPLE_TEAM_ID` | the ten-character team id |
| `APPLE_ID` | the Apple ID that notarises |
| `APPLE_APP_PASSWORD` | an app-specific password for that Apple ID |

`rel/macos/sign_and_notarize.sh` then signs every binary with the hardened
runtime and the BEAM's entitlements (JIT, `dlopen` of the SQLite library),
notarises, staples, and asks Gatekeeper before the zip is made. The same
five secrets, under the same names, sign Alnasl.app and OpenPairings.app. The first signed
build needs a Mac test of its own.

## Building one by hand

Windows, with Elixir, `zig` and `vpk` (`dotnet tool install -g vpk
--version 1.2.0`) on the PATH. Set `ARKAB_DATA` to a scratch folder first:
any `MIX_ENV=prod` task reads the runtime configuration, and without it
would create the real data folder of the PC you are sitting at.

```
set MIX_ENV=prod
set ARKAB_DATA=%CD%\tmp\release-data
mix deps.get --only prod
mix compile
mix release arkab --overwrite
.\rel\windows\build_installer.ps1 -PayloadDir _build\prod\rel\arkab -OutputDir installer_out
```

`set ARKAB_UART=1` before `deps.get` to have the serial library in it -
from a checkout whose path has no space. Without
it the release is whole and cannot open a real board.

Linux: the same four `mix` lines, then
`tar -czf arkab-linux-$(uname -m).tar.gz -C _build/prod/rel arkab`. Built
on your machine it runs on your machine's glibc or newer; the workflow
builds on Ubuntu 22.04 for a reason.

**Building an installer is harmless. Running one is not a test to do on the
PC you work on.** Use a Windows Sandbox or a spare machine. A sister project
lost real data to an installer run "just to see".

## What the first release has to prove

Nothing below has been done. Each line is a claim the code makes and nobody
has watched come true. Work down the list with the first release and strike
what holds.

**The workflow**

- [x] `ci.yml` and `release.yml` parse and run at all (0.1.0, 2026-10-12).
- [x] `erlef/setup-beam` has OTP 29.0.5 for `ubuntu-22.04` and
      `ubuntu-22.04-arm`.
- [x] `circuits_uart` builds on `windows-latest` with the image's own
      `gcc` and `mingw32-make`.
- [ ] `shellcheck --severity=warning` passes on `rel/linux/*.sh` (it was
      not available where they were written; they pass `sh -n`).
- [ ] The smoke tests pass on all three targets, including "the serial
      library loads" and "nothing listens but port 4050".
- [ ] A push with a version and no changelog section publishes nothing; a
      push with both publishes once; the next push publishes nothing.
- [ ] The release notes are the changelog section.

**Windows**

- [ ] `Arkab-Setup.exe` installs to `%LOCALAPPDATA%\ArkabApp`, makes the
      Start menu and desktop entries, and starts the launcher.
- [ ] The launcher's window appears, the browser opens when the site
      answers, a second double-click opens a tab instead of a second server.
- [ ] Closing the window asks, and stops the program; no `erl.exe` is left.
- [ ] The data is in `%LOCALAPPDATA%\ArkabData`, and **is still there
      after uninstalling**. This is the one that matters. Join a server first, so there is a key to lose.
- [ ] Installing again finds the data.
- [ ] A PC that never had Erlang or the Visual C++ runtime starts it (the
      three DLLs beside `erl.exe` are there for this).
- [ ] A real electronic board on a COM port is read by the installed copy.
- [ ] From the second release on: the notice appears, "Download and
      install" stops the program, the launcher downloads and applies, the
      new version starts. Then the unhappy ways: no network at that moment
      (the old version must come back), and the boards are not read while the update runs, and the page says so.
- [ ] SmartScreen says what the README says it says.
- [ ] Symantec and Defender leave `Setup.exe`, the portable zip and the
      installed `Arkab.exe` alone. (Measured for OpenPairings' Velopack
      installer and portable release on this network; assumed to carry
      over.)
- [ ] "Start with Windows" starts it, minimised, without a browser.

**Linux**

- [ ] `install.sh` on Debian 12, Ubuntu 22.04 and Raspberry Pi OS Bookworm
      64-bit: user, group, directories, units, service up.
- [ ] The hardened unit starts at all (`ProtectSystem=strict`,
      `RELEASE_TMP=/run/arkab`, `RestrictAddressFamilies`), and can open
      `/dev/ttyUSB0` as `arkab` in `dialout`.
- [ ] `update.sh` to a newer release: download, checksum, switch, restart,
      answer. And to a release that does not start: the old one is back.
- [ ] "Download and install" on the status page: the request file appears,
      `arkab-update.path` fires, the page comes back on the new version.
- [ ] `uninstall.sh` removes the program and **leaves `/var/lib/arkab`**.
- [ ] Offline install from an unpacked archive.

**macOS** (the full list, for a person with a Mac, is in `docs/macos.md`)

- [ ] `macos-15` builds it, `build_app.sh` finds no
      Homebrew library, and the app starts from a read-only bundle on the
      runner.
- [ ] Downloaded on a real Mac, it opens after "Open Anyway", shows its
      window, opens the browser; Stop asks and stops; no `beam` is left.
- [ ] The data is in `~/Library/Application Support/ArkabData`, and is
      still there after the app is binned.
- [ ] A real electronic board on a USB adapter shows up as `/dev/cu.*` and is read.

## Version numbers

The first published release is `0.2.0`. From then on:
patch for fixes, minor for anything an arbiter would notice, and 1.0.0 the
day a whole tournament has been played on real boards through an installed
copy.

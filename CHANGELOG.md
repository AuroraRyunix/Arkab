# Changelog

What changed in Arkab, newest first. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and each entry is
tagged so that a version can be skimmed:

| tag | meaning |
|---|---|
| [Feature] | something new you can do |
| [Fix] | something that was broken |
| [Change] | existing behaviour works differently |
| [Removed] | something is gone |
| [Security] | a hole closed, or judged not to be one |
| [Verified] | checked against the real thing, no code change |

## [Unreleased]

- [Change] **Installed copies keep their data in one place that no installer owns:** `%LOCALAPPDATA%\ArkabData`, `/var/lib/arkab`, `~/Library/Application Support/ArkabData`, and `ARKAB_DATA` still wins. The bridge refuses to start with data inside the install folder, the program folder or an app bundle, because an uninstall that takes the queue and the servers' keys with it is a lesson best learnt on somebody else's project. `PORT` is read as well as `ARKAB_PORT`; the installers set the first.
- [Feature] **A Details panel, the same as the server's.** The Windows launcher and the Mac app can show what the bridge says about itself (version, uptime, CPU, memory, the queue file, servers connected, events waiting, boards, buses open, recording) and the end of its log; `arkab.sh details` does the same in a terminal. The answer is `GET /_launcher/stats`, which is for this machine only, with this start's secret, and 404 for anything else, a proxy header included. No port is opened to answer it.
- [Feature] **The bridge knows when it is out of date.** An installed copy asks GitHub every half hour, with the last answer's ETag so that "nothing changed" costs nothing, whether a newer version exists, and says so on the status page with the size of the download. It installs nothing without a yes: the Windows installer's launcher or the Linux updater does it, the portable copies get a link. One checkbox switches the question off, and "Later" puts the notice away for a day. The page also says that the boards are not read for about a minute while an update installs, since a bridge, unlike a server, has no idea whether a game is under way and cannot refuse. On Windows there is a switch to start it with the machine.
- [Feature] **Releases.** The Windows installer (which updates itself) and a portable zip, Linux archives for PCs and for the Raspberry Pi with a one-line installer and a systemd service, and an Apple Silicon Mac app built for macOS 11 and newer, with checksums beside them. All of it is built on every push to `main`, each file on its own kind of machine, and every one is started and made to answer on port 4050 before anything is published. It is Alnasl's pipeline with the names changed, which is how it was built and also why it should work.
- [Feature] **A mark.** Seven squares, one of them in the accent colour, beside the name on both pages and as the tab icon (`/favicon.svg`), all read from one file, `priv/logo/mark.svg`. Replace the file and the rest follows; it was a name in a heading until now.
- [Change] The docs now call them what they are to the person using them: live boards.
- [Feature] **A help for the bridge's page, and the page in Dutch.** `/help` says what Arkab is, how to join a server, what the dots mean, what the queue count is, what the ports list shows and what to do when a server is red - six short sections, in English and Dutch. The page itself speaks both now too: EN and NL at the foot, remembered in a cookie, and until you choose, whatever the browser asks for. No gettext for this: about thirty strings do not need a build step to have opinions about them.
## [0.1.0] - 2026-10-16

- [Feature] **The board drivers, moved out of Alnasl and renamed `Arkab.*`.** The electronic-board serial protocol, the single board, the loop and its bus, the emulator, the UART and fake transports, the capture format and its recorder, and the replay player. The code now exists once, here, and Alnasl uses it as a library. Started as a library, Arkab starts nothing at all; it was only moved, not promoted.
- [Feature] **A bridge: the hall's boards, sent to any number of Alnasl servers.** Started with `config :arkab, role: :bridge`. Every event goes into a SQLite queue on disk first and is numbered, then travels over one outgoing WebSocket per server, TLS when the link is https. Each server has its own cursor, so one that is down holds up nobody else, and an event leaves the queue only once every server has acknowledged it. A bridge that restarts carries on from where the queue says it was, not from where it would like to have been.
- [Feature] **Commands come back down the same socket.** Rescan a port, add one, forget a port or a board, send a board again in full, and recording on or off. They are applied one at a time in arrival order. Only a server joined as owner can make the bridge forget anything; the others may ask, and will be told no.
- [Feature] **Joining is one step.** Paste or scan the server's join link on the bridge's page. The bridge fetches its own long key, so nobody ever reads a secret aloud across a playing hall. Remove works from either side and ends the link for both.
- [Feature] **A status page on port 4050.** Each server with a green or red dot and a Remove button, the number of events waiting, the ports, the boards, and one field to join with. It runs the camera's own QR reader where the browser has one, and asks for a paste where it does not.
- [Feature] **Builds without the serial library.** With `ARKAB_UART=0` (or Alnasl's `ALNASL_UART=0`), the serial NIF is not compiled. Arkab looks for it at run time and answers "no ports" when it is not there, so a server that only receives bridges never has to own a C compiler.
- [Verified] **The link protocol is written down, version 1, in `docs/protocol.md`**, together with the reasons for mint_web_socket. The module both ends compile is `Arkab.Protocol`; the page describes it and the module decides.

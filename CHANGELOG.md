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

## [0.3.4] - 2026-10-19

- [Fix] **A join refused because the bridge is in another hall says so.** Alnasl turns away a link from a second hall while the bridge still sits in the first, and says exactly that. Arkab heard a 403 and announced that the address "answered, but not like a server", which was true of every server it had ever met. It now says the bridge has to be removed from the other hall first.
- [Feature] **Arkab for Intel Macs, from macOS 10.13.** macOS 10 exists only on Intel Macs, and they had been struck off on the 14th because their build is slow. It is back, and it is built only when there is a release to put it in (or when somebody starts the workflow by hand), so the other pushes are as quick as they were. Arkab's own update notice picks the zip for the Mac it is on, and no longer says an Intel Mac has no build; an Intel Arkab running under Rosetta on an Apple Silicon Mac is treated as the Apple Silicon Mac it is. Every program in the bundle, serial library included, is checked against the oldest macOS promised, as before. Whether a 2017 Mac and an electronic board agree is for a person with both to say; see docs/macos.md.

## [0.3.3] - 2026-10-19

- [Change] **"Did not answer" now says what it heard instead.** A board on a loop that missed a question was logged as silent whether it was silent or not. The line now adds either "nothing came back" or how many bytes did, how soon, whether they failed their checksum, and the bytes themselves. A mute board and a port that mangles a talkative one no longer look the same in the log.

## [0.3.2] - 2026-10-19

- [Fix] **A bridged board's "Signal" is no longer a percentage of the wrong thing.** The bridge sends one "answered" a second and every miss, so a loop board polled sixty times a second showed 95% with nine misses, and one that missed a handful per second showed 17%. The answer that is sent now says how many answers it stands for (`n` on the wire; a server that ignores it sees what it saw before), and the answers owed go out ahead of the next miss.
- [Fix] **A board that answers a little late is no longer missing for ever.** On a loop, an answer that arrived after its 200 ms was thrown away as a stray, and the board was asked again, answered late again, and so counted missed on every poll. A late answer is now recognised by its address and kind, logged with how late it was, and that board is given that long plus 100 ms from then on (a second at most). The first miss of every run is logged too, with the board and the question.
- [Fix] **Reading a port again waits for its old loop to let go.** On a Mac two programs can open the same serial device, and a rescan could start the single-board driver while the old bus was still asking: two askers, and the old boards answer neither.

## [0.3.1] - 2026-10-19

- [Fix] **Stopping Arkab stops Arkab, promptly.** With the status page open in a browser (which is to say, always), the server politely waited fifteen seconds for the page to hang up before it would go, then closed its database, and the Mac launcher's patience ran out at twenty. "Stopping Arkab..." sat there long enough to look like a hang. Open pages now get three seconds, as Polis and Nunki already gave them, and the Mac launcher writes into the log how long a stop took, or that it had to insist.

## [0.3.0] - 2026-10-19

- [Security] **The status page no longer lets the hall's network press its buttons.** It listens on the hall's network by default and had no login, so anyone there could join the bridge to a server of their choosing, make it leave the real ones, or restart it mid-round. Everything that changes something (joining, removing a server, updating, the Windows start-up entry) now works only from the bridge itself, decided by the connection's peer address when the page opens and again for every event sent, never by a header. From another computer the page is a read-only view, marked as such in English and Dutch; to manage a bridge with no screen, forward the port over SSH. The help says so.
- [Fix] **The page on another computer is alive again.** Phoenix compared the page's origin with the single host name "localhost", so a phone or laptop opening the bridge's address got the first render and a socket that was refused: no refresh, buttons that did nothing. The socket now accepts the host names the bridge actually answers to (localhost, 127.0.0.1, its own name and addresses, and `ARKAB_HOSTS`), and a request for any other host gets a 403, which also closes the DNS-rebinding route to the page.
- [Fix] **A server that never comes back, or a full disk, no longer takes the bridge down.** The queue now has a ceiling (the oldest clock readings go first; positions and results only past a much higher one), a write the disk refuses throws that batch away and says so on the page instead of killing the process (and, three restarts later, the whole VM, which then came back to the same full disk), and a database file that will not open is moved aside with the time in its name while the bridge starts with a fresh one. Servers have to be joined again after that last one; the log line says so.
- [Security] **The Linux updater refuses a version that is not newer.** A request from the status page is a file the unprivileged service user can write, and the updater is root; it installed whatever version number the file named, including an older release under a newer database. Older or equal versions are now refused before anything is downloaded.

- [Change] **New address.** The repository moved to github.com/teapot-chess; old links still redirect, out of politeness rather than obligation.
## [0.2.2] - 2026-10-18

- [Fix] **Quitting Arkab on the Mac stops Arkab, and whatever it started.** The launcher script signalled the server and nobody else, so a helper program could outlive the thing that asked for it; it now reads the whole tree under the server before saying goodbye, and after twenty seconds (or a clean exit, which is no proof of anything) SIGKILLs all of it. The app's own last resort, ten seconds later, did the same trick with only the script, and left the server to launchd; it now takes the tree as well.

## [0.2.1] - 2026-10-18

- [Fix] Quitting no longer leaves an error in the log about the launcher's details. It was tidying up a setting while the application controller was busy shutting everything down, and complaining when nobody answered.
- [Change] **The page says where the join link comes from, in Alnasl's own words:** Halls, your hall, Bridges, "Add a bridge", then paste it here or scan its code. The help says the same, and that Alnasl's Setup wizard leads there too. "On the server: Halls" had been accurate in the way a street name without a town is.

## [0.2.0] - 2026-10-17

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

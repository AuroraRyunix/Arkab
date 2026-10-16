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

## [0.1.0] - 2026-10-16

- [Feature] **The board drivers, moved out of Alnasl and renamed `Arkab.*`.** The DGT serial protocol, the single board, the loop and its bus, the emulator, the UART and fake transports, the capture format and its recorder, and the replay player. The code now exists once, here, and Alnasl uses it as a library. Started as a library, Arkab starts nothing at all; it was only moved, not promoted.
- [Feature] **A bridge: the hall's boards, sent to any number of Alnasl servers.** Started with `config :arkab, role: :bridge`. Every event goes into a SQLite queue on disk first and is numbered, then travels over one outgoing WebSocket per server, TLS when the link is https. Each server has its own cursor, so one that is down holds up nobody else, and an event leaves the queue only once every server has acknowledged it. A bridge that restarts carries on from where the queue says it was, not from where it would like to have been.
- [Feature] **Commands come back down the same socket.** Rescan a port, add one, forget a port or a board, send a board again in full, and recording on or off. They are applied one at a time in arrival order. Only a server joined as owner can make the bridge forget anything; the others may ask, and will be told no.
- [Feature] **Joining is one step.** Paste or scan the server's join link on the bridge's page. The bridge fetches its own long key, so nobody ever reads a secret aloud across a playing hall. Remove works from either side and ends the link for both.
- [Feature] **A status page on port 4050.** Each server with a green or red dot and a Remove button, the number of events waiting, the ports, the boards, and one field to join with. It runs the camera's own QR reader where the browser has one, and asks for a paste where it does not.
- [Feature] **Builds without the serial library.** With `ARKAB_UART=0` (or Alnasl's `ALNASL_UART=0`), the serial NIF is not compiled. Arkab looks for it at run time and answers "no ports" when it is not there, so a server that only receives bridges never has to own a C compiler.
- [Verified] **The link protocol is written down, version 1, in `docs/protocol.md`**, together with the reasons for mint_web_socket. The module both ends compile is `Arkab.Protocol`; the page describes it and the module decides.

# Arkab: brief for the download page

For whoever maintains the public website. Everything the page may say is
here.

## What it is

Arkab is the bridge: a small program on a PC or a Raspberry Pi next to the
electronic chess boards in a tournament hall. It reads the boards and sends
every move, with the clock times, to one or more Alnasl servers over an
outgoing connection. Nothing in the hall's network has to be opened.

It is for the person who sets the hall up, not for players or spectators.
It goes with Alnasl (the server that follows the games) and OpenPairings
(the arbiter's program); say so, so that nobody downloads the wrong one.

## The download links

These addresses are the same for every release. Link to them exactly; do
not host copies, and do not print a version number you did not fetch.

| What | Address |
|---|---|
| Windows installer | `https://github.com/teapot-chess/Arkab/releases/latest/download/Arkab-Setup.exe` |
| Windows, portable zip | `https://github.com/teapot-chess/Arkab/releases/latest/download/arkab-windows-x86_64-portable.zip` |
| Linux, PC (x86_64) | `https://github.com/teapot-chess/Arkab/releases/latest/download/arkab-linux-x86_64.tar.gz` |
| Linux, Raspberry Pi and other arm64 | `https://github.com/teapot-chess/Arkab/releases/latest/download/arkab-linux-aarch64.tar.gz` |
| Linux installer script | `https://github.com/teapot-chess/Arkab/releases/latest/download/install.sh` |
| Mac, Apple Silicon only | `https://github.com/teapot-chess/Arkab/releases/latest/download/arkab-macos-aarch64.zip` |
| Checksums | `https://github.com/teapot-chess/Arkab/releases/latest/download/SHA256SUMS` |
| All versions, release notes | `https://github.com/teapot-chess/Arkab/releases` |

## Instructions, three lines each

**Windows**: download `Arkab-Setup.exe` and run it (Windows warns that it
does not know the program: "More info", then "Run anyway"); leave the small
window open, closing it stops the bridge; open the page it shows on port
4050 and paste the join link from Alnasl (Halls, your hall, Bridges, *Add a bridge*).

**Raspberry Pi and Linux**: run the one-line installer from the README;
open `http://<the box>:4050`; paste the join link.

**Mac**: unzip, open `Arkab.app` (the first time with *Open Anyway*);
paste the join link on the page.

## What not to say

Nothing about boards of a particular make by name; "electronic boards" is
enough. Nothing about speed or reliability that nobody has measured.

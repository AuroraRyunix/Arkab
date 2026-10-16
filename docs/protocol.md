# The bridge link, version 1

How an Arkab bridge and an Alnasl server talk. `Arkab.Protocol` is this
document in code. Both ends compile that module, so neither can read the
rules differently from the other. If this page and the module disagree,
the module is right and this page is the bug.

## Joining (HTTP, once)

The server shows a link, `https://<host>/join/<code>`, and a QR code of
that link. The code is short, works once, and expires after 15 minutes.
The bridge's page takes the link, pasted or scanned, and the bridge does
the rest. Nobody types a key.

```
POST /join/<code>
content-type: application/json

{"v": 1, "bridge": "<bridge id>", "name": "<bridge name>", "software": "arkab 0.1.0"}
```

| answer | meaning |
|---|---|
| `200 {"key", "socket", "server", "owner"}` | joined. `key` is this bridge's long secret for this server. `socket` is the path of the link (`/bridge/link`). `server` is the name to show. `owner` says whether this server may make the bridge forget boards and ports |
| `404`, `410` | the code is unknown, used up or expired |
| `400` with `{"error": "version"}` | the server does not speak this version |

The socket URL keeps the join link's host and port. Its scheme is `ws`
for a link on `http` and `wss` for one on `https`, so TLS in production
needs nothing beyond an https link.

## The link (one WebSocket per server)

The bridge always dials out. A hall has no reason to accept connections
from the internet, and with this design it never has to. All frames are
JSON text frames, each an object with a `"type"`.

### Bridge to server

| type | fields | meaning |
|---|---|---|
| `hello` | `v`, `bridge`, `key`, `name`, `software` | always the first frame. The key goes here, not in the URL, because URLs end up in proxy logs |
| `events` | `events: [event]` | driver events, oldest first, numbered |
| `boards` | `boards`, `ports`, `recording` | what the bridge reads right now. Sent after `welcome` and again on every change |
| `reply` | `id`, `ok`, `error` | the answer to a command |
| `leave` | | this server was removed on the bridge |

### Server to bridge

| type | fields | meaning |
|---|---|---|
| `welcome` | `v`, `seen`, `server` | accepted. `seen` is the highest event number the server holds, and the bridge counts everything up to it as acknowledged |
| `refused` | `reason` | `version`; `key` (not a key the server knows); `revoked` (removed on the server, so the bridge forgets it too) |
| `ack` | `seq` | everything up to and including `seq` belongs to the server now |
| `command` | `id`, `cmd`, fields | see below |
| `leave` | | this bridge was removed on the server |

### An event

```json
{"s": 1042, "t": 1760600000123, "id": "COM3#12799", "e": {"k": "pos", "b": "rnbqkbnr..."}}
```

- `s`: the event's number in the bridge's queue. Numbers only go up and are never reused, even across restarts.
- `t`: when it happened, in milliseconds. For a real board this is the bridge's wall clock. For a played-back capture it is the recording's own clock, and the event also carries `"at": [speed, next]` (see `Arkab.Driver.Player`).
- `id`: the board, as returned by `Arkab.Protocol.board_id/2`. For a single board that is its port; on a loop it is `port#address`.
- `e`: the driver event (`Arkab.Driver`), in the capture file's words where the capture format has a word for it: positions, clock readings, connected and disconnected, what a board says about itself (only the names in `Arkab.Protocol`'s list, so the server never makes a new atom), and polls.

Raw serial bytes are never sent. They go to the bridge's own capture files
while recording is on, and stay there. Successful polls are thinned to one
a second; a missed poll is always sent.

### Delivery

- The bridge writes every event to its SQLite queue before it sends it anywhere. A power cut loses what the board had not said yet, and nothing it had.
- Each server has its own cursor. A server that is down holds up nobody else. The queue keeps an event until every server has acknowledged it, and not one minute longer.
- At most 1000 unacknowledged events are in flight to a server, sent in batches of 200.
- The server acknowledges by number after it has stored and processed the events, in that order. It ignores numbers it has already seen, so an event sent twice (the line went down after the server stored it but before the ack arrived) is processed once.
- A server added later starts at the end of the queue. It gets the boards' current state from `resend`, not from old history.
- Pings every 25 s. A link with no answer for 75 s is treated as dead. Reconnect waits 1 s and doubles up to 30 s; after a refusal it waits 60 s.

### Commands

Applied on the bridge one at a time, in arrival order across all servers.
When two servers disagree, both are obeyed and the later one wins.

| cmd | fields | |
|---|---|---|
| `resend` | `board` (optional) | the whole board again: status, what it says about itself, position, clock. The server sends this on every connect |
| `rescan` | `port` (optional) | read the port(s) again from scratch, which finds a loop again |
| `add_port` | `port` | read this port from now on, including after a restart |
| `forget_port` | `port` | owner only: stop reading it |
| `forget_board` | `board` | owner only: stop reading this board until its port is added again |
| `record` | `on` | capture files on or off |

### Removing

Remove on either side ends the link for both. Removed on the bridge, the
bridge sends `leave` if it can reach the server. If it cannot, the bridge
forgets the server anyway and never dials it again, so the server's row
shows a bridge that stays away until someone removes it there too. Removed on the server, the
server sends `leave` to a connected bridge, or `refused "revoked"` the
next time a disconnected one dials in.

## Versions

`v` appears in the join request, `hello` and `welcome`. A server that does
not accept the bridge's version says `refused "version"` and does not try
to make sense of what follows. Version 1 is the only version so far.

## Why mint_web_socket

The bridge is a WebSocket *client*: one outgoing socket per server, with
pings, backoff, and a cursor that must not move until an ack arrives.
Options considered:

- **mint_web_socket** (chosen). From the Mint maintainers. Mint is already in the tree through Req and Finch, so this adds one small package and no new HTTP stack. It is process-less: the socket is data inside `Arkab.Bridge.Link`'s own GenServer, so connect, reconnect, ack bookkeeping and backpressure all live in one process with one mailbox and no second process to keep in step. It passes the Autobahn suite, speaks TLS through Mint's transport, and is maintained (1.0.x).
- **gun**: capable, but it brings cowlib and its own process model. That is a second supervision story for one socket, and a large dependency for a bridge on a Raspberry Pi.
- **websockex**: a process per socket with its own callbacks. Coordinating its reconnects with the queue cursor would mean messages between two processes about state only one of them should own. It has also seen little maintenance.
- **Phoenix channels client** (slipstream and similar): would make the link speak Phoenix channel framing. The server end is a bare `Phoenix.Socket.Transport` so that the protocol stays this page, not channel topics and refs.

# shikikan.hml

Lobby and game session server framework for Hemlock, built on gn.hml.

"Shikikan" (指揮官) means "commander" in Japanese.

## Architecture

Two layers:

- `lib/` — Generic lobby server framework (reusable across games)
  - IPC with GameRouter via stdout NDJSON events and stdin commands
  - Connection lifecycle: join, leave, heartbeat, reconnect by UID
  - Host authority model: host player has elevated permissions
  - Lobby management: player slots, spectators, password protection
  - Timer patterns via spawn() + sleep() with channels

- `src/` — Raifu Wars game logic (first consumer of lib/)
  - Turn-based gameplay: roll, move, attack, end turn
  - Map loading: zlib decompression, sha1 hashing
  - Deck/card system with customizable weights, tiers, costs
  - Coin spawning mechanics
  - 1v1 mode with team slot management
  - Save/load compressed game state for reconnection

## Key Design Decisions

- No mutexes needed: gn.hml server callbacks are sequential on one thread
- Timers are spawn() + sleep() tasks that send messages back via channels
- IPC is newline-delimited JSON on stdout (events) and stdin (commands)
- Wire-compatible with gn.js: existing GameMaker clients work unchanged

## Dependencies

- `Yotis-Studios/gn.hml` — WebSocket networking (via hpm)
- `@stdlib/hash` — sha1 for map hashing
- `@stdlib/compression` — zlib for map/save data
- `@stdlib/random` — dice rolls, luck values, coin spawns
- `@stdlib/json` — IPC message serialization
- `@stdlib/time` — sleep for timer tasks

## IPC Protocol (stdout events)

```json
{"event":"port","data":12345}
{"event":"players","data":3}
{"event":"name","data":"My Lobby"}
{"event":"isStarted","data":1}
{"event":"mapHash","data":"abc123..."}
{"event":"mapName","data":"Desert Map"}
{"event":"numPlayers","data":4}
{"event":"locked","data":1}
{"event":"gameSpeed","data":2}
{"event":"gameLength","data":1}
{"event":"spectators","data":true}
```

## Running

```bash
hpm install
hemlock server.hml
```

## Packet IDs

Packet IDs in `src/id.hml` must match the GameMaker client exactly.
Do not renumber without updating the client.

**This is now checked rather than remembered.** The client repo carries
`tools/check-packet-ids.py`, which compares `src/id.hml` against
`scripts/net_event_ids/net_event_ids.gml` and runs as part of its `compile-check.sh`. Point it
here with `RW_SHIKIKAN=/path/to/shikikan.hml` if the repo is not at `~/Projects/shikikan.hml`.

It catches three things:

- a name defined on both sides with different numbers
- the same number used twice within one side
- a name defined on only ONE side whose number collides with a live id on the other -- one-sided
  ids are normal (`PREMIUM_KEY` is client-only, `MAP_CLIMATE` is server-only and unused), but a
  collision means one end acts on the other's packet as something else

**Why it matters more than most invariants:** a mismatch does not crash and does not fail to
parse. Both ends read a number and dispatch on it, so one end just performs the wrong action.

## Protocol reference

`RaifuWars/docs/protocol/PROTOCOL.md` in the client repo documents the whole protocol -- the three
packet shapes, what 1.14 added and why, host migration, the client's packet queue lock, and notes
for a redesign. It is the shared reference; neither repo owns the protocol alone.

## 1.14: GAME_NUM_PLAYERS (115)

The host may resize the lobby roster online. Previously every client derived `numPlayers` from the
map, so a host changing it alone disagreed with the lobby about which slots exist -- the client's
stepper was gated offline-only for that reason.

**The host asks; this server decides.** `packet_handler` clamps the request to `num_bases`, to a
minimum of 2, and to an even number, then broadcasts a NEW packet carrying the clamped value to
everyone including the asker.

Rebuilding rather than relaying is the point: relaying the incoming packet would tell the other
clients what was ASKED for, and a clamped request would leave the host one step ahead of the lobby
-- the exact disagreement the packet exists to remove. `set_num_players` already existed (it emits
the `numPlayers` IPC event GameRouter lists lobbies with); it simply had no packet reaching it.

Even-ness matters: team play halves the roster and the client rounds nowhere, so an odd count is a
silently mismatched team rather than an error.

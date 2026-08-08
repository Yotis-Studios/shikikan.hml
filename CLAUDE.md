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

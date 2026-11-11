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
  - `realtime.hml`: a server-stepped match on the session (tick, intents, snapshots, end),
    with the rules supplied by the game as hooks; driven by gn.hml's `Server.every()`

- `src/start_server.hml` — the server as `start_server(opts)`; `server.hml` is
  `start_server({})`, Raifu Wars. `opts.realtime` adds a match (see README, "A real-time game")
- `src/platform.hml` — Yotis Online on the session: verified players and pinned seats, public
  (Quick Play) matches, chat moderation, reports, GameRouter's commands
- `src/` — Raifu Wars game logic (first consumer of lib/)
  - Turn-based gameplay: roll, move, attack, end turn
  - Map loading: zlib decompression, sha1 hashing
  - Deck/card system with customizable weights, tiers, costs
  - Coin spawning mechanics
  - 1v1 mode with team slot management
  - Save/load compressed game state for reconnection

## Key Design Decisions

- No mutexes needed: gn.hml server callbacks are sequential on one thread, and so are
  `Server.every()` timers (gn.hml 0.4.0+). Use those for anything that changes match state
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
{"event":"gameMode","data":2}
{"event":"public","data":true}
{"event":"humans","data":2}
{"event":"bots","data":1}
{"event":"joinable","data":true}
{"event":"join","data":{"sub":"g:12","name":"Ace","slot":0}}
{"event":"leave","data":{"sub":"g:12","slot":0}}
{"event":"report","data":{"match":"...","reporter":"g:12","reported":"u:5","reason":"...","lines":[...]}}
{"event":"result","data":{"game":"biplane-battle","match_ref":"<start>/<seed>/<n>","humans":2,"players":[{"slot":0,"sub":"g:12","human":true,"game_xp":250,"stats":{}}]}}
```

`result` comes from a realtime game's optional `results(match)` hook when its match ends by its
own rules (lib/realtime.hml, "RESULTS"); GameRouter forwards it to Yotis Online as YO XP. Hemlock
reserves `match` and `ref`, hence `match_ref`.

Commands on stdin (src/platform.hml): kick, mute, announce, close, reserve, jwks -- see README,
"Yotis Online". `lib/identity.hml` verifies player tokens through libcrypto (Ed25519 is not in
@stdlib/crypto). Tests that run the server in-process share nothing with it but channels
(`test/harness.hml` says why: arrays shared across tasks segfaulted).

## Running

```bash
hpm install
hemlock server.hml
```

## Before a release, and deploying one

- **Compile it: `hemlockc server.hml -o shikikan-server`.** Production runs this binary from yotis-ops
  stage 9 on (November 2026; `HEMLOCK_BIN=./shikikan-server`, relative to the release, with the
  source beside it so the interpreter is a fallback by router setting alone). A release is built
  on a build box with its `hem_modules` and ships `shikikan-server` at its root. Before 2.14 the
  compiler was also the only check that resolved every name -- a `sleep` that was never imported
  killed the start watchdog silently for weeks (`test/start_watchdog_test.hml`).
- **Run every test, both ways**: `bash test/run_tests.sh` and `bash test/run_tests.sh --compiled`.
  The compiled run is the one that matches production. Two hemlockc bugs shaped the tests:
  a top-level `fn join` in an entry file breaks the builtin `join()` in every other module
  (hemlang/hemlock#677, hence `join_as`), and a `let x = null` stays typed null after
  reassignment (#678, hence `slot = -1`).
- **Deploy with GameRouter's `tools/game-release.sh`** (GameRouter README, "Deploying a game
  server"), packed with `hem_modules` on a build box. It installs the release beside the current
  one and switches the router's `GAME_SERVER_DIR` link: running matches keep their release, the
  next one gets the new one, and nothing restarts. Never copy over the live directory.

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

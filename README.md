# shikikan.hml

Lobby and game session server framework for [Hemlock](https://github.com/hemlang/hemlock), built on [gn.hml](https://github.com/Yotis-Studios/gn.hml).

Designed to work with [GameRouter](https://github.com/Yotis-Studios/GameRouter) for matchmaking and lobby management.

Currently includes the [Raifu Wars](https://store.steampowered.com/app/1685500/Raifu_Wars/) game server implementation.

## Prerequisites

- [Hemlock](https://github.com/hemlang/hemlock) 2.0+
- [hpm](https://github.com/hemlang/hpm)
- libwebsockets (`apt install libwebsockets-dev`)

## Setup

```bash
hpm install
hemlock server.hml
```

The server binds to a random available port and reports it via stdout for GameRouter to pick up.

## Project Structure

```
shikikan.hml/
├── lib/                    # Generic lobby server framework
│   ├── index.hml           # Public exports
│   ├── lobby.hml           # IPC, lifecycle, port binding
│   ├── session.hml         # Connection management, heartbeat, reconnect
│   ├── realtime.hml        # A server-stepped match on top of the session
│   └── host.hml            # Host authority validation
├── src/                    # Raifu Wars game logic
│   ├── game.hml            # Turn management, start/end lifecycle
│   ├── packet_handler.hml  # Packet dispatch, turn validation
│   ├── player.hml          # Player state, CPU detection
│   ├── map.hml             # Map decompression, hashing, coins
│   ├── deck.hml            # Card deck configuration
│   ├── save_data.hml       # Save/load game state
│   ├── start_server.hml    # The server: start_server(opts)
│   ├── id.hml              # Packet ID constants
│   └── colors.hml          # Player color constants (BGR)
└── server.hml              # Raifu Wars' entry point: start_server({})
```

## A real-time game

A game whose server steps the match (rather than relaying moves between clients) keeps the same
lobby, seating, ready, start and router IPC, and supplies its rules as hooks:

```hemlock
import { start_server } from "Yotis-Studios/shikikan.hml";
import { setenv } from "@stdlib/env";

setenv("SHIKIKAN_REQUIRE_MAP", "0");   // or set it in the router descriptor
start_server({
    realtime: {
        new_match: fn(seed, seats) { ... },       // -> the match state
        intent: fn(m, slot, values) { ... },      // the seat's latest intent
        step: fn(m) { ... },                      // one tick
        snapshot: fn(m, slot) { return [...]; },  // gn values for that seat
        over: fn(m) { ... },                      // -> bool, after each tick
        fingerprint: fn(m) { ... },               // -> string, sent with the end
    },
    tick_hz: 30,
    send_hz: 20,
});
```

The match starts when the session does (the host's `GAME_START`) and runs on gn.hml's
`Server.every()`, on the same thread as packet handlers. Clients send `GBE_RT_INTENT` (172) and
receive `GBE_RT_START` (171) and `GBE_RT_SNAPSHOT` (173); `src/id.hml` has the layouts and
`lib/realtime.hml` the details. `test/realtime_test.hml` plays a whole match headless, and passes
under `FUZZ_DELAY_MS=80 FUZZ_PERCENT=30` too. `examples/realtime_toy.hml` is a complete server on
toy rules; the Ganbatte engine tests its client against it (`GBE_NET_MODE=realtime`).

## Building a New Game

To build a different game on shikikan:

1. Import from `lib/` for lobby, session, and host management
2. Write your own packet handler and game logic
3. Define your packet IDs
4. Wire it up in your own `server.hml` entry point

The `lib/` layer handles connection lifecycle, heartbeat, IPC with GameRouter, and host authority — you just implement game rules.

## License

MIT

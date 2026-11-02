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
        leave: fn(m, slot) { ... },               // optional: a seat's connection went away
        rejoin: fn(m, slot) { ... },              // optional: that seat is back (same uid)
        summary: fn(m) { return {...}; },         // optional: the game's part of the match log
    },
    tick_hz: 30,
    send_hz: 20,
    match_log: "matches.jsonl",                   // optional; SHIKIKAN_MATCH_LOG overrides it
    game: "my-game",                              // optional: named in each log line
});
```

**Rejoining.** Once the match has started, the lobby takes back only seats it already has: a
connection presenting a seat's `CLIENT_UID` is put back in that slot and sent `GBE_RT_START` at
the current tick, and its intent sequence starts over. That holds while the old connection still
looks alive, too (a dropped Wi-Fi link the server has not noticed yet): the newer one takes the
seat over. Anyone else is told "The match has started." `test/realtime_rejoin_test.hml` drops a
seat, brings it back twice and turns a stranger away.

**The match log.** With `match_log` (or `SHIKIKAN_MATCH_LOG`) set, each match appends one JSON
line when it ends: when and how long, how it ended (`over`; `ended` when the session stopped it;
`closed` with the exit code, e.g. 2 when the last seat left), each seat with how often it left
and came back, dropped ticks, the fingerprint, and the game's `summary(m)`.

The match starts when the session does (the host's `GAME_START`) and runs on gn.hml's
`Server.every()`, on the same thread as packet handlers. Clients send `GBE_RT_INTENT` (172) and
receive `GBE_RT_START` (171) and `GBE_RT_SNAPSHOT` (173); `src/id.hml` has the layouts and
`lib/realtime.hml` the details. `test/realtime_test.hml` plays a whole match headless, and passes
under `FUZZ_DELAY_MS=80 FUZZ_PERCENT=30` too. `examples/realtime_toy.hml` is a complete server on
toy rules; the Ganbatte engine tests its client against it (`GBE_NET_MODE=realtime`).

## Yotis Online

`src/platform.hml` (platform phase P4, yo-account-api `docs/PLATFORM.md`). A client that sends none
of this to a lobby GameRouter did not make public plays exactly as before.

**Who is playing.** A client sends `GBE_AUTH` (176) `[player token, ticket]` before `CLIENT_UID`.
The token (Ed25519, from the account service) is verified here, through libcrypto
(`lib/identity.hml`), against the key set GameRouter passes in `ROUTER_JWKS`; the reply is
`GBE_AUTH [sub, name]`. The seat is then pinned to that `sub`: once a match has started, a seat
with a sub goes back only to a connection with the same sub, so a uid (which a client makes up)
no longer moves anyone into someone else's seat, and the returning player gets their seat back
whatever uid they bring. The player's name is the token's. GameRouter hears `join` and `leave`
with the sub.

**Public matches** (`ROUTER_PUBLIC=1`, Quick Play). Nobody is seated without a verified token and
either the ticket GameRouter reserved for their sub or a seat already theirs; a connection that
does not authenticate within 10 s is put out, and so is a token carrying a public-play ban. There is
no host: kick, password, name, settings, start and end are off, and the server starts the match
`SHIKIKAN_PUBLIC_START_S` (20) seconds after its first player sits down, or once every seat is
taken, with `SHIKIKAN_PUBLIC_LOBBY_DATA` as its settings and `SHIKIKAN_PUBLIC_MODE` as its
mode (a GAME_MODE number, or several joined with `,` for each match to play one at random). Empty seats are the game's bots. A
real-time game with a `take_seat(match, slot, { name, sub })` hook stays joinable after the start:
a Quick Play player takes a bot's seat. GameRouter hears `public`, `humans`, `bots` and `joinable`.

**Chat** is refused from muted players (GameRouter's `mute`, or a chat ban in the token), starred
out where it has a word from `SHIKIKAN_CHAT_FILTER` (a file, one a line), capped at 200 characters
in public matches, and the last 50 lines are kept. **Reports**: `GBE_REPORT` (178) `[slot, reason]`
from a verified player becomes a `report` event with both subs, the reason and the last 30 lines,
so a report carries what was said rather than what the reporter says was said. `GBE_ANNOUNCE`
(177) `[text]` is a line from the server or a moderator.

**GameRouter's commands** on stdin, one JSON line each: `kick {sub, reason}` (and not let back),
`mute {sub}`, `announce {text}`, `close {reason}` (exit code 3), `reserve {ticket, sub, name,
expires}`, `jwks {keys}`.

`test/identity_test.hml`, `test/platform_test.hml` (a private lobby) and
`test/platform_public_test.hml` (a Quick Play match) cover these.

## Building a New Game

To build a different game on shikikan:

1. Import from `lib/` for lobby, session, and host management
2. Write your own packet handler and game logic
3. Define your packet IDs
4. Wire it up in your own `server.hml` entry point

The `lib/` layer handles connection lifecycle, heartbeat, IPC with GameRouter, and host authority — you just implement game rules.

## License

MIT

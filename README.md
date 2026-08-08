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
│   └── host.hml            # Host authority validation
├── src/                    # Raifu Wars game logic
│   ├── game.hml            # Turn management, start/end lifecycle
│   ├── packet_handler.hml  # Packet dispatch, turn validation
│   ├── player.hml          # Player state, CPU detection
│   ├── map.hml             # Map decompression, hashing, coins
│   ├── deck.hml            # Card deck configuration
│   ├── save_data.hml       # Save/load game state
│   ├── id.hml              # Packet ID constants
│   └── colors.hml          # Player color constants (BGR)
└── server.hml              # Entry point
```

## Building a New Game

To build a different game on shikikan:

1. Import from `lib/` for lobby, session, and host management
2. Write your own packet handler and game logic
3. Define your packet IDs
4. Wire it up in your own `server.hml` entry point

The `lib/` layer handles connection lifecycle, heartbeat, IPC with GameRouter, and host authority — you just implement game rules.

## License

MIT

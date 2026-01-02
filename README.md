# Discord-Droid Bridge

**Two-way communication between Discord and the Droid CLI (Factory.ai)**

> ⚠️ **Requirements:** macOS + iTerm2 + Discord

Send messages from Discord threads directly into your Droid CLI session, and have Droid respond back to Discord automatically.

## How It Works

```
Discord Thread → mcp-discord (MCP) → discord-inbox.json
                                            ↓ fswatch (instant)
Session Registry → bridge-v2.sh → iTerm2 (direct TTY write, no focus steal)
                                            ↓
                                Stop Hook → droid-discord send → Discord Thread
```

**Key Features:**
- **Instant delivery** - fswatch detects messages immediately (no polling)
- **No focus stealing** - Messages inject directly via iTerm2's `write text` API
- **Multi-session support** - Each Droid session gets its own Discord thread
- **Auto-registration** - Skill handles session setup automatically

## Prerequisites

- **macOS** (uses AppleScript for iTerm2 automation)
- **iTerm2** (Terminal.app not supported in V2)
- **[Droid CLI](https://factory.ai)** installed
- **jq** (`brew install jq`)
- **fswatch** (`brew install fswatch`)
- **Discord bot** with Message Content Intent enabled

## Quick Start

### 1. Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create application → Add Bot
3. Enable **Message Content Intent** under Privileged Gateway Intents
4. Generate OAuth2 URL with `bot` scope and these permissions:
   - Send Messages, Read Message History, Manage Threads, Create Public Threads, Send Messages in Threads
5. Invite bot to your server
6. Copy the bot token

### 2. Install mcp-discord

You need an MCP server for Discord. Use [mcp-discord](https://github.com/slimslenderslacks/mcp-discord) with thread/watch extensions, or any compatible Discord MCP.

Add to `~/.factory/mcp.json`:
```json
{
  "mcpServers": {
    "discord": {
      "type": "stdio",
      "command": "npx",
      "args": ["@anthropic/mcp-discord"],
      "env": {
        "DISCORD_TOKEN": "your-bot-token-here"
      }
    }
  }
}
```

### 3. Configure Discord IDs

```bash
cp discord-config.example.json ~/.factory/discord-config.json
# Edit ~/.factory/discord-config.json with your guildId + channelId
```

### 4. Install Bridge

```bash
git clone https://github.com/YOUR_USERNAME/discord-droid-bridge.git
cd discord-droid-bridge

# Add to PATH (add to ~/.zshrc)
export PATH="$HOME/path/to/discord-droid-bridge/bin:$PATH"

# Export TTY for Droid (add to ~/.zshrc)
# This enables bridge auto-registration when a thread is created but not registered.
export DROID_TTY=$(tty 2>/dev/null || echo "")
```

### 5. Install Skill

```bash
cp skill/discord-notify.md ~/.factory/skills/discord-notify.md
```

### 6. Grant Permissions

System Settings → Privacy & Security → Accessibility:
- Add iTerm2
- Add `/usr/bin/osascript`

## Usage

### In Droid

Use the skill once per session:
```
Use the discord-notify skill to set up Discord for this session
```

The skill will:
1. Create a Discord thread
2. Watch it for incoming messages
3. Register the session (TTY + PID)
4. Start the bridge if not running

### From Discord

Send a message in the thread. It appears in Droid instantly, and Droid responds back to Discord via hooks (deterministic).

## Hooks (Required for Full Two-Way Communication)

Hooks make the bridge fully automatic - no need for the model to manually call MCP tools.

### Install All Hooks

```bash
# Copy all hooks to Factory's hooks directory
cp hooks/*.sh ~/.factory/hooks/
chmod +x ~/.factory/hooks/*.sh
```

### Configure Hooks in Settings

Add to `~/.factory/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.factory/hooks/discord-session-start.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.factory/hooks/discord-prompt-submit.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.factory/hooks/discord-stop.sh"
          }
        ]
      }
    ]
  }
}
```

### What Each Hook Does

| Hook | Purpose |
|------|---------|
| `discord-session-start.sh` | Starts heartbeat daemon when session begins |
| `discord-prompt-submit.sh` | Sends "Got it!" acknowledgment, restarts heartbeat |
| `discord-stop.sh` | Sends final response to Discord, stops heartbeat |
| `discord-heartbeat.sh` | Background daemon that sends periodic "still working" messages |

### Heartbeat Configuration

The heartbeat sends a witty "still working" message every 60 seconds by default. Configure with:

```bash
export DISCORD_HEARTBEAT_INTERVAL=90  # seconds between messages
```

Example messages:
- "Still crunching through your request... (~2m elapsed)"
- "Working on it - haven't forgotten about you!"
- "In the zone, be back soon..."

### Manual Heartbeat Control

```bash
# Check heartbeat status
~/.factory/hooks/discord-heartbeat.sh status

# Stop heartbeat manually
~/.factory/hooks/discord-heartbeat.sh stop
```

## Components

| Component | Purpose |
|-----------|---------|
| `bridge-v2.sh` | Main daemon - watches inbox, injects to iTerm2 |
| `bin/droid-discord` | CLI tool for session management |
| `lib/config.sh` | Paths, logging, and locking utilities |
| `lib/registry.sh` | Session registration (TTY + PID tracking) |
| `lib/inject.sh` | iTerm2 AppleScript injection |
| `skill/discord-notify.md` | Droid skill for auto-setup |
| `hooks/discord-heartbeat.sh` | Background heartbeat daemon |
| `hooks/discord-session-start.sh` | SessionStart hook - starts heartbeat |
| `hooks/discord-prompt-submit.sh` | UserPromptSubmit hook - acknowledgment + restart heartbeat |
| `hooks/discord-stop.sh` | Stop hook - sends response, stops heartbeat |

## CLI Commands

```bash
droid-discord register <threadId> [name]  # Register session
droid-discord deregister [threadId]       # Deregister session
droid-discord status                      # Show current session
droid-discord list                        # List all sessions
droid-discord start                       # Start bridge (foreground)
droid-discord start-bg                    # Start bridge (background)
droid-discord stop                        # Stop bridge
droid-discord logs                        # Show bridge logs
droid-discord send <threadId> [message]   # Send message to Discord thread (stdin if omitted)
```

## Files

| File | Location | Purpose |
|------|----------|---------|
| `droid-sessions.json` | `~/.factory/` | Session registry |
| `discord-inbox.json` | `~/.factory/` | Incoming messages (from mcp-discord) |
| `discord-queue.json` | `~/.factory/` | Retry queue |
| `bridge-v2.log` | `~/.factory/` | Bridge logs |

## Troubleshooting

### Messages not reaching Droid

1. Check session is registered: `droid-discord list`
2. Check bridge is running: `pgrep -f bridge-v2.sh`
3. Check logs: `droid-discord logs`

### "No session for thread" in logs

The session wasn't registered. Run the skill's registration command or manually:
```bash
droid-discord register <threadId> "[project:branch]"
```

### Permission errors

Grant Accessibility permissions to iTerm2 and `/usr/bin/osascript` in System Settings.

## How Sessions Work

Each Droid session registers with:
- **threadId** - Discord thread for this session
- **tty** - Terminal device (e.g., `/dev/ttys005`)
- **pid** - Process ID (for liveness checks)

Messages are routed by threadId → TTY lookup. Dead sessions (PID gone) are cleaned up automatically.

## License

MIT

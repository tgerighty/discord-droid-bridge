# Discord-Droid Bridge

Bridges Discord messages into an active Droid CLI session, enabling remote control of Droid via Discord.

## How it Works

1. The `mcp-discord` MCP server watches Discord threads for messages
2. When a message arrives, it writes to `~/.factory/discord-inbox.json`
3. This bridge script monitors that file
4. When a new message is detected, it finds the terminal window running Droid
5. It injects the message as keyboard input, as if you typed it

## Prerequisites

- macOS (uses AppleScript for terminal control)
- `jq` installed (`brew install jq`)
- `mcp-discord` MCP server configured and running
- A Discord thread being watched via `discord_watch_thread`

## Usage

```bash
# Start the bridge in a separate terminal
./bridge.sh

# Or with custom interval (default 5 seconds)
CHECK_INTERVAL=10 ./bridge.sh
```

## Setup

1. In your Droid session, create and watch a Discord thread:
   ```
   discord_create_thread(channelId: "YOUR_CHANNEL", name: "[project:branch]")
   discord_watch_thread(threadId: "RETURNED_THREAD_ID")
   ```

2. Start the bridge in a separate terminal window

3. Send messages in the Discord thread - they'll appear in your Droid session!

## How it Finds Droid

The bridge looks for terminal windows (Terminal.app or iTerm2) with "droid" in the window title. It automatically detects which app you're using.

## Files

- `bridge.sh` - Main bridge script
- `~/.factory/discord-inbox.json` - Written by mcp-discord when messages arrive
- `~/.factory/discord-inbox-processed.txt` - Tracks which messages have been injected

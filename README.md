# Discord-Droid Bridge

A complete solution for two-way communication between Discord and the Droid CLI (Factory.ai). Send messages from Discord and have them injected directly into your active Droid session, with responses sent back to Discord.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Discord   │────▶│   mcp-discord    │────▶│  bridge.sh      │────▶│  Droid CLI   │
│   Thread    │     │   (MCP Server)   │     │  (Background)   │     │  (Terminal)  │
└─────────────┘     └──────────────────┘     └─────────────────┘     └──────────────┘
       ▲                    │                                               │
       │                    ▼                                               │
       │            ~/.factory/discord-inbox.json                           │
       │                                                                    │
       └────────────────────────────────────────────────────────────────────┘
                              (Droid responds via discord_send_thread_message)
```

## Components

### 1. mcp-discord (MCP Server)
Located at: `~/mcp-discord`

An extended version of [slimslenderslacks/mcp-discord](https://github.com/slimslenderslacks/mcp-discord) with added features:
- Thread creation and management
- Thread watching with auto-inbox
- File-based message notifications

**Key tools added:**
- `discord_create_thread` - Create a thread in a text channel
- `discord_watch_thread` - Start watching a thread for incoming messages
- `discord_unwatch_thread` - Stop watching a thread
- `discord_get_unread_messages` - Get unread messages from watched threads
- `discord_send_thread_message` - Send a message to a thread
- `discord_read_thread_messages` - Read messages from a thread
- `discord_clear_inbox` - Clear the message inbox

### 2. bridge.sh (This Repo)
A background script that:
- Monitors `~/.factory/discord-inbox.json` for new messages
- Routes messages to the **specific terminal session** that owns the thread (by threadId in window title)
- Supports multiple concurrent Droid sessions with session isolation
- Injects Discord messages via clipboard paste (Terminal.app) or direct write (iTerm2)
- Tracks processed messages to avoid duplicates

### 3. discord-notify Skill
Located at: `~/.factory/skills/discord-notify/skill.md`

A Droid skill that instructs the AI to:
- Always respond to Discord messages via the thread
- Send full responses (not summaries) to Discord
- Check for unread messages periodically

## Prerequisites

- macOS (uses AppleScript for terminal automation)
- [Droid CLI](https://factory.ai) installed
- `jq` installed (`brew install jq`)
- Discord bot with:
  - Message Content Intent enabled
  - Server Members Intent enabled
  - Presence Intent enabled
  - Bot added to your server with appropriate permissions

## Setup

### Step 1: Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application → Add Bot
3. Enable Privileged Gateway Intents:
   - Message Content Intent ✓
   - Server Members Intent ✓
   - Presence Intent ✓
4. Generate OAuth2 URL with `bot` scope and permissions:
   - Send Messages
   - Read Message History
   - Add Reactions
   - Manage Channels
   - Manage Threads
   - Create Public Threads
   - Send Messages in Threads
5. Invite bot to your server using the generated URL
6. Copy the bot token

### Step 2: Install mcp-discord

```bash
git clone https://github.com/slimslenderslacks/mcp-discord.git ~/mcp-discord
cd ~/mcp-discord
npm install
npm run build
```

Apply the custom patches (thread support, watch/inbox, file writing) - see `mcp-discord-patches/` directory.

### Step 3: Configure MCP in Droid

Add to `~/.factory/mcp.json`:

```json
{
  "mcpServers": {
    "discord": {
      "type": "stdio",
      "command": "node",
      "args": [
        "/Users/YOUR_USERNAME/path/to/mcp-discord/build/index.js"
      ],
      "env": {
        "DISCORD_TOKEN": "YOUR_DISCORD_BOT_TOKEN"
      }
    }
  }
}
```

### Step 4: Grant macOS Permissions

The bridge uses AppleScript to inject keystrokes. Grant Accessibility permissions:

1. Open System Settings → Privacy & Security → Accessibility
2. Add `/usr/bin/osascript`
3. Add Terminal.app (or iTerm2)

### Step 5: Install the Skill

Copy `skill.md` to `~/.factory/skills/discord-notify/skill.md`

### Step 6: Start the Bridge

```bash
# In a separate terminal (or run in background)
~/discord-droid-bridge/bridge.sh

# Or run in background
nohup ~/discord-droid-bridge/bridge.sh > ~/.factory/bridge.log 2>&1 &
```

## Usage

### In Droid Session

```bash
# 1. Create and watch a thread
discord_create_thread(channelId: "YOUR_CHANNEL_ID", name: "[project:branch] - 2025-01-01")
discord_watch_thread(threadId: "RETURNED_THREAD_ID")

# 2. Set your terminal title to include the threadId for session routing
# In Terminal.app or iTerm2:
echo -ne "\033]0;droid-THREAD_ID\007"

# Or use this shell function (add to ~/.zshrc):
droid-title() { echo -ne "\033]0;droid-$1\007"; }
# Then: droid-title THREAD_ID

# 3. Send a message
discord_send_thread_message(threadId: "THREAD_ID", message: "Hello from Droid!")

# 4. Check for messages
discord_get_unread_messages()
```

### From Discord

Simply send a message in the watched thread. The bridge will:
1. Detect the new message in `~/.factory/discord-inbox.json`
2. Find the terminal window with the matching **threadId** in its title
3. Inject the message into **only that session**
4. Droid processes and responds back to Discord

### Multi-Session Support

Each Droid session can have its own Discord thread. Messages are isolated by threadId:

```
Terminal 1: title="droid-1234567890"  ←── receives messages from thread 1234567890
Terminal 2: title="droid-0987654321"  ←── receives messages from thread 0987654321
```

If no terminal has a matching threadId in its title, the message is logged but not injected.

## Files

| File | Location | Purpose |
|------|----------|---------|
| `bridge.sh` | This repo | Main bridge script |
| `mcp-discord/` | `~/mcp-discord` | Extended MCP server |
| `discord-notify/skill.md` | `~/.factory/skills/discord-notify/` | Droid skill |
| `discord-inbox.json` | `~/.factory/` | Incoming message queue |
| `discord-inbox-processed.txt` | `~/.factory/` | Processed message IDs |
| `bridge.log` | `~/.factory/` | Bridge logs (when run in background) |
| `mcp.json` | `~/.factory/` | MCP server configuration |

## Configuration

Environment variables for `bridge.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECK_INTERVAL` | `5` | Seconds between inbox checks |

## Troubleshooting

### Bridge not injecting messages

1. Check Accessibility permissions for `osascript`
2. Ensure Droid window title contains "droid"
3. Check `~/.factory/bridge.log` for errors

### Messages not appearing in inbox

1. Verify thread is being watched: `discord_get_unread_messages()` should show `watchedThreads`
2. Check mcp-discord is running (restart Droid)
3. Verify `~/.factory/discord-inbox.json` is being updated

### "osascript is not allowed to send keystrokes"

Grant Accessibility permission to `/usr/bin/osascript` in System Settings.

## Security Notes

- The Discord bot token is stored in `~/.factory/mcp.json` - keep this file secure
- The bridge has access to your terminal - only run in trusted environments
- Messages are stored temporarily in `~/.factory/discord-inbox.json`

## License

MIT

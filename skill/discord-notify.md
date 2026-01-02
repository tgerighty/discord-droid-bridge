---
name: discord-notify
description: Create and manage a Discord session thread for the current Droid session (create thread, watch it, register locally, start the bridge). Also use for sending important messages to Discord when awaiting input or reporting completion.
---

# Discord Notification Skill

## FIRST: Load Discord Config

**BEFORE doing anything else**, read the config file:

```bash
cat ~/.factory/discord-config.json
```

Expected format:
```json
{
  "guildId": "YOUR_SERVER_ID",
  "channelId": "YOUR_CHANNEL_ID"
}
```

**If the file doesn't exist or is missing IDs**, tell the user:

> Discord is not configured. Create `~/.factory/discord-config.json`:
> ```json
> {
>   "guildId": "YOUR_SERVER_ID",
>   "channelId": "YOUR_CHANNEL_ID"
> }
> ```
> To get these IDs in Discord:
> 1. Enable Developer Mode: User Settings → Advanced → Developer Mode
> 2. Right-click server icon → "Copy Server ID"
> 3. Right-click channel → "Copy Channel ID"

**Store the `channelId`** - use it for `discord_create_thread`.
**Do NOT call server lookup tools** (avoid `discord_get_server_info` / `discord_list_servers`). The config already has what you need.

If `DROID_TTY` is not set, prompt the user to add this to `~/.zshrc`:
```bash
export DROID_TTY=$(tty 2>/dev/null || echo "")
```

## Primary Trigger

If the user says any of the following (or close variants), you MUST run the session setup steps below:
- "Create a Discord thread for this session"
- "Create a Discord thread for this session and register it"
- "Set up Discord for this session"

## Auto-Response Behavior

Use hooks for deterministic replies. The bridge prefixes Discord messages with `[Discord:<threadId>]` in the terminal.

## When to Use

- **Questions needing input** - When blocked
- **Task completion** - Significant work done
- **Errors** - Something failed
- **Decisions** - Multiple options to choose

Do NOT use for: progress updates, tool results, intermediate steps.

## Starting a Session Thread

### Step 1: Read Config
```bash
cat ~/.factory/discord-config.json
```

### Step 2: Create Thread
Use `channelId` from config:
```
discord_create_thread(
  channelId: "<channelId-from-config>",
  name: "[project:branch] - YYYY-MM-DD HH:MM",
  message: "Session started. Working on: <short description>"
)
```

### Step 3: Watch Thread
```
discord_watch_thread(threadId: "<returned-thread-id>")
```

### Step 4: Register Session (Required)
```bash
THREAD_ID="<thread-id>" && \
THREAD_NAME="[project:branch]" && \
echo "$THREAD_ID" > "$HOME/.factory/current-discord-session" && \
droid-discord register "$THREAD_ID" "$THREAD_NAME" && \
pgrep -f "bridge-v2.sh" > /dev/null || droid-discord start-bg
```

Store the `threadId` for all messages in this session.

### Step 5: Confirm Registration
```bash
droid-discord status
```
If the session is not registered, repeat Step 4.

## Sending Messages

```
discord_send_thread_message(threadId: "<session-thread-id>", message: "Your message")
```

## Reading Responses

```
discord_get_unread_messages(threadId: "<session-thread-id>")
```

## Quick Reference

| Action | Command |
|--------|---------|
| Create thread | `discord_create_thread(channelId, name, message)` |
| Watch thread | `discord_watch_thread(threadId)` |
| Send message | `discord_send_thread_message(threadId, message)` |
| Get unread | `discord_get_unread_messages(threadId)` |
| Rename thread | `discord_rename_thread(threadId, newName)` |
| Stop watching | `discord_unwatch_thread(threadId)` |

**User commands:**
- `droid-discord register <threadId> [name]` - Register session
- `droid-discord status` - Show status
- `droid-discord start-bg` - Start bridge daemon
- `droid-discord send <threadId> [message]` - Send message to Discord (stdin if omitted)

---
name: discord-notify
description: Send important messages to Discord when you need user input or have completed a significant task. Use this when awaiting a response, reporting completion, or asking questions - NOT for status updates or tool calls.
---

# Discord Notification Skill

## CRITICAL: Auto-Response Behavior

**When a Discord thread is active (watched), you MUST:**

1. **ALWAYS respond to Discord** - Every message from Discord (injected via bridge) MUST get a response sent back to the Discord thread using `discord_send_thread_message`. Send the FULL response you show in the CLI, not a summary.
2. Check for unread messages at the START of processing any user message
3. After completing any significant task, send a summary to Discord

**If a message came from Discord (injected by bridge), ALWAYS reply to Discord, not just the CLI.**

The bridge prefixes Discord messages with `[Discord:<threadId>]` - when you see this prefix, your response MUST go to that Discord thread using:
```
discord_send_thread_message(threadId: "<threadId from prefix>", message: "<your full response>")
```

**Thread Ownership:** Each session has its own threadId. Only check/respond to YOUR session's thread by filtering with the threadId you created.

**Current session threadId:** Store this when you create/watch a thread and use it for all responses.

## When to Use This Skill

Invoke this skill when you need to notify the user via Discord. Use it for:

1. **Asking questions that need user input** - When you're blocked and need clarification
2. **Task completion** - When a significant task or feature is complete
3. **Errors requiring attention** - When something failed that the user needs to know about
4. **Decisions needed** - When there are multiple options and you need the user to choose

## When NOT to Use This Skill

Do NOT send Discord messages for:
- Progress updates or status messages
- Tool call results
- Intermediate steps
- Confirmations of small actions
- Working messages or thinking out loud

## Thread-Based Communication

Each Droid session should use its own thread to keep conversations organized.

### Starting a Session Thread (V2 - iTerm2 Only)

At the start of a session (or first time you need Discord), create, watch, and **self-register**:

```
// 1. Create the thread (name format: [project:branch] - date time)
discord_create_thread(
  channelId: "YOUR_CHANNEL_ID",
  name: "[project-name:branch] - YYYY-MM-DD HH:MM",
  message: "Session started. Working on: <brief description>"
)

// 2. Watch it for incoming messages (use the returned threadId)
discord_watch_thread(threadId: "<returned-thread-id>")

// 3. IMPORTANT: Self-register by injecting to the current TTY
// Get the TTY from the DROID_TTY environment variable (set by shell integration)
// Then inject the registration command:
```

**Self-Registration (REQUIRED):**

After creating/watching the thread, you MUST IMMEDIATELY execute this SINGLE command block (replace `THREAD_ID` and `THREAD_NAME` with actual values):

```bash
# ALL-IN-ONE: Check iTerm2, register session, start bridge
THREAD_ID="<your-thread-id>" && \
THREAD_NAME="[project:branch]" && \
if ! pgrep -f "iTerm" > /dev/null; then echo "ERROR: iTerm2 not running"; exit 1; fi && \
TTY="${DROID_TTY:-$(ps -p $PPID -o tty= | sed 's/^/\/dev\//' | tr -d ' ')}" && \
PID=$PPID && \
jq --arg tid "$THREAD_ID" --arg tty "$TTY" --argjson pid "$PID" --arg name "$THREAD_NAME" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.sessions[$tid] = {threadId: $tid, threadName: $name, tty: $tty, pid: $pid, registered: $now, lastActivity: $now}' \
   ~/.factory/droid-sessions.json > /tmp/sess.$$.json && mv /tmp/sess.$$.json ~/.factory/droid-sessions.json && \
echo "Registered: $THREAD_ID -> $TTY (PID $PID)" && \
if ! pgrep -f "bridge-v2.sh" > /dev/null; then ~/discord-droid-bridge/bin/droid-discord start-bg; else echo "Bridge already running"; fi
```

**CRITICAL:** 
- Execute this command IMMEDIATELY after `discord_watch_thread`. Do NOT skip this step.
- Replace `THREAD_ID` with the threadId returned from `discord_create_thread`.
- Replace `THREAD_NAME` with the thread name you used.
- If this fails, Discord messages will NOT reach this session.

Store the returned `threadId` for all subsequent messages in this session.

**V2 Benefits:**
- Messages inject directly into iTerm2 without stealing focus
- TTY-based routing is more reliable than window title matching
- Auto-deregister when terminal closes
- Branch change detection prompts to rename thread

### Branch Changes

When the user changes git branches, the shell hook will prompt them:
```
[droid] Branch changed: main -> feature/new-feature
To rename Discord thread, run in Droid:
  discord_rename_thread(threadId: "...", newName: "[project:feature/new-feature] - ...")
```

You can then call `discord_rename_thread` to update the thread name.

### Sending Messages

Use `discord_send_thread_message` with the session's threadId:
```
discord_send_thread_message(threadId: "<session-thread-id>", message: "Your message")
```

### Reading Responses (Automatic Inbox)

Once a thread is watched, user replies are automatically collected. Check the inbox:
```
discord_get_unread_messages(threadId: "<session-thread-id>")
```

This returns only unread messages from non-bot users and marks them as read.

### Workflow Example

1. Create thread + watch it at session start
2. Send message when you need user input
3. Continue working on other tasks
4. Periodically call `discord_get_unread_messages` to check for replies
5. Process any responses and continue

## Message Format

Keep Discord messages concise and actionable:
- State clearly what you need
- If asking a question, make it specific
- If reporting completion, summarize what was done

## Example Messages

**Good (needs response):**
"Should I use JWT or session-based authentication? JWT is simpler but sessions give better revocation control."

**Good (task complete):**
"Completed: Added user registration endpoint with email verification. Ready for testing."

**Good (error/blocked):**
"Build failing - missing STRIPE_KEY env var. Should I add it to .env.example?"

**Bad (don't send):**
"Running npm install..."
"Reading file src/index.ts..."
"Found 3 matches for the pattern..."

## Quick Reference

- **Channel ID:** `YOUR_CHANNEL_ID`
- **Create thread:** `discord_create_thread`
- **Watch thread:** `discord_watch_thread` (enables auto-inbox)
- **Send to thread:** `discord_send_thread_message`
- **Rename thread:** `discord_rename_thread` (for branch changes)
- **Get unread:** `discord_get_unread_messages` (from watched threads)
- **Read all:** `discord_read_thread_messages`
- **Clear inbox:** `discord_clear_inbox`
- **Stop watching:** `discord_unwatch_thread`

**Terminal commands (user runs these):**
- `droid-register <threadId>` - Register session for message injection
- `droid-status` - Show current session status
- `droid-discord start-bg` - Start bridge daemon in background

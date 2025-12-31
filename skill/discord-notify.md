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

The bridge prefixes Discord messages with `[Discord]` - when you see this, your response MUST go to the Discord thread.

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

### Starting a Session Thread

At the start of a session (or first time you need Discord), create and watch a thread:

```
// 1. Create the thread
discord_create_thread(
  channelId: "YOUR_CHANNEL_ID",
  name: "[project-name:branch] - YYYY-MM-DD HH:MM",
  message: "Session started. Working on: <brief description>"
)

// 2. Watch it for incoming messages (use the returned threadId)
discord_watch_thread(threadId: "<returned-thread-id>")
```

Store the returned `threadId` for all subsequent messages in this session.

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
- **Get unread:** `discord_get_unread_messages` (from watched threads)
- **Read all:** `discord_read_thread_messages`
- **Clear inbox:** `discord_clear_inbox`
- **Stop watching:** `discord_unwatch_thread`

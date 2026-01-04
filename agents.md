# Discord-Droid Bridge: Agent Guidelines

This document provides guidance for AI agents using the Discord-Droid Bridge skill.

## Overview

The Discord-Droid Bridge enables two-way communication between Discord and your terminal session. Messages sent in Discord threads are delivered directly to your terminal, and your responses are automatically sent back to Discord via hooks.

## Setting Up a Session

When a user asks to set up Discord for their session, use the `discord-notify` skill:

```
Use the discord-notify skill
```

The skill will guide you through:
1. Reading the Discord config (`~/.factory/discord-config.json`)
2. Creating a thread with `discord_create_thread()`
3. Watching the thread with `discord_watch_thread()`
4. Registering the session with `droid-discord register`
5. Starting the bridge daemon

## Communication Protocol

### Receiving Messages

Discord messages appear in your terminal prefixed with:
```
[Discord:<threadId>] <message content>
```

When you see this prefix, the message came from Discord and you should respond appropriately.

### Sending Messages

Use the MCP tool to send messages:
```
discord_send_thread_message(threadId: "<thread-id>", message: "Your message")
```

### Automatic Hooks

The bridge includes hooks that automatically:
- **SessionStart**: Starts a heartbeat daemon
- **UserPromptSubmit**: Sends "Got it!" acknowledgment, restarts heartbeat
- **Stop**: Sends your final response to Discord, stops heartbeat

## Status Updates on Long-Running Tasks

**IMPORTANT**: When working on tasks that take more than 2-3 tool calls, proactively send status updates to Discord.

### When to Send Updates

Send a Discord message when:
- Starting a multi-step task (explain what you're about to do)
- Completing significant milestones
- Encountering errors or blockers
- Making decisions that affect the approach
- Finishing the task

### Update Frequency Guidelines

| Task Duration | Update Frequency |
|---------------|------------------|
| < 5 tool calls | Update at start and end |
| 5-15 tool calls | Every 3-5 significant actions |
| 15+ tool calls | Every 2-3 minutes or major milestone |

### Example Status Updates

**Starting a task:**
```
discord_send_thread_message(threadId, "Starting code review - will check security, performance, and code quality across 5 parallel agents")
```

**Progress update:**
```
discord_send_thread_message(threadId, "Security review complete (no issues). Running performance analysis now...")
```

**Completion:**
```
discord_send_thread_message(threadId, "All reviews complete:\n- Security: PASSED\n- Performance: No regressions\n- Code quality: 2 minor suggestions\n\nReady to push when you give the go-ahead.")
```

### Heartbeat Messages

The heartbeat daemon automatically sends "still working" messages every 60 seconds during long operations. This is handled by the hooks, but you should still send meaningful status updates about what you're actually doing.

## Best Practices

### Do

- **Acknowledge requests promptly** - When you receive a Discord message, acknowledge it
- **Be concise** - Discord messages should be scannable
- **Use formatting** - Bold for emphasis, code blocks for commands/output
- **Report blockers immediately** - Don't wait if you need input
- **Summarize at completion** - Provide a clear summary of what was done

### Don't

- **Don't spam updates** - Every tool call doesn't need a message
- **Don't send partial thoughts** - Wait until you have something meaningful
- **Don't forget to respond** - Every Discord message deserves acknowledgment
- **Don't send sensitive data** - No secrets, tokens, or credentials in messages

## Message Formatting

### Good Format

```
**Status Update**

Completed:
- Fixed path traversal vulnerability
- Expanded test suite to 76 tests
- All tests passing

Next: Ready to push to remote
```

### Avoid

```
ok done with the thing, let me know if you need anything else i guess
```

## Responding to Commands

Common Discord commands you might receive:

| Command | Expected Action |
|---------|-----------------|
| "Status update" | Send current progress summary |
| "Push" | Push commits to remote, confirm |
| "Run tests" | Execute test suite, report results |
| "Stop" | Acknowledge and wrap up gracefully |
| "What's taking so long?" | Explain current work, estimate remaining |

## Error Handling

If something goes wrong:

1. **Acknowledge the error** - Don't silently fail
2. **Explain what happened** - Be specific
3. **Propose solutions** - Offer next steps
4. **Ask for guidance if needed** - Don't guess on important decisions

Example:
```
discord_send_thread_message(threadId, "⚠️ Test suite failed (3 failures in registry.bats)\n\nInvestigating root cause - will report back shortly.")
```

## Session Lifecycle

### Starting
```bash
# User invokes skill
Use the discord-notify skill
```

### During Session
- Messages flow automatically via bridge
- Hooks handle acknowledgments and responses
- You send proactive updates for long tasks

### Resuming
```bash
# If session was interrupted
droid-discord resume
discord_watch_thread(threadId: "<thread-id>")
```

### Ending
- Stop hook sends final response automatically
- Heartbeat daemon stops
- Session remains registered for potential resume

## Troubleshooting

### Messages not appearing in Discord
1. Check session registration: `droid-discord status`
2. Check bridge is running: `pgrep -f bridge-v2.sh`
3. Review logs: `droid-discord logs`

### Can't receive Discord messages
1. Ensure thread is being watched: `discord_watch_thread(threadId)`
2. Check inbox: `cat ~/.factory/discord-inbox.json`

### Session disconnected
```bash
droid-discord resume
```
Then re-watch the thread with `discord_watch_thread()`.

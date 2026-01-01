# Discord-Droid Bridge V2 Design

## Overview

V2 is **iTerm2-only**, leveraging iTerm's powerful AppleScript API for:
- Direct session write without focus stealing
- Reliable session targeting via TTY
- Shell integration for session tracking

This replaces the polling-based clipboard hack with an event-driven, no-focus-steal architecture.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Discord Thread │────▶│   mcp-discord    │────▶│ discord-inbox   │
│                 │     │   (MCP Server)   │     │    .json        │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼ fswatch
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Droid CLI     │◀────│   bridge-v2.sh   │◀────│  Session        │
│  (TTY direct)   │     │  (event-driven)  │     │  Registry       │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

## Components

### 1. Session Registry (`~/.factory/droid-sessions.json`)

Sessions self-register when starting Discord integration:

```json
{
  "sessions": {
    "<threadId>": {
      "threadId": "<threadId>",
      "threadName": "[project:branch] - 2025-12-31",
      "tty": "/dev/ttys003",
      "pid": 12345,
      "app": "iTerm",
      "registered": "2025-12-31T18:32:00Z",
      "lastActivity": "2025-12-31T18:45:00Z"
    }
  },
  "version": 2
}
```

### 2. Session Registration Script (`droid-register`)

Called by Droid skill when setting up Discord:

```bash
droid-register <threadId> [threadName]
# - Detects current TTY via `tty` command
# - Detects PID via $$
# - Detects app via $TERM_PROGRAM
# - Writes to session registry
# - Sets up cleanup trap for deregistration
```

### 3. Bridge Daemon (`bridge-v2.sh`)

Event-driven message router:

```bash
# Uses fswatch instead of polling
fswatch -o ~/.factory/discord-inbox.json | while read; do
  process_new_messages
done
```

**Message Processing:**
1. Read new messages from inbox
2. Look up session in registry by threadId
3. Validate session still exists (check PID)
4. Write directly to TTY or queue if unavailable
5. Mark message as processed

### 4. iTerm2 Direct Session Write

Use iTerm's AppleScript API for no-focus-steal injection:

```bash
inject_message() {
  local tty="$1"
  local message="$2"
  
  osascript <<EOF
tell application "iTerm"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s is "$tty" then
                    tell s to write text "$message"
                    return "sent"
                end if
            end repeat
        end repeat
    end repeat
end tell
return "not_found"
EOF
}
```

**Key benefits:**
- `write text` auto-submits (includes Enter)
- No `activate` = no focus steal
- Target by TTY (reliable) not session name (unreliable)

**Fallback:**
1. iTerm direct write (primary)
2. Queue for later if session not found

### 5. Message Queue (`~/.factory/discord-queue.json`)

For undeliverable messages:

```json
{
  "queued": [
    {
      "id": "msg123",
      "threadId": "<threadId>",
      "content": "message text",
      "queuedAt": "2025-12-31T18:50:00Z",
      "attempts": 1,
      "nextRetry": "2025-12-31T18:51:00Z",
      "reason": "session_not_found"
    }
  ]
}
```

**Retry Strategy:**
- Exponential backoff: 1s, 2s, 4s, 8s, max 60s
- Max 10 attempts
- Dead letter after max attempts (logged, not lost)

### 6. Shell Helpers (iTerm2 Only)

```bash
# Register session with Discord thread
# Call this AFTER creating/watching a thread in Droid
droid-register() {
  local thread_id="$1"
  local thread_name="${2:-}"
  local current_tty=$(tty)
  local pid=$$
  local registry="$HOME/.factory/droid-sessions.json"
  
  # Ensure registry exists
  [[ -f "$registry" ]] || echo '{"sessions":{},"version":2}' > "$registry"
  
  # Get project/branch info
  local project=$(basename "$(pwd)")
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "none")
  
  # Update registry with TTY (key for injection)
  jq --arg tid "$thread_id" \
     --arg tty "$current_tty" \
     --arg pid "$pid" \
     --arg name "$thread_name" \
     --arg project "$project" \
     --arg branch "$branch" \
     --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.sessions[$tid] = {
       threadId: $tid,
       threadName: $name,
       tty: $tty,
       pid: ($pid | tonumber),
       project: $project,
       branch: $branch,
       registered: $now,
       lastActivity: $now
     }' "$registry" > /tmp/sessions.$$.json \
     && mv /tmp/sessions.$$.json "$registry"
  
  # Store thread ID for branch change detection
  export DROID_THREAD_ID="$thread_id"
  
  # Set up deregistration on exit
  trap "droid-deregister $thread_id 2>/dev/null" EXIT
  
  echo "✓ Registered: thread=$thread_id tty=$current_tty"
}

# Deregister session (called automatically on exit)
droid-deregister() {
  local thread_id="$1"
  local registry="$HOME/.factory/droid-sessions.json"
  [[ -f "$registry" ]] && \
    jq --arg tid "$thread_id" 'del(.sessions[$tid])' "$registry" > /tmp/sessions.$$.json \
    && mv /tmp/sessions.$$.json "$registry"
}

# Check current registration
droid-status() {
  local registry="$HOME/.factory/droid-sessions.json"
  if [[ -n "$DROID_THREAD_ID" ]]; then
    echo "Thread: $DROID_THREAD_ID"
    jq --arg tid "$DROID_THREAD_ID" '.sessions[$tid]' "$registry"
  else
    echo "Not registered. Run: droid-register <threadId>"
  fi
}
```

## File Structure

```
~/.factory/
├── discord-inbox.json        # Incoming messages (from mcp-discord)
├── discord-inbox-processed.txt  # Processed message IDs
├── droid-sessions.json       # Session registry
├── discord-queue.json        # Undelivered message queue
└── bridge.log               # Bridge daemon logs

discord-droid-bridge/
├── bridge-v2.sh             # Main daemon (fswatch-based)
├── lib/
│   ├── registry.sh          # Session registry functions
│   ├── inject.sh            # TTY injection functions
│   └── queue.sh             # Message queue functions
├── bin/
│   ├── droid-register       # Session registration
│   └── droid-deregister     # Session deregistration
└── docs/
    └── V2-DESIGN.md         # This document
```

## Benefits Over V1

| Aspect | V1 | V2 |
|--------|----|----|
| Terminal support | Terminal.app + iTerm2 | **iTerm2 only** |
| Detection | Poll every 5s | Instant (fswatch) |
| Session lookup | Scan window names | Direct TTY lookup |
| Message injection | AppleScript + clipboard | iTerm `write text` |
| Focus stealing | Yes (brings window front) | **No** |
| Multi-session | Fragile (window title grep) | Robust (TTY + PID) |
| Reliability | Messages can be lost | Queue with retry |
| CPU usage | Constant polling | Event-driven |

## Migration Path

1. V2 bridge runs alongside V1 during testing
2. V2 uses same inbox file format (compatible with mcp-discord)
3. Shell helpers updated to use registration
4. V1 deprecated once V2 stable

## Dependencies

- `fswatch` - `brew install fswatch`
- `jq` - `brew install jq` (already required)

### 7. Auto-Rename Thread on Branch Change

Monitor git branch and update Discord thread name automatically:

```bash
# Hook into cd/git commands to detect branch changes
droid-branch-hook() {
  local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local session_file="$HOME/.factory/droid-sessions.json"
  
  # Get stored branch for this session
  local stored_branch=$(jq -r --arg tid "$DROID_THREAD_ID" \
    '.sessions[$tid].branch // ""' "$session_file")
  
  if [[ -n "$current_branch" && "$current_branch" != "$stored_branch" ]]; then
    # Update registry
    jq --arg tid "$DROID_THREAD_ID" \
       --arg branch "$current_branch" \
       '.sessions[$tid].branch = $branch' "$session_file" > /tmp/sess.$$.json \
       && mv /tmp/sess.$$.json "$session_file"
    
    # Rename Discord thread
    local new_name="[$(basename $(pwd)):$current_branch] - $(date '+%Y-%m-%d')"
    # Call mcp-discord to rename (need to add this tool)
    discord_rename_thread "$DROID_THREAD_ID" "$new_name"
  fi
}

# Add to chpwd hook (zsh) or PROMPT_COMMAND (bash)
autoload -Uz add-zsh-hook
add-zsh-hook chpwd droid-branch-hook
```

**Implementation Options:**

1. **chpwd hook** - Fires on every directory change, checks git branch
2. **post-checkout hook** - Git hook, only fires on branch switch
3. **Polling** - Check branch every N seconds (not preferred)

**Thread naming format:**
```
[project:branch] - YYYY-MM-DD HH:MM
```

Updates to:
```
[project:new-branch] - YYYY-MM-DD HH:MM
```

**Required mcp-discord addition:**
```typescript
// New tool: discord_rename_thread
discord_rename_thread(threadId: string, newName: string)
```

## Open Questions

1. Should we add a health check endpoint?
2. WebSocket option for even lower latency?
3. Should mcp-discord write directly to TTY (skip bridge entirely)?
4. Should thread rename include timestamp update or preserve original?

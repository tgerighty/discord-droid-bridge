#!/bin/bash
# Discord-Droid Bridge Session Hook
# Automatically creates Discord thread and registers session on start
# Deregisters and optionally closes thread on end
#
# INSTALLATION:
# 1. Copy this file to ~/.factory/hooks/discord-session.sh
# 2. Make executable: chmod +x ~/.factory/hooks/discord-session.sh
# 3. Update DISCORD_CHANNEL_ID below with your channel ID
# 4. Add to ~/.factory/settings.json:
#    "hooks": {
#      "SessionStart": [{"hooks": [{"type": "command", "command": "/path/to/home/.factory/hooks/discord-session.sh"}]}],
#      "SessionEnd": [{"hooks": [{"type": "command", "command": "/path/to/home/.factory/hooks/discord-session.sh"}]}]
#    }

SESSIONS_FILE="$HOME/.factory/droid-sessions.json"
CURRENT_SESSION_FILE="$HOME/.factory/current-discord-session"

# TODO: Set your Discord channel ID here
DISCORD_CHANNEL_ID="YOUR_CHANNEL_ID_HERE"

# Read hook input from stdin
input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

case "$event" in
    SessionStart)
        # Get project name and branch from cwd
        project_name=$(basename "$cwd" 2>/dev/null || echo "unknown")
        branch=$(cd "$cwd" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        thread_name="[$project_name:$branch] - $(date '+%Y-%m-%d %H:%M')"
        
        # Build the context message (escape for JSON)
        context="## Discord Session Setup Required\\n\\n"
        context+="Create a Discord thread for this session by running these MCP tools IN ORDER:\\n\\n"
        context+="1. Create the thread:\\n"
        context+="   discord_create_thread(channelId: \\\"$DISCORD_CHANNEL_ID\\\", name: \\\"$thread_name\\\", message: \\\"Session started\\\")\\n\\n"
        context+="2. Watch the thread (use the threadId returned above):\\n"
        context+="   discord_watch_thread(threadId: \\\"<threadId from step 1>\\\")\\n\\n"
        context+="3. Register the session (replace THREAD_ID with actual value):\\n"
        context+="   droid-discord register THREAD_ID \\\"$thread_name\\\" && droid-discord start-bg 2>/dev/null\\n\\n"
        context+="Store the threadId for sending messages back to Discord throughout this session."
        
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$context\"}}"
        ;;
        
    SessionEnd)
        # Read current session thread ID if stored
        if [[ -f "$CURRENT_SESSION_FILE" ]]; then
            thread_id=$(cat "$CURRENT_SESSION_FILE")
            if [[ -n "$thread_id" && -f "$SESSIONS_FILE" ]]; then
                # Deregister
                tmp=$(mktemp)
                jq --arg tid "$thread_id" 'del(.sessions[$tid])' "$SESSIONS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SESSIONS_FILE"
            fi
            rm -f "$CURRENT_SESSION_FILE"
        fi
        ;;
esac

exit 0

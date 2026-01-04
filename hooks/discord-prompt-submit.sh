#!/bin/bash
# Discord-Droid Bridge - UserPromptSubmit hook
# Restarts the heartbeat when user submits a new prompt (Droid about to work)
# Also sends an acknowledgment to Discord

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared config for get_current_thread_id
source "$SCRIPT_DIR/../lib/config.sh" 2>/dev/null || true

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty')

# Get and validate thread ID using shared function
thread_id=$(get_current_thread_id 2>/dev/null) || exit 0

# Check if this prompt came from Discord (prefixed with [Discord:threadId])
# If so, send an acknowledgment
if [[ "$prompt" == "[Discord:"* ]]; then
    # Send acknowledgment
    droid-discord send "$thread_id" "Got it! Working on your request..." >/dev/null 2>&1 || true
fi

# Start/restart the heartbeat daemon
"$SCRIPT_DIR/discord-heartbeat.sh" start "$thread_id" >/dev/null 2>&1 || true

exit 0

#!/bin/bash
# Discord-Droid Bridge - UserPromptSubmit hook
# Restarts the heartbeat when user submits a new prompt (Droid about to work)
# Also sends an acknowledgment to Discord

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty')

# Get the current Discord thread (if any)
thread_id=""
if [[ -f "$HOME/.factory/current-discord-session" ]]; then
    thread_id=$(cat "$HOME/.factory/current-discord-session")
fi

# No active Discord session, nothing to do
[[ -z "$thread_id" ]] && exit 0

# Validate thread ID
[[ ! "$thread_id" =~ ^[0-9]{17,20}$ ]] && exit 0

# Check if this prompt came from Discord (prefixed with [Discord:threadId])
# If so, send an acknowledgment
if [[ "$prompt" == "[Discord:"* ]]; then
    # Send acknowledgment
    droid-discord send "$thread_id" "Got it! Working on your request..." >/dev/null 2>&1 || true
fi

# Start/restart the heartbeat daemon
"$SCRIPT_DIR/discord-heartbeat.sh" start "$thread_id" >/dev/null 2>&1 || true

exit 0

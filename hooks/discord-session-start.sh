#!/bin/bash
# Discord-Droid Bridge - SessionStart hook
# Starts heartbeat daemon when a session begins with an active Discord thread

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
input=$(cat)

# Get the current Discord thread (if any)
thread_id=""
if [[ -f "$HOME/.factory/current-discord-session" ]]; then
    thread_id=$(cat "$HOME/.factory/current-discord-session")
fi

# No active Discord session, nothing to do
[[ -z "$thread_id" ]] && exit 0

# Validate thread ID
[[ ! "$thread_id" =~ ^[0-9]{17,20}$ ]] && exit 0

# Start the heartbeat daemon
"$SCRIPT_DIR/discord-heartbeat.sh" start "$thread_id" >/dev/null 2>&1 || true

# Output context for Droid (shown via additionalContext)
# This reminds Droid about the Discord connection
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Discord session active: Thread $thread_id. Heartbeat started for periodic feedback."
  }
}
EOF

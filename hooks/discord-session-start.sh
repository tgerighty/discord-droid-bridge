#!/bin/bash
# Discord-Droid Bridge - SessionStart hook
# Starts heartbeat daemon when a session begins with an active Discord thread

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared config for get_current_thread_id
source "$SCRIPT_DIR/../lib/config.sh" 2>/dev/null || true

# Read hook input from stdin
input=$(cat)

# Get and validate thread ID using shared function
thread_id=$(get_current_thread_id 2>/dev/null) || exit 0

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

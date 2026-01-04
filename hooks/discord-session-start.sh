#!/bin/bash
# Discord-Droid Bridge - SessionStart hook
# Auto-reconnects to previous Discord thread and starts heartbeat daemon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source shared libraries
source "$BRIDGE_DIR/lib/config.sh" 2>/dev/null || true
source "$BRIDGE_DIR/lib/registry.sh" 2>/dev/null || true

# Read hook input from stdin (required by Factory hooks)
input=$(cat)

# Get thread ID from session file
thread_id=$(get_current_thread_id 2>/dev/null) || exit 0

# Safe auto-reconnect: only if DROID_TTY is set (proves we're in a real Droid session)
if [[ -n "${DROID_TTY:-}" ]]; then
    # Ensure bridge is running
    if ! pgrep -f "bridge-v2.sh" > /dev/null 2>&1; then
        nohup "$BRIDGE_DIR/bridge-v2.sh" >> "$LOG_FILE" 2>&1 &
    fi
    
    # Re-register session with current TTY (safe: uses DROID_TTY, not bridge's TTY)
    register_session "$thread_id" "" "$DROID_TTY" "${DROID_SESSION_PID:-$PPID}" >/dev/null 2>&1 || true
fi

# Start the heartbeat daemon
"$SCRIPT_DIR/discord-heartbeat.sh" start "$thread_id" >/dev/null 2>&1 || true

# Output context for Droid (shown via additionalContext)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Discord session active: Thread $thread_id. Auto-reconnected and heartbeat started."
  }
}
EOF

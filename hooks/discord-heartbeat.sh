#!/bin/bash
# Discord-Droid Bridge - Heartbeat daemon for ongoing feedback
# Spawned by SessionStart hook, killed by Stop/SessionEnd hooks
# Sends periodic "still working" messages to Discord thread

set -euo pipefail

HEARTBEAT_INTERVAL="${DISCORD_HEARTBEAT_INTERVAL:-60}"  # seconds between messages
HEARTBEAT_PID_FILE="$HOME/.factory/discord-heartbeat.pid"
HEARTBEAT_STATE_FILE="$HOME/.factory/discord-heartbeat-state.json"

# Witty messages to send (randomly selected)
MESSAGES=(
    "Still crunching through your request..."
    "Working on it - haven't forgotten about you!"
    "Still here, still coding..."
    "Heads down, making progress..."
    "Processing... this is a meaty one!"
    "Still at it - good things take time!"
    "Churning through the code..."
    "Making headway on your request..."
    "Still working - coffee break denied!"
    "In the zone, be back soon..."
)

get_random_message() {
    local count=${#MESSAGES[@]}
    local index=$((RANDOM % count))
    echo "${MESSAGES[$index]}"
}

start_heartbeat() {
    local thread_id="$1"
    
    # Kill any existing heartbeat
    stop_heartbeat 2>/dev/null || true
    
    # Validate thread ID
    [[ ! "$thread_id" =~ ^[0-9]{17,20}$ ]] && return 1
    
    # Save state
    mkdir -p "$HOME/.factory"
    echo "{\"thread_id\": \"$thread_id\", \"started\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$HEARTBEAT_STATE_FILE"
    
    # Start background heartbeat loop
    (
        local msg_count=0
        while true; do
            sleep "$HEARTBEAT_INTERVAL"
            
            # Check if we should still be running
            [[ ! -f "$HEARTBEAT_PID_FILE" ]] && exit 0
            
            # Get a witty message
            local message
            message=$(get_random_message)
            
            # Add elapsed time context
            ((msg_count++))
            local elapsed=$((msg_count * HEARTBEAT_INTERVAL / 60))
            if [[ $elapsed -gt 0 ]]; then
                message="$message (~${elapsed}m elapsed)"
            fi
            
            # Send to Discord
            droid-discord send "$thread_id" "$message" >/dev/null 2>&1 || true
        done
    ) &
    
    local pid=$!
    echo "$pid" > "$HEARTBEAT_PID_FILE"
    echo "Heartbeat started (PID: $pid, interval: ${HEARTBEAT_INTERVAL}s)"
}

stop_heartbeat() {
    if [[ -f "$HEARTBEAT_PID_FILE" ]]; then
        local pid
        pid=$(cat "$HEARTBEAT_PID_FILE")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "Heartbeat stopped (PID: $pid)"
        fi
        rm -f "$HEARTBEAT_PID_FILE"
    fi
    rm -f "$HEARTBEAT_STATE_FILE"
}

status_heartbeat() {
    if [[ -f "$HEARTBEAT_PID_FILE" ]]; then
        local pid
        pid=$(cat "$HEARTBEAT_PID_FILE")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Heartbeat running (PID: $pid)"
            [[ -f "$HEARTBEAT_STATE_FILE" ]] && cat "$HEARTBEAT_STATE_FILE"
            return 0
        fi
    fi
    echo "Heartbeat not running"
    return 1
}

case "${1:-}" in
    start)
        shift
        start_heartbeat "$@"
        ;;
    stop)
        stop_heartbeat
        ;;
    status)
        status_heartbeat
        ;;
    *)
        echo "Usage: discord-heartbeat.sh {start <threadId>|stop|status}"
        exit 1
        ;;
esac

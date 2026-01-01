#!/bin/bash
# Discord-Droid Bridge V2 - Session Registry
# Manages session registration with TTY tracking

# Validate thread ID format (Discord snowflake: 17-19 digits)
validate_thread_id() {
    local tid="$1"
    [[ "$tid" =~ ^[0-9]{17,20}$ ]]
}

# Secure temp file creation
secure_temp() {
    mktemp "${TMPDIR:-/tmp}/droid-bridge.XXXXXX"
}

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$SESSIONS_FILE" ]]; then
        echo '{"sessions":{},"version":2}' > "$SESSIONS_FILE"
        chmod 600 "$SESSIONS_FILE"
    fi
}

# Register a session with the current TTY (with file locking)
# Usage: register_session <threadId> [threadName]
register_session() {
    local thread_id="$1"
    local thread_name="${2:-}"
    local current_tty=$(tty 2>/dev/null || echo "unknown")
    local pid=$$
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Validate thread ID
    if ! validate_thread_id "$thread_id"; then
        echo "Error: Invalid thread ID format"
        return 1
    fi
    
    init_registry
    
    # Use file locking for safe concurrent access
    with_lock "$SESSIONS_FILE" "
        local tmp=\$(secure_temp)
        jq --arg tid '$thread_id' \
           --arg tty '$current_tty' \
           --argjson pid $pid \
           --arg name '$thread_name' \
           --arg now '$now' \
           '.sessions[\$tid] = {tty: \$tty, pid: \$pid, name: \$name, registered: \$now}' \
           '$SESSIONS_FILE' > \"\$tmp\" && mv \"\$tmp\" '$SESSIONS_FILE'
    "
    
    echo "✓ Registered: thread=$thread_id tty=$current_tty pid=$pid"
}

# Deregister a session (with file locking)
# Usage: deregister_session <threadId>
deregister_session() {
    local thread_id="$1"
    
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    with_lock "$SESSIONS_FILE" "
        local tmp=\$(secure_temp)
        jq --arg tid '$thread_id' 'del(.sessions[\$tid])' '$SESSIONS_FILE' > \"\$tmp\" && mv \"\$tmp\" '$SESSIONS_FILE'
    "
    
    echo "✓ Deregistered: thread=$thread_id"
}

# Get session by threadId
# Usage: get_session <threadId>
# Returns: JSON object or "null"
get_session() {
    local thread_id="$1"
    
    [[ ! -f "$SESSIONS_FILE" ]] && echo "null" && return 1
    
    jq -r --arg tid "$thread_id" '.sessions[$tid] // null' "$SESSIONS_FILE"
}

# Clean up sessions with dead PIDs (batch operation)
# Usage: cleanup_dead_sessions
cleanup_dead_sessions() {
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    local removed=0
    local sessions_data=$(cat "$SESSIONS_FILE")
    local modified=false
    
    for tid in $(echo "$sessions_data" | jq -r '.sessions | keys[]' 2>/dev/null); do
        local pid=$(echo "$sessions_data" | jq -r --arg tid "$tid" '.sessions[$tid].pid')
        
        if [[ -n "$pid" && "$pid" != "null" ]]; then
            if ! kill -0 "$pid" 2>/dev/null; then
                sessions_data=$(echo "$sessions_data" | jq --arg tid "$tid" 'del(.sessions[$tid])')
                ((removed++))
                modified=true
            fi
        fi
    done
    
    # Single write for all deletions
    if [[ "$modified" == "true" ]]; then
        local tmp=$(secure_temp)
        echo "$sessions_data" > "$tmp" && mv "$tmp" "$SESSIONS_FILE"
        echo "Cleaned up $removed dead session(s)"
    fi
}

# List all sessions
# Usage: list_sessions
list_sessions() {
    [[ ! -f "$SESSIONS_FILE" ]] && echo "No sessions registered" && return 0
    
    echo "Registered sessions:"
    jq -r '.sessions | to_entries[] | "  \(.key): tty=\(.value.tty) pid=\(.value.pid)"' "$SESSIONS_FILE"
}

# Show current session status
# Usage: show_session_status
show_session_status() {
    if [[ -n "$DROID_THREAD_ID" ]]; then
        echo "Current thread: $DROID_THREAD_ID"
        local session=$(get_session "$DROID_THREAD_ID")
        if [[ "$session" != "null" ]]; then
            echo "$session" | jq .
        else
            echo "Session not found in registry"
        fi
    else
        echo "No active Discord session (DROID_THREAD_ID not set)"
        echo ""
        list_sessions
    fi
}

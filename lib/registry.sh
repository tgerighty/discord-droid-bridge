#!/bin/bash
# Discord-Droid Bridge V2 - Session Registry
# Manages session registration with TTY tracking

set -euo pipefail

# Validate thread ID format (Discord snowflake: 17-20 digits)
validate_thread_id() {
    local tid="$1"
    [[ "$tid" =~ ^[0-9]{17,20}$ ]]
}

# Validate TTY format (expect /dev/ttysNNN)
validate_tty() {
    local tty="$1"
    [[ "$tty" =~ ^/dev/ttys[0-9]+$ ]]
}

# Check if a TTY has active processes
tty_has_processes() {
    local tty="$1"
    local short="${tty#/dev/}"
    ps -t "$short" 2>/dev/null | awk 'NR>1{found=1; exit} END{exit (found ? 0 : 1)}'
}

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$SESSIONS_FILE" ]]; then
        echo '{"sessions":{}}' > "$SESSIONS_FILE"
        chmod 600 "$SESSIONS_FILE"
    fi
}

# Register a session (unified function)
# Usage: register_session <threadId> [threadName] [tty] [pid]
# If tty not provided, uses current tty or DROID_TTY
# If pid not provided, uses DROID_SESSION_PID or PPID
register_session() {
    local thread_id="$1"
    local thread_name="${2:-}"
    local provided_tty="${3:-}"
    local pid="${4:-${DROID_SESSION_PID:-$PPID}}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    ensure_factory_dir

    if ! validate_thread_id "$thread_id"; then
        echo "Error: Invalid thread ID format" >&2
        return 1
    fi

    # Determine TTY
    local current_tty="$provided_tty"
    if [[ -z "$current_tty" ]]; then
        current_tty=$(tty 2>/dev/null || echo "")
        if ! validate_tty "$current_tty"; then
            current_tty="${DROID_TTY:-}"
        fi
    fi

    if ! validate_tty "$current_tty"; then
        echo "Error: Invalid TTY format: $current_tty" >&2
        echo "Hint: export DROID_TTY=\$(tty 2>/dev/null || echo \"\")" >&2
        return 1
    fi

    init_registry

    # Use file locking for atomic update
    local lockfile="$SESSIONS_FILE.lock"
    local tmp
    tmp=$(secure_temp)
    
    (
        acquire_lock "$lockfile" 200
        
        # Handle null/empty pid
        if [[ -z "$pid" || "$pid" == "null" ]]; then
            jq --arg tid "$thread_id" \
               --arg tty "$current_tty" \
               --arg name "$thread_name" \
               --arg now "$now" \
               '.sessions[$tid] = {tty: $tty, pid: null, name: $name, registered: $now}' \
               "$SESSIONS_FILE" > "$tmp"
        else
            jq --arg tid "$thread_id" \
               --arg tty "$current_tty" \
               --argjson pid "$pid" \
               --arg name "$thread_name" \
               --arg now "$now" \
               '.sessions[$tid] = {tty: $tty, pid: $pid, name: $name, registered: $now}' \
               "$SESSIONS_FILE" > "$tmp"
        fi
        
        # Validate JSON before moving
        if jq empty "$tmp" 2>/dev/null; then
            mv "$tmp" "$SESSIONS_FILE"
        else
            rm -f "$tmp"
            echo "Error: JSON validation failed" >&2
            return 1
        fi
        
        release_lock 200
    )

    echo "✓ Registered: thread=$thread_id tty=$current_tty pid=$pid"
}

# Alias for backward compatibility with bridge auto-registration
register_session_with_tty() {
    local thread_id="$1"
    local thread_name="${2:-}"
    local provided_tty="$3"
    local pid="${4:-}"
    register_session "$thread_id" "$thread_name" "$provided_tty" "$pid"
}

# Deregister a session
# Usage: deregister_session <threadId>
deregister_session() {
    local thread_id="$1"
    
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    local lockfile="$SESSIONS_FILE.lock"
    local tmp
    tmp=$(secure_temp)
    
    (
        acquire_lock "$lockfile" 200
        jq --arg tid "$thread_id" 'del(.sessions[$tid])' "$SESSIONS_FILE" > "$tmp"
        if jq empty "$tmp" 2>/dev/null; then
            mv "$tmp" "$SESSIONS_FILE"
        else
            rm -f "$tmp"
        fi
        release_lock 200
    )
    
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
    
    local lockfile="$SESSIONS_FILE.lock"
    local removed=0
    local sessions_data
    local modified=false
    
    (
        acquire_lock "$lockfile" 200
        
        sessions_data=$(cat "$SESSIONS_FILE")
        
        for tid in $(echo "$sessions_data" | jq -r '.sessions | keys[]' 2>/dev/null); do
            local pid
            pid=$(echo "$sessions_data" | jq -r --arg tid "$tid" '.sessions[$tid].pid')
            
            # Validate PID is numeric before kill check
            if [[ -n "$pid" && "$pid" != "null" && "$pid" =~ ^[0-9]+$ ]]; then
                if ! kill -0 "$pid" 2>/dev/null; then
                    sessions_data=$(echo "$sessions_data" | jq --arg tid "$tid" 'del(.sessions[$tid])')
                    ((removed++)) || true
                    modified=true
                fi
            fi
        done
        
        # Single write for all deletions
        if [[ "$modified" == "true" ]]; then
            local tmp
            tmp=$(secure_temp)
            echo "$sessions_data" > "$tmp"
            if jq empty "$tmp" 2>/dev/null; then
                mv "$tmp" "$SESSIONS_FILE"
                echo "Cleaned up $removed dead session(s)"
            else
                rm -f "$tmp"
            fi
        fi
        
        release_lock 200
    )
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

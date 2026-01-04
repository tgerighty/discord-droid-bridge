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

# Get process start time (for PID reuse detection)
# Returns empty string if process doesn't exist
get_pid_start_time() {
    local pid="$1"
    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 1
    ps -p "$pid" -o lstart= 2>/dev/null | tr -d '\n'
}

# Check if PID is the same process (by start time)
is_same_process() {
    local pid="$1"
    local stored_start_time="$2"
    
    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return 1
    [[ -z "$stored_start_time" || "$stored_start_time" == "null" ]] && return 1
    
    local current_start
    current_start=$(get_pid_start_time "$pid")
    [[ -z "$current_start" ]] && return 1
    
    [[ "$current_start" == "$stored_start_time" ]]
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

    # Get PID start time for reuse detection
    local pid_start=""
    if [[ -n "$pid" && "$pid" != "null" && "$pid" =~ ^[0-9]+$ ]]; then
        pid_start=$(get_pid_start_time "$pid" 2>/dev/null || echo "")
    fi

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
               '.sessions[$tid] = {tty: $tty, pid: null, pidStart: null, name: $name, registered: $now}' \
               "$SESSIONS_FILE" > "$tmp"
        else
            jq --arg tid "$thread_id" \
               --arg tty "$current_tty" \
               --argjson pid "$pid" \
               --arg pidStart "$pid_start" \
               --arg name "$thread_name" \
               --arg now "$now" \
               '.sessions[$tid] = {tty: $tty, pid: $pid, pidStart: $pidStart, name: $name, registered: $now}' \
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
# Optimized: single jq call to get all tid:pid pairs, batch deletion
# Usage: cleanup_dead_sessions
cleanup_dead_sessions() {
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    local lockfile="$SESSIONS_FILE.lock"
    local removed=0
    local sessions_data
    local dead_tids=""
    
    (
        acquire_lock "$lockfile" 200
        
        sessions_data=$(cat "$SESSIONS_FILE")
        
        # Single jq call to extract all tid:pid pairs
        while IFS=$'\t' read -r tid pid; do
            [[ -z "$tid" ]] && continue
            
            # Validate PID is numeric before kill check
            if [[ -n "$pid" && "$pid" != "null" && "$pid" =~ ^[0-9]+$ ]]; then
                if ! kill -0 "$pid" 2>/dev/null; then
                    # Collect dead thread IDs
                    dead_tids="$dead_tids $tid"
                    ((removed++)) || true
                fi
            fi
        done < <(echo "$sessions_data" | jq -r '.sessions | to_entries[] | [.key, .value.pid] | @tsv' 2>/dev/null)
        
        # Single jq call to remove all dead sessions
        if [[ $removed -gt 0 ]]; then
            local tmp
            tmp=$(secure_temp)
            
            # Build jq filter to delete all dead sessions at once
            local filter=".sessions"
            for tid in $dead_tids; do
                filter="$filter | del(.[\"$tid\"])"
            done
            
            echo "$sessions_data" | jq ".sessions = ($filter)" > "$tmp"
            
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

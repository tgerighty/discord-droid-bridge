#!/bin/bash
# Discord-Droid Bridge V2 - Session Registry
# Manages session registration with TTY tracking

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$SESSIONS_FILE" ]]; then
        echo '{"sessions":{},"version":2}' > "$SESSIONS_FILE"
    fi
}

# Register a session with the current TTY
# Usage: register_session <threadId> [threadName]
register_session() {
    local thread_id="$1"
    local thread_name="${2:-}"
    local current_tty=$(tty 2>/dev/null || echo "unknown")
    local pid=$$
    local project=$(basename "$(pwd)")
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "none")
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    init_registry
    
    # Update registry with session info
    jq --arg tid "$thread_id" \
       --arg tty "$current_tty" \
       --arg pid "$pid" \
       --arg name "$thread_name" \
       --arg project "$project" \
       --arg branch "$branch" \
       --arg now "$now" \
       '.sessions[$tid] = {
         threadId: $tid,
         threadName: $name,
         tty: $tty,
         pid: ($pid | tonumber),
         project: $project,
         branch: $branch,
         registered: $now,
         lastActivity: $now
       }' "$SESSIONS_FILE" > "/tmp/sessions.$$.json" \
       && mv "/tmp/sessions.$$.json" "$SESSIONS_FILE"
    
    echo "✓ Registered: thread=$thread_id tty=$current_tty pid=$pid"
}

# Deregister a session
# Usage: deregister_session <threadId>
deregister_session() {
    local thread_id="$1"
    
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    jq --arg tid "$thread_id" 'del(.sessions[$tid])' "$SESSIONS_FILE" > "/tmp/sessions.$$.json" \
       && mv "/tmp/sessions.$$.json" "$SESSIONS_FILE"
    
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

# Get session by TTY
# Usage: get_session_by_tty <tty>
# Returns: JSON object or "null"
get_session_by_tty() {
    local tty="$1"
    
    [[ ! -f "$SESSIONS_FILE" ]] && echo "null" && return 1
    
    jq -r --arg tty "$tty" '[.sessions[] | select(.tty == $tty)] | first // null' "$SESSIONS_FILE"
}

# Update session branch info
# Usage: update_session_branch <threadId> <branch>
update_session_branch() {
    local thread_id="$1"
    local branch="$2"
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    [[ ! -f "$SESSIONS_FILE" ]] && return 1
    
    jq --arg tid "$thread_id" \
       --arg branch "$branch" \
       --arg now "$now" \
       '.sessions[$tid].branch = $branch | .sessions[$tid].lastActivity = $now' \
       "$SESSIONS_FILE" > "/tmp/sessions.$$.json" \
       && mv "/tmp/sessions.$$.json" "$SESSIONS_FILE"
}

# Update last activity timestamp
# Usage: update_session_activity <threadId>
update_session_activity() {
    local thread_id="$1"
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    [[ ! -f "$SESSIONS_FILE" ]] && return 1
    
    jq --arg tid "$thread_id" \
       --arg now "$now" \
       '.sessions[$tid].lastActivity = $now' \
       "$SESSIONS_FILE" > "/tmp/sessions.$$.json" \
       && mv "/tmp/sessions.$$.json" "$SESSIONS_FILE"
}

# Clean up sessions with dead PIDs
# Usage: cleanup_dead_sessions
cleanup_dead_sessions() {
    [[ ! -f "$SESSIONS_FILE" ]] && return 0
    
    local removed=0
    local sessions=$(jq -r '.sessions | keys[]' "$SESSIONS_FILE" 2>/dev/null)
    
    for tid in $sessions; do
        local pid=$(jq -r --arg tid "$tid" '.sessions[$tid].pid' "$SESSIONS_FILE")
        
        if [[ -n "$pid" && "$pid" != "null" ]]; then
            if ! kill -0 "$pid" 2>/dev/null; then
                jq --arg tid "$tid" 'del(.sessions[$tid])' "$SESSIONS_FILE" > "/tmp/sessions.$$.json" \
                   && mv "/tmp/sessions.$$.json" "$SESSIONS_FILE"
                ((removed++))
            fi
        fi
    done
    
    [[ $removed -gt 0 ]] && echo "Cleaned up $removed dead session(s)"
}

# List all sessions
# Usage: list_sessions
list_sessions() {
    [[ ! -f "$SESSIONS_FILE" ]] && echo "No sessions registered" && return 0
    
    echo "Registered sessions:"
    jq -r '.sessions | to_entries[] | "  \(.key): tty=\(.value.tty) pid=\(.value.pid) project=\(.value.project) branch=\(.value.branch)"' "$SESSIONS_FILE"
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

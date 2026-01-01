#!/bin/bash
#
# Discord-Droid Bridge V2
# Event-driven, iTerm2-only message injection
# Uses fswatch for instant detection, direct TTY write for no focus steal
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/inject.sh"
source "$SCRIPT_DIR/lib/queue.sh"

# Check dependencies
check_dependencies() {
    if ! command -v fswatch &> /dev/null; then
        error "fswatch is required but not installed. Run: brew install fswatch"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed. Run: brew install jq"
        exit 1
    fi
    
    if ! is_iterm_running; then
        warn "iTerm2 is not running. Bridge will wait for sessions."
    fi
}

# Process new messages from inbox
process_inbox() {
    [[ ! -f "$INBOX_FILE" ]] && return
    
    local unread=$(jq -r '.unreadCount // 0' "$INBOX_FILE" 2>/dev/null)
    [[ "$unread" -eq 0 || "$unread" == "null" ]] && return
    
    jq -c '.messages[]?' "$INBOX_FILE" 2>/dev/null | while read -r msg; do
        [[ -z "$msg" ]] && continue
        
        local msg_id=$(echo "$msg" | jq -r '.id')
        local thread_id=$(echo "$msg" | jq -r '.threadId')
        local content=$(echo "$msg" | jq -r '.content')
        local author=$(echo "$msg" | jq -r '.author.username')
        local thread_name=$(echo "$msg" | jq -r '.threadName')
        
        # Skip if already processed
        if grep -q "^${msg_id}$" "$PROCESSED_FILE" 2>/dev/null; then
            continue
        fi
        
        # Look up session in registry
        local session=$(get_session "$thread_id")
        
        if [[ -z "$session" || "$session" == "null" ]]; then
            warn "No session for thread $thread_id ($thread_name) - queuing"
            queue_message "$msg_id" "$thread_id" "$content" "no_session"
            echo "$msg_id" >> "$PROCESSED_FILE"
            continue
        fi
        
        local tty=$(echo "$session" | jq -r '.tty')
        local pid=$(echo "$session" | jq -r '.pid')
        
        # Verify PID still alive
        if ! kill -0 "$pid" 2>/dev/null; then
            warn "Session $thread_id PID $pid is dead - cleaning up"
            deregister_session "$thread_id"
            queue_message "$msg_id" "$thread_id" "$content" "dead_session"
            echo "$msg_id" >> "$PROCESSED_FILE"
            continue
        fi
        
        # Inject message to iTerm session with [Discord] prefix so Droid knows to respond back
        log "Message from $author in '$thread_name' -> $tty"
        local prefixed_content="[Discord:$thread_id] $content"
        local result=$(inject_to_iterm "$tty" "$prefixed_content")
        
        if [[ "$result" == "sent" ]]; then
            log "✓ Delivered to $tty"
            update_session_activity "$thread_id"
        else
            warn "✗ Injection failed ($result) - queuing for retry"
            queue_message "$msg_id" "$thread_id" "$content" "inject_failed"
        fi
        
        echo "$msg_id" >> "$PROCESSED_FILE"
    done
}

# Handle graceful shutdown
cleanup() {
    log "Bridge shutting down..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main entry point
main() {
    ensure_factory_dir
    init_registry
    init_queue
    
    log "Discord-Droid Bridge V2 starting..."
    log "iTerm2-only, fswatch-based, no focus steal"
    log "Watching: $INBOX_FILE"
    log "Registry: $SESSIONS_FILE"
    log "Press Ctrl+C to stop"
    echo ""
    
    check_dependencies
    
    # Clean up any dead sessions on startup
    cleanup_dead_sessions
    
    # Process any existing inbox messages
    process_inbox
    
    # Also process retry queue
    process_queue
    
    # Watch for inbox changes with fswatch
    # -o outputs a single line per batch of events (more efficient)
    # --event Updated only triggers on file modifications
    fswatch -o --event Updated "$INBOX_FILE" 2>/dev/null | while read -r _; do
        process_inbox
        process_queue
    done
}

# Run main
main "$@"

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

# Check dependencies
check_dependencies() {
    if ! command -v fswatch &> /dev/null; then
        error "fswatch is required. Run: brew install fswatch"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is required. Run: brew install jq"
        exit 1
    fi
    
    if ! is_iterm_running; then
        log "iTerm2 not detected, waiting for sessions..."
    fi
}

# Process new messages from inbox
process_inbox() {
    [[ ! -f "$INBOX_FILE" ]] && return
    
    local unread=$(jq -r '.unreadCount // 0' "$INBOX_FILE" 2>/dev/null)
    [[ "$unread" -eq 0 || "$unread" == "null" ]] && return
    
    # Process each message as compact JSON (safer than TSV for content with special chars)
    jq -c '.messages[]?' "$INBOX_FILE" 2>/dev/null | while IFS= read -r msg; do
        [[ -z "$msg" ]] && continue
        
        # Extract fields from JSON
        local msg_id=$(echo "$msg" | jq -r '.id')
        local thread_id=$(echo "$msg" | jq -r '.threadId')
        local content=$(echo "$msg" | jq -r '.content')
        local author=$(echo "$msg" | jq -r '.author.username')
        
        [[ -z "$msg_id" ]] && continue
        
        # Skip if already processed
        if grep -q "^${msg_id}$" "$PROCESSED_FILE" 2>/dev/null; then
            continue
        fi
        
        # Validate thread ID format
        if ! [[ "$thread_id" =~ ^[0-9]{17,20}$ ]]; then
            error "Invalid thread ID: $thread_id"
            echo "$msg_id" >> "$PROCESSED_FILE"
            continue
        fi
        
        # Look up session in registry
        local session=$(get_session "$thread_id")
        
        if [[ -z "$session" || "$session" == "null" ]]; then
            log "No session for thread $thread_id - message dropped"
            echo "$msg_id" >> "$PROCESSED_FILE"
            continue
        fi
        
        # Extract tty and pid
        local tty=$(echo "$session" | jq -r '.tty')
        local pid=$(echo "$session" | jq -r '.pid')
        
        # Verify PID still alive
        if ! kill -0 "$pid" 2>/dev/null; then
            log "Session $thread_id dead (PID $pid) - cleaning up"
            deregister_session "$thread_id"
            echo "$msg_id" >> "$PROCESSED_FILE"
            continue
        fi
        
        # Inject message with [Discord:threadId] prefix
        log "Message from $author -> $tty"
        local prefixed_content="[Discord:$thread_id] $content"
        local result=$(inject_to_iterm "$tty" "$prefixed_content")
        
        if [[ "$result" == "sent" ]]; then
            log "✓ Delivered"
        else
            error "Injection failed: $result"
        fi
        
        echo "$msg_id" >> "$PROCESSED_FILE"
    done
    
    # Rotate processed file periodically
    rotate_processed_file
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
    rotate_log_file
    
    log "Discord-Droid Bridge V2 starting..."
    log "Watching: $INBOX_FILE"
    echo ""
    
    check_dependencies
    cleanup_dead_sessions
    process_inbox
    
    # Watch for inbox changes with fswatch
    fswatch -o --event Updated "$INBOX_FILE" 2>/dev/null | while read -r _; do
        process_inbox
    done
}

main "$@"

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

# Process new messages from inbox (optimized: single jq parse per message)
process_inbox() {
    [[ ! -f "$INBOX_FILE" ]] && return
    
    local unread=$(jq -r '.unreadCount // 0' "$INBOX_FILE" 2>/dev/null)
    [[ "$unread" -eq 0 || "$unread" == "null" ]] && return
    
    # Single jq call extracts all needed fields as TSV
    jq -r '.messages[]? | [.id, .threadId, .content, .author.username] | @tsv' "$INBOX_FILE" 2>/dev/null | \
    while IFS=$'\t' read -r msg_id thread_id content author; do
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
        
        # Extract tty and pid in single jq call
        local tty pid
        read -r tty pid < <(echo "$session" | jq -r '[.tty, .pid] | @tsv')
        
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

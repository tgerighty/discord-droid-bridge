#!/bin/bash
#
# Discord-Droid Bridge V2
# Event-driven, iTerm2-only message injection
# Uses fswatch for instant detection, direct TTY write for no focus steal
#

set -uo pipefail  # Note: -e omitted to allow graceful error handling in loops

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library files
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/inject.sh"

# Associative array for O(1) processed message lookup
declare -A PROCESSED_IDS

# Load processed IDs into memory
load_processed_ids() {
    PROCESSED_IDS=()
    if [[ -f "$PROCESSED_FILE" ]]; then
        while IFS= read -r id; do
            [[ -n "$id" ]] && PROCESSED_IDS["$id"]=1
        done < "$PROCESSED_FILE"
    fi
}

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

# Check if session is alive (PID running or TTY has processes)
is_session_alive() {
    local pid="$1"
    local tty="$2"
    
    # If PID is valid and running, session is alive
    if [[ -n "$pid" && "$pid" != "null" && "$pid" =~ ^[0-9]+$ ]]; then
        kill -0 "$pid" 2>/dev/null && return 0
    fi
    
    # Otherwise check if TTY has any processes
    tty_has_processes "$tty"
}

# Process new messages from inbox
process_inbox() {
    [[ ! -f "$INBOX_FILE" ]] && return 0

    # Reload processed IDs to catch any external changes
    load_processed_ids

    # Process each message - single jq call extracts all fields (performance optimization)
    while IFS=$'\t' read -r msg_id thread_id author thread_name content; do
        [[ -z "$msg_id" ]] && continue
        
        # O(1) lookup instead of grep
        [[ -n "${PROCESSED_IDS[$msg_id]:-}" ]] && continue
        
        # Validate thread ID format
        if ! [[ "$thread_id" =~ ^[0-9]{17,20}$ ]]; then
            error "Invalid thread ID: $thread_id"
            echo "$msg_id" >> "$PROCESSED_FILE"
            PROCESSED_IDS["$msg_id"]=1
            continue
        fi
        
        # Look up session in registry
        local session
        session=$(get_session "$thread_id")
        
        if [[ -z "$session" || "$session" == "null" ]]; then
            if [[ -n "${DROID_TTY:-}" ]] && validate_tty "$DROID_TTY" && tty_has_processes "$DROID_TTY"; then
                log "Auto-registering thread $thread_id to DROID_TTY=$DROID_TTY"
                register_session_with_tty "$thread_id" "$thread_name" "$DROID_TTY" ""
                session=$(get_session "$thread_id")
            fi
        fi

        if [[ -z "$session" || "$session" == "null" ]]; then
            log "No session for thread $thread_id - message dropped"
            echo "$msg_id" >> "$PROCESSED_FILE"
            PROCESSED_IDS["$msg_id"]=1
            continue
        fi
        
        # Extract tty and pid in single jq call
        local tty pid
        read -r tty pid < <(echo "$session" | jq -r '[.tty, .pid] | @tsv')
        
        # Verify session is still alive
        if ! is_session_alive "$pid" "$tty"; then
            log "Session $thread_id dead (PID $pid) - cleaning up"
            deregister_session "$thread_id"
            echo "$msg_id" >> "$PROCESSED_FILE"
            PROCESSED_IDS["$msg_id"]=1
            continue
        fi
        
        # Inject message with [Discord:threadId] prefix
        log "Message from $author -> $tty"
        local prefixed_content="[Discord:$thread_id] $content"
        local result
        result=$(inject_to_iterm "$tty" "$prefixed_content") || true
        
        if [[ "$result" == "sent" ]]; then
            log "✓ Delivered"
        else
            error "Injection failed: $result"
        fi
        
        echo "$msg_id" >> "$PROCESSED_FILE"
        PROCESSED_IDS["$msg_id"]=1
        
    done < <(jq -r '.messages[]? | [.id, .threadId, .author.username, (.threadName // ""), .content] | @tsv' "$INBOX_FILE" 2>/dev/null)
    
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
    
    # Watch for inbox changes with fswatch (handle create/rename)
    fswatch -o --event Updated --event Created --event Renamed "$FACTORY_DIR" 2>/dev/null | while read -r _; do
        process_inbox
    done
}

main "$@"

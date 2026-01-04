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

# Check if message ID has been processed (file-based for Bash 3.2 compatibility)
is_processed() {
    local msg_id="$1"
    [[ -f "$PROCESSED_FILE" ]] && grep -qxF "$msg_id" "$PROCESSED_FILE" 2>/dev/null
}

# Mark message ID as processed
mark_processed() {
    local msg_id="$1"
    echo "$msg_id" >> "$PROCESSED_FILE"
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

# Check if session is alive (PID running with same start time, or TTY has processes)
is_session_alive() {
    local pid="$1"
    local tty="$2"
    local pid_start="${3:-}"
    
    # If PID is valid and running, verify it's the same process (prevent PID reuse false positive)
    if [[ -n "$pid" && "$pid" != "null" && "$pid" =~ ^[0-9]+$ ]]; then
        if kill -0 "$pid" 2>/dev/null; then
            # If we have stored start time, verify it matches
            if [[ -n "$pid_start" && "$pid_start" != "null" ]]; then
                is_same_process "$pid" "$pid_start" && return 0
            else
                # No start time stored, fall back to basic kill check
                return 0
            fi
        fi
    fi
    
    # Otherwise check if TTY has any processes
    tty_has_processes "$tty"
}

# Process new messages from inbox with atomic snapshot
process_inbox() {
    [[ ! -f "$INBOX_FILE" ]] && return 0

    # Take atomic snapshot of inbox to prevent race conditions
    local inbox_snapshot
    inbox_snapshot=$(secure_temp)
    cp "$INBOX_FILE" "$inbox_snapshot" 2>/dev/null || { rm -f "$inbox_snapshot"; return 0; }
    
    # Ensure cleanup of snapshot
    trap 'rm -f "$inbox_snapshot" 2>/dev/null' RETURN

    # Process each message - single jq call extracts all fields (performance optimization)
    while IFS=$'\t' read -r msg_id thread_id author thread_name content; do
        [[ -z "$msg_id" ]] && continue
        
        # Skip already processed messages
        is_processed "$msg_id" && continue
        
        # Validate thread ID format
        if ! [[ "$thread_id" =~ ^[0-9]{17,20}$ ]]; then
            error "Invalid thread ID: $thread_id"
            mark_processed "$msg_id"
            continue
        fi
        
        # Look up session in registry
        local session
        session=$(get_session "$thread_id")
        
        if [[ -z "$session" || "$session" == "null" ]]; then
            log "No session for thread $thread_id - message dropped"
            mark_processed "$msg_id"
            continue
        fi
        
        # Extract tty, pid, and pidStart in single jq call
        local tty pid pid_start
        read -r tty pid pid_start < <(echo "$session" | jq -r '[.tty, .pid, .pidStart] | @tsv')
        
        # Verify session is still alive (with PID reuse protection)
        if ! is_session_alive "$pid" "$tty" "$pid_start"; then
            log "Session $thread_id dead (PID $pid) - cleaning up"
            deregister_session "$thread_id"
            mark_processed "$msg_id"
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
        
        mark_processed "$msg_id"
        
    done < <(jq -r '.messages[]? | [.id, .threadId, .author.username, (.threadName // ""), .content] | @tsv' "$inbox_snapshot" 2>/dev/null)
    
    rm -f "$inbox_snapshot" 2>/dev/null
    
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

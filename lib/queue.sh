#!/bin/bash
# Discord-Droid Bridge V2 - Message Queue
# Handles undeliverable messages with retry logic

# Initialize queue file if needed
init_queue() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo '{"queued":[],"deadLetter":[]}' > "$QUEUE_FILE"
    fi
}

# Add message to queue
# Usage: queue_message <msg_id> <threadId> <content> <reason>
queue_message() {
    local msg_id="$1"
    local thread_id="$2"
    local content="$3"
    local reason="$4"
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local next_retry=$(date -u -v+1S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 second' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$now")
    
    init_queue
    
    # Check if already queued
    local existing=$(jq -r --arg id "$msg_id" '[.queued[] | select(.id == $id)] | length' "$QUEUE_FILE")
    if [[ "$existing" -gt 0 ]]; then
        return 0
    fi
    
    # Escape content for JSON
    local escaped_content=$(echo "$content" | jq -Rs .)
    
    jq --arg id "$msg_id" \
       --arg tid "$thread_id" \
       --argjson content "$escaped_content" \
       --arg reason "$reason" \
       --arg now "$now" \
       --arg next "$next_retry" \
       '.queued += [{
         id: $id,
         threadId: $tid,
         content: $content,
         reason: $reason,
         queuedAt: $now,
         attempts: 1,
         nextRetry: $next
       }]' "$QUEUE_FILE" > "/tmp/queue.$$.json" \
       && mv "/tmp/queue.$$.json" "$QUEUE_FILE"
}

# Remove message from queue
# Usage: dequeue_message <msg_id>
dequeue_message() {
    local msg_id="$1"
    
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    
    jq --arg id "$msg_id" '.queued = [.queued[] | select(.id != $id)]' "$QUEUE_FILE" > "/tmp/queue.$$.json" \
       && mv "/tmp/queue.$$.json" "$QUEUE_FILE"
}

# Move message to dead letter queue
# Usage: dead_letter_message <msg_id>
dead_letter_message() {
    local msg_id="$1"
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    [[ ! -f "$QUEUE_FILE" ]] && return 1
    
    # Get the message
    local msg=$(jq -r --arg id "$msg_id" '[.queued[] | select(.id == $id)] | first // null' "$QUEUE_FILE")
    
    if [[ "$msg" != "null" ]]; then
        # Move to dead letter
        jq --arg id "$msg_id" --arg now "$now" \
           '.deadLetter += [(.queued[] | select(.id == $id) | . + {deadLetteredAt: $now})] | .queued = [.queued[] | select(.id != $id)]' \
           "$QUEUE_FILE" > "/tmp/queue.$$.json" \
           && mv "/tmp/queue.$$.json" "$QUEUE_FILE"
    fi
}

# Increment retry count and update next retry time
# Usage: increment_retry <msg_id>
increment_retry() {
    local msg_id="$1"
    
    [[ ! -f "$QUEUE_FILE" ]] && return 1
    
    local attempts=$(jq -r --arg id "$msg_id" '[.queued[] | select(.id == $id)] | first | .attempts // 0' "$QUEUE_FILE")
    local new_attempts=$((attempts + 1))
    
    # Exponential backoff: 2^attempts seconds, max 60 seconds
    local delay=$((RETRY_BACKOFF_BASE ** new_attempts))
    [[ $delay -gt 60 ]] && delay=60
    
    local next_retry=$(date -u -v+${delay}S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+${delay} seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    
    jq --arg id "$msg_id" \
       --argjson attempts "$new_attempts" \
       --arg next "$next_retry" \
       '.queued = [.queued[] | if .id == $id then .attempts = $attempts | .nextRetry = $next else . end]' \
       "$QUEUE_FILE" > "/tmp/queue.$$.json" \
       && mv "/tmp/queue.$$.json" "$QUEUE_FILE"
    
    echo "$new_attempts"
}

# Get messages ready for retry
# Usage: get_retry_messages
# Returns: JSON array of messages ready to retry
get_retry_messages() {
    [[ ! -f "$QUEUE_FILE" ]] && echo "[]" && return 0
    
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    jq -c --arg now "$now" '[.queued[] | select(.nextRetry <= $now)]' "$QUEUE_FILE"
}

# Process the retry queue
# Usage: process_queue
# Requires: get_session, inject_to_iterm from other libs
process_queue() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    
    local messages=$(get_retry_messages)
    local count=$(echo "$messages" | jq 'length')
    
    [[ "$count" -eq 0 ]] && return 0
    
    log "Processing $count queued message(s)"
    
    echo "$messages" | jq -c '.[]' | while read -r msg; do
        local msg_id=$(echo "$msg" | jq -r '.id')
        local thread_id=$(echo "$msg" | jq -r '.threadId')
        local content=$(echo "$msg" | jq -r '.content')
        local attempts=$(echo "$msg" | jq -r '.attempts')
        
        # Look up session
        local session=$(get_session "$thread_id")
        
        if [[ -z "$session" || "$session" == "null" ]]; then
            # Still no session, increment retry
            local new_attempts=$(increment_retry "$msg_id")
            if [[ "$new_attempts" -ge "$MAX_RETRIES" ]]; then
                warn "Message $msg_id exceeded max retries, moving to dead letter"
                dead_letter_message "$msg_id"
            fi
            continue
        fi
        
        local tty=$(echo "$session" | jq -r '.tty')
        local pid=$(echo "$session" | jq -r '.pid')
        
        # Verify PID still alive
        if ! kill -0 "$pid" 2>/dev/null; then
            deregister_session "$thread_id"
            local new_attempts=$(increment_retry "$msg_id")
            if [[ "$new_attempts" -ge "$MAX_RETRIES" ]]; then
                warn "Message $msg_id exceeded max retries, moving to dead letter"
                dead_letter_message "$msg_id"
            fi
            continue
        fi
        
        # Try to inject
        local result=$(inject_to_iterm "$tty" "$content")
        
        if [[ "$result" == "sent" ]]; then
            log "✓ Delivered queued message $msg_id to $tty"
            dequeue_message "$msg_id"
        else
            local new_attempts=$(increment_retry "$msg_id")
            if [[ "$new_attempts" -ge "$MAX_RETRIES" ]]; then
                warn "Message $msg_id exceeded max retries, moving to dead letter"
                dead_letter_message "$msg_id"
            fi
        fi
    done
}

# Get queue stats
# Usage: get_queue_stats
get_queue_stats() {
    [[ ! -f "$QUEUE_FILE" ]] && echo '{"queued":0,"deadLetter":0}' && return 0
    
    jq '{queued: (.queued | length), deadLetter: (.deadLetter | length)}' "$QUEUE_FILE"
}

# Clear dead letter queue
# Usage: clear_dead_letter
clear_dead_letter() {
    [[ ! -f "$QUEUE_FILE" ]] && return 0
    
    jq '.deadLetter = []' "$QUEUE_FILE" > "/tmp/queue.$$.json" \
       && mv "/tmp/queue.$$.json" "$QUEUE_FILE"
}

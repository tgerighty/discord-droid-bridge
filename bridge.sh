#!/bin/bash
#
# Discord-Droid Bridge
# Watches for Discord messages and injects them into the active Droid CLI session
# Automatically finds the terminal window running Droid
#

INBOX_FILE="$HOME/.factory/discord-inbox.json"
PROCESSED_FILE="$HOME/.factory/discord-inbox-processed.txt"
CHECK_INTERVAL=${CHECK_INTERVAL:-5}  # seconds between checks

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[bridge]${NC} $(date '+%H:%M:%S') $1"
}

warn() {
    echo -e "${YELLOW}[bridge]${NC} $(date '+%H:%M:%S') $1"
}

error() {
    echo -e "${RED}[bridge]${NC} $(date '+%H:%M:%S') $1"
}

info() {
    echo -e "${BLUE}[bridge]${NC} $(date '+%H:%M:%S') $1"
}

# Ensure processed file exists
touch "$PROCESSED_FILE"

# Check dependencies
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Run: brew install jq"
    exit 1
fi

find_droid_window() {
    local thread_id="${1:-}"
    
    # Require thread_id - no fallback to generic windows
    if [[ -z "$thread_id" ]]; then
        echo "not_found"
        return 1
    fi
    
    # Try Terminal.app first - strict match on threadId only
    TERMINAL_WINDOWS=$(osascript -e 'tell application "Terminal" to get name of every window' 2>/dev/null)
    
    if echo "$TERMINAL_WINDOWS" | grep -q "$thread_id"; then
        echo "Terminal:$thread_id"
        return 0
    fi
    
    # Try iTerm2 - check session names (more reliable than window names)
    ITERM_SESSIONS=$(osascript <<'APPLESCRIPT'
tell application "iTerm"
    set allNames to {}
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                set end of allNames to name of s
            end repeat
        end repeat
    end repeat
    return allNames
end tell
APPLESCRIPT
    2>/dev/null)
    
    if echo "$ITERM_SESSIONS" | grep -q "$thread_id"; then
        echo "iTerm:$thread_id"
        return 0
    fi
    
    # No fallback - messages only go to their originating session
    echo "not_found"
    return 1
}

inject_to_terminal() {
    local message="$1"
    local app_and_term="$2"
    
    # Parse app:search_term format
    local app="${app_and_term%%:*}"
    local search_term="${app_and_term#*:}"
    
    # Escape special characters for AppleScript
    local escaped_message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    if [[ "$app" == "iTerm" ]]; then
        osascript <<EOF
tell application "iTerm"
    set windowList to every window
    repeat with w in windowList
        if name of w contains "$search_term" then
            tell current session of w
                write text "$escaped_message"
            end tell
            return "sent"
        end if
    end repeat
end tell
return "not_found"
EOF
    else
        # Terminal.app - use clipboard paste method (more reliable)
        # Save current clipboard
        local old_clipboard=$(pbpaste 2>/dev/null)
        
        # Put message in clipboard
        echo -n "$message" | pbcopy
        
        osascript <<EOF
tell application "Terminal"
    set windowList to every window
    repeat with i from 1 to count of windowList
        set w to item i of windowList
        if name of w contains "$search_term" then
            -- Bring window to front
            set frontmost of w to true
            activate
            delay 0.3
            -- Paste from clipboard and press enter
            tell application "System Events"
                keystroke "v" using command down
                delay 0.3
                key code 36  -- Return key
            end tell
            return "sent"
        end if
    end repeat
end tell
return "not_found"
EOF
        local result=$?
        
        # Restore old clipboard
        if [[ -n "$old_clipboard" ]]; then
            echo -n "$old_clipboard" | pbcopy
        fi
        
        return $result
    fi
}

log "Discord-Droid Bridge starting..."
log "Watching: $INBOX_FILE"
log "Check interval: ${CHECK_INTERVAL}s"
log "Messages only route to sessions with matching threadId in window title"
log "Press Ctrl+C to stop"
echo ""

while true; do
    # Check if inbox file exists and has content
    if [[ -f "$INBOX_FILE" ]]; then
        # Get unread messages
        UNREAD_COUNT=$(jq -r '.unreadCount // 0' "$INBOX_FILE" 2>/dev/null)
        
        if [[ "$UNREAD_COUNT" -gt 0 ]]; then
            # Process each unread message
            jq -c '.messages[]?' "$INBOX_FILE" 2>/dev/null | while read -r msg; do
                MSG_ID=$(echo "$msg" | jq -r '.id')
                MSG_CONTENT=$(echo "$msg" | jq -r '.content')
                MSG_AUTHOR=$(echo "$msg" | jq -r '.author.username')
                MSG_THREAD=$(echo "$msg" | jq -r '.threadName')
                MSG_THREAD_ID=$(echo "$msg" | jq -r '.threadId')
                
                # Check if already processed
                if ! grep -q "^${MSG_ID}$" "$PROCESSED_FILE" 2>/dev/null; then
                    # Find the droid window for this specific thread
                    DROID_APP=$(find_droid_window "$MSG_THREAD_ID")
                    
                    if [[ "$DROID_APP" == "not_found" ]]; then
                        warn "Message for thread $MSG_THREAD_ID but no matching window found"
                        # Still mark as processed to avoid repeated warnings
                        echo "$MSG_ID" >> "$PROCESSED_FILE"
                    else
                        log "New message from $MSG_AUTHOR in '$MSG_THREAD' (thread: $MSG_THREAD_ID)"
                        info "Content: $MSG_CONTENT"
                        info "Target: $DROID_APP"
                        
                        # Inject into terminal
                        RESULT=$(inject_to_terminal "$MSG_CONTENT" "$DROID_APP")
                        
                        if [[ "$RESULT" == "sent" ]]; then
                            # Mark as processed
                            echo "$MSG_ID" >> "$PROCESSED_FILE"
                            log "✓ Injected into $DROID_APP"
                        else
                            warn "Failed to inject message"
                        fi
                    fi
                fi
            done
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done

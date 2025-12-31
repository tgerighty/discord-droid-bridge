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
    # Try Terminal.app first
    TERMINAL_WINDOWS=$(osascript -e 'tell application "Terminal" to get name of every window' 2>/dev/null)
    
    # Look for window with "droid" in the name
    if echo "$TERMINAL_WINDOWS" | grep -qi "droid"; then
        # Find the index of the droid window
        INDEX=$(osascript <<'EOF'
tell application "Terminal"
    set windowList to every window
    repeat with i from 1 to count of windowList
        set winName to name of item i of windowList
        if winName contains "droid" then
            return {app:"Terminal", index:i}
        end if
    end repeat
end tell
return "not_found"
EOF
)
        if [[ "$INDEX" != "not_found" ]]; then
            echo "Terminal"
            return 0
        fi
    fi
    
    # Try iTerm2
    ITERM_WINDOWS=$(osascript -e 'tell application "iTerm" to get name of every window' 2>/dev/null)
    
    if echo "$ITERM_WINDOWS" | grep -qi "droid"; then
        echo "iTerm"
        return 0
    fi
    
    echo "not_found"
    return 1
}

inject_to_terminal() {
    local message="$1"
    local app="$2"
    
    # Escape special characters for AppleScript
    local escaped_message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    if [[ "$app" == "iTerm" ]]; then
        osascript <<EOF
tell application "iTerm"
    set windowList to every window
    repeat with w in windowList
        if name of w contains "droid" then
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
        if name of w contains "droid" then
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
log "Will auto-detect Terminal/iTerm window running Droid"
log "Press Ctrl+C to stop"
echo ""

# Initial check for Droid window
DROID_APP=$(find_droid_window)
if [[ "$DROID_APP" == "not_found" ]]; then
    warn "No Droid window found yet. Will keep checking..."
else
    log "Found Droid running in: $DROID_APP"
fi

while true; do
    # Check if inbox file exists and has content
    if [[ -f "$INBOX_FILE" ]]; then
        # Get unread messages
        UNREAD_COUNT=$(jq -r '.unreadCount // 0' "$INBOX_FILE" 2>/dev/null)
        
        if [[ "$UNREAD_COUNT" -gt 0 ]]; then
            # Find the droid window
            DROID_APP=$(find_droid_window)
            
            if [[ "$DROID_APP" == "not_found" ]]; then
                warn "Discord message waiting but no Droid window found!"
            else
                # Process each unread message
                jq -c '.messages[]?' "$INBOX_FILE" 2>/dev/null | while read -r msg; do
                    MSG_ID=$(echo "$msg" | jq -r '.id')
                    MSG_CONTENT=$(echo "$msg" | jq -r '.content')
                    MSG_AUTHOR=$(echo "$msg" | jq -r '.author.username')
                    MSG_THREAD=$(echo "$msg" | jq -r '.threadName')
                    
                    # Check if already processed
                    if ! grep -q "^${MSG_ID}$" "$PROCESSED_FILE" 2>/dev/null; then
                        log "New message from $MSG_AUTHOR in '$MSG_THREAD'"
                        info "Content: $MSG_CONTENT"
                        
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
                done
            fi
        fi
    fi
    
    sleep "$CHECK_INTERVAL"
done

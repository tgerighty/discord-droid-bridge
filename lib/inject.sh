#!/bin/bash
# Discord-Droid Bridge V2 - iTerm2 Injection
# Direct session write without focus stealing

# Inject message to iTerm session by TTY
# Usage: inject_to_iterm <tty> <message>
# Returns: "sent", "not_found", or "error:<message>"
inject_to_iterm() {
    local tty="$1"
    local message="$2"
    
    # Escape special characters for AppleScript
    local escaped_message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    local result
    result=$(osascript <<EOF
tell application "iTerm"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s is "$tty" then
                    tell s to write text "$escaped_message"
                    return "sent"
                end if
            end repeat
        end repeat
    end repeat
end tell
return "not_found"
EOF
    2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo "error:$result"
        return 1
    fi
    
    echo "$result"
    [[ "$result" == "sent" ]] && return 0 || return 1
}

# Check if iTerm is running
# Usage: is_iterm_running
# Returns: 0 if running, 1 if not
is_iterm_running() {
    pgrep -x "iTerm2" > /dev/null 2>&1
}

# Get all iTerm session TTYs
# Usage: get_iterm_ttys
# Returns: List of TTYs, one per line
get_iterm_ttys() {
    osascript <<'EOF' 2>/dev/null
tell application "iTerm"
    set ttyList to {}
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                set end of ttyList to tty of s
            end repeat
        end repeat
    end repeat
    return ttyList
end tell
EOF
}

# Verify a TTY exists in iTerm
# Usage: verify_iterm_tty <tty>
# Returns: 0 if found, 1 if not
verify_iterm_tty() {
    local tty="$1"
    local ttys=$(get_iterm_ttys)
    
    echo "$ttys" | grep -q "$tty"
}

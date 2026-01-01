#!/bin/bash
# Discord-Droid Bridge V2 - iTerm2 Injection
# Direct session write without focus stealing

# Validate TTY format (security: prevent injection via malformed TTY)
# Usage: validate_tty <tty>
# Returns: 0 if valid, 1 if invalid
validate_tty() {
    local tty="$1"
    # TTY must match /dev/ttysNNN pattern exactly
    [[ "$tty" =~ ^/dev/ttys[0-9]+$ ]]
}

# Validate and sanitize message for AppleScript injection
# Usage: sanitize_message <message>
# Returns: sanitized message or exits with error
sanitize_message() {
    local msg="$1"
    
    # Reject messages with control characters (except newline which we'll handle)
    if [[ "$msg" =~ [[:cntrl:]] && ! "$msg" =~ $'\n' ]]; then
        echo "error:message contains control characters"
        return 1
    fi
    
    # Escape for AppleScript: backslashes, quotes, and convert newlines to spaces
    printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

# Inject message to iTerm session by TTY
# Usage: inject_to_iterm <tty> <message>
# Returns: "sent", "not_found", or "error:<message>"
inject_to_iterm() {
    local tty="$1"
    local message="$2"
    
    # Validate TTY format (security)
    if ! validate_tty "$tty"; then
        echo "error:invalid tty format"
        return 1
    fi
    
    # Sanitize message for AppleScript (security)
    local escaped_message
    escaped_message=$(sanitize_message "$message")
    if [[ $? -ne 0 ]]; then
        echo "$escaped_message"
        return 1
    fi
    
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
    pgrep -f "iTerm" > /dev/null 2>&1
}

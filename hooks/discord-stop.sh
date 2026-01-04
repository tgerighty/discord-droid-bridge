#!/bin/bash
# Discord-Droid Bridge - Stop hook to send last assistant message to Discord
# Also stops the heartbeat daemon since Droid has finished responding.
# Reads hook input on stdin, extracts latest assistant text, and posts to thread.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared config for secure_temp, get_current_thread_id, logging
source "$SCRIPT_DIR/../lib/config.sh" 2>/dev/null || {
    # Fallback if config.sh not found
    secure_temp() {
        local private_tmp="${TMPDIR:-/tmp}/droid-bridge-$$"
        mkdir -p "$private_tmp" && chmod 700 "$private_tmp"
        mktemp "$private_tmp/XXXXXX"
    }
}

# Stop the heartbeat daemon (Droid finished responding)
"$SCRIPT_DIR/discord-heartbeat.sh" stop >/dev/null 2>&1 || true

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

[[ -z "$transcript_path" || ! -f "$transcript_path" ]] && exit 0

# Security: validate transcript path is under allowed directory
if ! validate_path_prefix "$transcript_path" "$HOME/.factory" 2>/dev/null && \
   ! validate_path_prefix "$transcript_path" "${TMPDIR:-/tmp}" 2>/dev/null; then
    exit 0
fi

# Get and validate thread ID using shared function
thread_id=$(get_current_thread_id 2>/dev/null) || exit 0

message=$(jq -s -r 'map(select(.type=="message" and .message.role=="assistant"))
  | last
  | .message.content
  | map(select(.type=="text") | .text)
  | join("\n")' "$transcript_path")

[[ -z "$message" || "$message" == "null" ]] && exit 0

mkdir -p "$HOME/.factory"
state_file="$HOME/.factory/discord-outbound-state.json"
lockfile="$state_file.lock"

fingerprint=$(printf '%s' "$message" | shasum -a 256 | awk '{print $1}')

# Use file locking to prevent race condition with concurrent hooks
(
    exec 200>"$lockfile"
    flock -x 200
    
    last_fp=""
    if [[ -f "$state_file" ]]; then
        last_fp=$(jq -r --arg tid "$thread_id" '.[$tid] // empty' "$state_file")
    fi

    if [[ "$fingerprint" == "$last_fp" ]]; then
        exit 0
    fi

    tmp=$(secure_temp)
    if [[ -f "$state_file" ]]; then
        jq --arg tid "$thread_id" --arg fp "$fingerprint" '.[$tid] = $fp' "$state_file" > "$tmp"
    else
        jq -n --arg tid "$thread_id" --arg fp "$fingerprint" '{($tid): $fp}' > "$tmp"
    fi
    
    # Validate JSON before moving
    if jq empty "$tmp" 2>/dev/null; then
        mv "$tmp" "$state_file"
    else
        rm -f "$tmp"
        exit 1
    fi
    
    flock -u 200
    
    # Send message (outside lock to avoid holding it during network I/O)
    droid-discord send "$thread_id" "$message" >/dev/null 2>&1 || true
)

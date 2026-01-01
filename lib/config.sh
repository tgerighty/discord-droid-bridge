#!/bin/bash
# Discord-Droid Bridge V2 - Configuration
# Shared constants and paths

# Paths
FACTORY_DIR="$HOME/.factory"
INBOX_FILE="$FACTORY_DIR/discord-inbox.json"
SESSIONS_FILE="$FACTORY_DIR/droid-sessions.json"
PROCESSED_FILE="$FACTORY_DIR/discord-inbox-processed.txt"
LOG_FILE="$FACTORY_DIR/bridge-v2.log"

# Settings
MAX_PROCESSED_ENTRIES=1000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions (consolidated to 2)
log() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${GREEN}[bridge]${NC} $timestamp $1"
    echo "[$timestamp] $1" >> "$LOG_FILE" 2>/dev/null
}

error() {
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${RED}[bridge]${NC} $timestamp ERROR: $1"
    echo "[$timestamp] ERROR: $1" >> "$LOG_FILE" 2>/dev/null
}

# Ensure factory directory exists with proper permissions
ensure_factory_dir() {
    umask 077
    mkdir -p "$FACTORY_DIR"
    chmod 700 "$FACTORY_DIR"
    touch "$PROCESSED_FILE"
    chmod 600 "$PROCESSED_FILE"
}

# Rotate processed file to prevent unbounded growth
rotate_processed_file() {
    if [[ -f "$PROCESSED_FILE" ]]; then
        local count=$(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo 0)
        if [[ $count -gt $MAX_PROCESSED_ENTRIES ]]; then
            local tmp=$(mktemp)
            tail -n "$MAX_PROCESSED_ENTRIES" "$PROCESSED_FILE" > "$tmp"
            mv "$tmp" "$PROCESSED_FILE"
            log "Rotated processed file (kept last $MAX_PROCESSED_ENTRIES entries)"
        fi
    fi
}

# Rotate log file if too large (10MB)
rotate_log_file() {
    local max_size=10485760
    if [[ -f "$LOG_FILE" ]]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $max_size ]]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
            touch "$LOG_FILE"
            chmod 600 "$LOG_FILE"
        fi
    fi
}

# File locking for safe concurrent access
# Usage: with_lock <file> <command>
with_lock() {
    local file="$1"
    local cmd="$2"
    local lockfile="${file}.lock"
    (
        flock -x -w 5 200 || { error "Lock timeout: $lockfile"; return 1; }
        eval "$cmd"
    ) 200>"$lockfile"
}

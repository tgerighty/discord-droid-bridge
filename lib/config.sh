#!/bin/bash
# Discord-Droid Bridge V2 - Configuration
# Shared constants and paths

set -euo pipefail

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
NC='\033[0m'

# Acquire exclusive lock on a file (use for registry/state operations)
# Usage: acquire_lock <lockfile_path> <fd_number>
acquire_lock() {
    local lockfile="$1"
    local fd="${2:-200}"
    eval "exec $fd>\"$lockfile\""
    flock -x "$fd"
}

# Release lock
# Usage: release_lock <fd_number>
release_lock() {
    local fd="${1:-200}"
    flock -u "$fd" 2>/dev/null || true
}

# Secure temp file creation with process-specific directory
secure_temp() {
    local private_tmp="${TMPDIR:-/tmp}/droid-bridge-$$"
    mkdir -p "$private_tmp" && chmod 700 "$private_tmp"
    mktemp "$private_tmp/XXXXXX"
}

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



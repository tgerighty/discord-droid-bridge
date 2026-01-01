#!/bin/bash
# Discord-Droid Bridge V2 - Configuration
# Shared constants and paths

# Paths
FACTORY_DIR="$HOME/.factory"
INBOX_FILE="$FACTORY_DIR/discord-inbox.json"
SESSIONS_FILE="$FACTORY_DIR/droid-sessions.json"
QUEUE_FILE="$FACTORY_DIR/discord-queue.json"
PROCESSED_FILE="$FACTORY_DIR/discord-inbox-processed.txt"
LOG_FILE="$FACTORY_DIR/bridge-v2.log"

# Settings
MAX_RETRIES=10
RETRY_BACKOFF_BASE=2
MAX_QUEUE_SIZE=100

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[bridge-v2]${NC} $timestamp $1"
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[bridge-v2]${NC} $timestamp $1"
    echo "[$timestamp] WARN: $1" >> "$LOG_FILE"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[bridge-v2]${NC} $timestamp $1"
    echo "[$timestamp] ERROR: $1" >> "$LOG_FILE"
}

info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[bridge-v2]${NC} $timestamp $1"
}

# Ensure factory directory exists
ensure_factory_dir() {
    mkdir -p "$FACTORY_DIR"
    touch "$PROCESSED_FILE"
}

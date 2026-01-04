#!/bin/bash
# BATS test helper - sets up test environment

# Get the project root directory
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create isolated test environment
setup_test_env() {
    export TEST_FACTORY_DIR=$(mktemp -d)
    export HOME="$TEST_FACTORY_DIR"
    export FACTORY_DIR="$TEST_FACTORY_DIR/.factory"
    mkdir -p "$FACTORY_DIR"
    
    # Override paths in config
    export SESSIONS_FILE="$FACTORY_DIR/droid-sessions.json"
    export INBOX_FILE="$FACTORY_DIR/discord-inbox.json"
    export PROCESSED_FILE="$FACTORY_DIR/discord-inbox-processed.txt"
    export LOG_FILE="$FACTORY_DIR/bridge-v2.log"
}

# Clean up test environment
teardown_test_env() {
    [[ -d "$TEST_FACTORY_DIR" ]] && rm -rf "$TEST_FACTORY_DIR"
}

# Source library files with test overrides
load_lib() {
    local lib="$1"
    source "$PROJECT_ROOT/lib/$lib"
}

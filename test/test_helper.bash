#!/bin/bash
# BATS test helper - sets up test environment

# Get the project root directory
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create isolated test environment
setup_test_env() {
    export TEST_FACTORY_DIR=$(mktemp -d)
    export ORIG_HOME="$HOME"
    export HOME="$TEST_FACTORY_DIR"
    export FACTORY_DIR="$TEST_FACTORY_DIR/.factory"
    mkdir -p "$FACTORY_DIR"
    
    # Override paths in config
    export SESSIONS_FILE="$FACTORY_DIR/droid-sessions.json"
    export INBOX_FILE="$FACTORY_DIR/discord-inbox.json"
    export PROCESSED_FILE="$FACTORY_DIR/discord-inbox-processed.txt"
    export LOG_FILE="$FACTORY_DIR/bridge-v2.log"
    
    # Clear any existing env vars that might interfere
    unset DROID_THREAD_ID
    unset DROID_TTY
    unset DROID_SESSION_PID
    unset DISCORD_TOKEN
}

# Clean up test environment
teardown_test_env() {
    export HOME="$ORIG_HOME"
    [[ -d "$TEST_FACTORY_DIR" ]] && rm -rf "$TEST_FACTORY_DIR"
}

# Source library files with test overrides
load_lib() {
    local lib="$1"
    source "$PROJECT_ROOT/lib/$lib"
}

# Helper to create a mock session file
create_test_session() {
    local thread_id="$1"
    local tty="${2:-/dev/ttys001}"
    local pid="${3:-12345}"
    
    cat > "$SESSIONS_FILE" <<EOF
{
  "sessions": {
    "$thread_id": {
      "tty": "$tty",
      "pid": $pid,
      "name": "test-session",
      "registered": "2024-01-01T00:00:00Z"
    }
  }
}
EOF
}

# Helper to create test inbox
create_test_inbox() {
    local thread_id="$1"
    local msg_id="${2:-1234567890123456789}"
    local content="${3:-Test message}"
    
    cat > "$INBOX_FILE" <<EOF
{
  "unreadCount": 1,
  "watchedThreads": ["$thread_id"],
  "messages": [
    {
      "id": "$msg_id",
      "threadId": "$thread_id",
      "content": "$content",
      "author": {"username": "testuser", "bot": false}
    }
  ]
}
EOF
}

# Assert helper for cleaner tests
assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    
    if [[ "$expected" != "$actual" ]]; then
        echo "Expected: $expected"
        echo "Actual: $actual"
        [[ -n "$msg" ]] && echo "Message: $msg"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Expected '$haystack' to contain '$needle'"
        return 1
    fi
}

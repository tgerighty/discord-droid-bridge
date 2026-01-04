#!/usr/bin/env bats
# Tests for lib/config.sh - Configuration and utility functions

load 'test_helper'

setup() {
    setup_test_env
    load_lib 'config.sh'
}

teardown() {
    teardown_test_env
}

# =============================================================================
# secure_temp() tests
# =============================================================================

@test "secure_temp creates file in private directory" {
    local tmp
    tmp=$(secure_temp)
    
    [ -f "$tmp" ]
    [[ "$tmp" == *"/droid-bridge-"* ]]
    
    rm -f "$tmp"
}

@test "secure_temp creates directory with 700 permissions" {
    local tmp
    tmp=$(secure_temp)
    
    local dir=$(dirname "$tmp")
    local perms=$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null)
    [ "$perms" = "700" ]
    
    rm -f "$tmp"
}

@test "secure_temp creates unique files" {
    local tmp1 tmp2
    tmp1=$(secure_temp)
    tmp2=$(secure_temp)
    
    [ "$tmp1" != "$tmp2" ]
    
    rm -f "$tmp1" "$tmp2"
}

# =============================================================================
# get_current_thread_id() tests
# =============================================================================

@test "get_current_thread_id returns empty when no session file" {
    run get_current_thread_id
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "get_current_thread_id returns thread ID from session file" {
    mkdir -p "$HOME/.factory"
    echo "1234567890123456789" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 0 ]
    [ "$output" = "1234567890123456789" ]
}

@test "get_current_thread_id accepts 17-digit ID" {
    mkdir -p "$HOME/.factory"
    echo "12345678901234567" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 0 ]
}

@test "get_current_thread_id accepts 20-digit ID" {
    mkdir -p "$HOME/.factory"
    echo "12345678901234567890" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 0 ]
}

@test "get_current_thread_id rejects invalid thread ID" {
    mkdir -p "$HOME/.factory"
    echo "invalid" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 1 ]
}

@test "get_current_thread_id rejects empty file" {
    mkdir -p "$HOME/.factory"
    echo "" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 1 ]
}

@test "get_current_thread_id rejects short ID (16 digits)" {
    mkdir -p "$HOME/.factory"
    echo "1234567890123456" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 1 ]
}

@test "get_current_thread_id rejects long ID (21 digits)" {
    mkdir -p "$HOME/.factory"
    echo "123456789012345678901" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_path_prefix() tests
# =============================================================================

@test "validate_path_prefix accepts valid paths" {
    run validate_path_prefix "/home/user/.factory/file.json" "/home/user/.factory"
    [ "$status" -eq 0 ]
}

@test "validate_path_prefix accepts exact prefix match" {
    run validate_path_prefix "/home/user/.factory" "/home/user/.factory"
    [ "$status" -eq 0 ]
}

@test "validate_path_prefix accepts nested paths" {
    run validate_path_prefix "/home/user/.factory/sub/dir/file.json" "/home/user/.factory"
    [ "$status" -eq 0 ]
}

@test "validate_path_prefix rejects paths outside prefix" {
    run validate_path_prefix "/etc/passwd" "/home/user/.factory"
    [ "$status" -eq 1 ]
}

@test "validate_path_prefix rejects partial prefix match" {
    run validate_path_prefix "/home/user/.factory-other/file" "/home/user/.factory"
    [ "$status" -eq 1 ]
}

@test "validate_path_prefix rejects path traversal" {
    run validate_path_prefix "/home/user/.factory/../etc/passwd" "/home/user/.factory"
    [ "$status" -eq 1 ]
}

# =============================================================================
# acquire_lock() and release_lock() tests
# =============================================================================

@test "acquire_lock creates lock directory (mkdir fallback)" {
    # Force mkdir fallback by using a path where flock won't be found
    local orig_path="$PATH"
    export PATH="/usr/bin:/bin"
    
    local lockfile="$TEST_FACTORY_DIR/test.lock"
    
    acquire_lock "$lockfile"
    [ -d "${lockfile}.d" ]
    
    release_lock
    export PATH="$orig_path"
}

@test "release_lock removes lock directory" {
    local orig_path="$PATH"
    export PATH="/usr/bin:/bin"
    
    local lockfile="$TEST_FACTORY_DIR/test.lock"
    
    acquire_lock "$lockfile"
    release_lock
    
    [ ! -d "${lockfile}.d" ]
    
    export PATH="$orig_path"
}

@test "acquire_lock is reentrant after release" {
    local orig_path="$PATH"
    export PATH="/usr/bin:/bin"
    
    local lockfile="$TEST_FACTORY_DIR/test.lock"
    
    acquire_lock "$lockfile"
    release_lock
    
    # Should be able to acquire again
    acquire_lock "$lockfile"
    [ -d "${lockfile}.d" ]
    
    release_lock
    export PATH="$orig_path"
}

# =============================================================================
# ensure_factory_dir() tests
# =============================================================================

@test "ensure_factory_dir creates directory" {
    rm -rf "$FACTORY_DIR"
    
    ensure_factory_dir
    
    [ -d "$FACTORY_DIR" ]
}

@test "ensure_factory_dir creates directory with 700 permissions" {
    rm -rf "$FACTORY_DIR"
    
    ensure_factory_dir
    
    local perms=$(stat -f '%Lp' "$FACTORY_DIR" 2>/dev/null || stat -c '%a' "$FACTORY_DIR" 2>/dev/null)
    [ "$perms" = "700" ]
}

@test "ensure_factory_dir creates processed file" {
    rm -rf "$FACTORY_DIR"
    
    ensure_factory_dir
    
    [ -f "$PROCESSED_FILE" ]
}

@test "ensure_factory_dir sets processed file permissions to 600" {
    rm -rf "$FACTORY_DIR"
    
    ensure_factory_dir
    
    local perms=$(stat -f '%Lp' "$PROCESSED_FILE" 2>/dev/null || stat -c '%a' "$PROCESSED_FILE" 2>/dev/null)
    [ "$perms" = "600" ]
}

@test "ensure_factory_dir is idempotent" {
    ensure_factory_dir
    ensure_factory_dir
    
    [ -d "$FACTORY_DIR" ]
}

# =============================================================================
# rotate_processed_file() tests
# =============================================================================

@test "rotate_processed_file keeps file under limit" {
    ensure_factory_dir
    
    # Create file with 500 lines (under 1000 limit)
    for i in $(seq 1 500); do
        echo "line$i" >> "$PROCESSED_FILE"
    done
    
    rotate_processed_file
    
    local count=$(wc -l < "$PROCESSED_FILE")
    [ "$count" -eq 500 ]
}

@test "rotate_processed_file trims file over limit" {
    ensure_factory_dir
    export MAX_PROCESSED_ENTRIES=100  # Lower limit for testing
    
    # Create file with 150 lines
    for i in $(seq 1 150); do
        echo "line$i" >> "$PROCESSED_FILE"
    done
    
    rotate_processed_file
    
    local count=$(wc -l < "$PROCESSED_FILE")
    [ "$count" -eq 100 ]
}

@test "rotate_processed_file keeps most recent entries" {
    ensure_factory_dir
    export MAX_PROCESSED_ENTRIES=10
    
    # Create file with 15 lines
    for i in $(seq 1 15); do
        echo "line$i" >> "$PROCESSED_FILE"
    done
    
    rotate_processed_file
    
    # Should keep lines 6-15 (last 10)
    run head -1 "$PROCESSED_FILE"
    [ "$output" = "line6" ]
}

# =============================================================================
# log() and error() tests
# =============================================================================

@test "log writes to log file" {
    ensure_factory_dir
    
    log "Test message"
    
    run cat "$LOG_FILE"
    [[ "$output" == *"Test message"* ]]
}

@test "log includes timestamp" {
    ensure_factory_dir
    
    log "Test message"
    
    run cat "$LOG_FILE"
    # Timestamp format: [HH:MM:SS]
    [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

@test "error writes ERROR prefix" {
    ensure_factory_dir
    
    error "Test error"
    
    run cat "$LOG_FILE"
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Test error"* ]]
}

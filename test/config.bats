#!/usr/bin/env bats
# Tests for lib/config.sh

load 'test_helper'

setup() {
    setup_test_env
    load_lib 'config.sh'
}

teardown() {
    teardown_test_env
}

@test "secure_temp creates file in private directory" {
    local tmp
    tmp=$(secure_temp)
    
    [ -f "$tmp" ]
    [[ "$tmp" == *"/droid-bridge-"* ]]
    
    # Check directory permissions (700)
    local dir=$(dirname "$tmp")
    local perms=$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null)
    [ "$perms" = "700" ]
    
    rm -f "$tmp"
}

@test "get_current_thread_id returns empty when no session file" {
    run get_current_thread_id
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "get_current_thread_id returns thread ID from session file" {
    echo "1234567890123456789" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 0 ]
    [ "$output" = "1234567890123456789" ]
}

@test "get_current_thread_id rejects invalid thread ID" {
    echo "invalid" > "$HOME/.factory/current-discord-session"
    
    run get_current_thread_id
    [ "$status" -eq 1 ]
}

@test "validate_path_prefix accepts valid paths" {
    run validate_path_prefix "/home/user/.factory/file.json" "/home/user/.factory"
    [ "$status" -eq 0 ]
}

@test "validate_path_prefix rejects paths outside prefix" {
    run validate_path_prefix "/etc/passwd" "/home/user/.factory"
    [ "$status" -eq 1 ]
}

@test "acquire_lock and release_lock work without flock" {
    # Force mkdir fallback by hiding flock
    local orig_path="$PATH"
    export PATH="/usr/bin:/bin"
    
    local lockfile="$TEST_FACTORY_DIR/test.lock"
    
    acquire_lock "$lockfile"
    [ -d "${lockfile}.d" ]
    
    release_lock
    [ ! -d "${lockfile}.d" ]
    
    export PATH="$orig_path"
}

@test "ensure_factory_dir creates directory with correct permissions" {
    rm -rf "$FACTORY_DIR"
    
    ensure_factory_dir
    
    [ -d "$FACTORY_DIR" ]
    local perms=$(stat -f '%Lp' "$FACTORY_DIR" 2>/dev/null || stat -c '%a' "$FACTORY_DIR" 2>/dev/null)
    [ "$perms" = "700" ]
}

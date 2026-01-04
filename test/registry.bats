#!/usr/bin/env bats
# Tests for lib/registry.sh - Session registry management

load 'test_helper'

setup() {
    setup_test_env
    load_lib 'config.sh'
    load_lib 'registry.sh'
    init_registry
}

teardown() {
    teardown_test_env
}

# =============================================================================
# validate_thread_id() tests
# =============================================================================

@test "validate_thread_id accepts valid Discord snowflake (19 digits)" {
    run validate_thread_id "1234567890123456789"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id accepts 17-digit ID (minimum)" {
    run validate_thread_id "12345678901234567"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id accepts 20-digit ID (maximum)" {
    run validate_thread_id "12345678901234567890"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id rejects 16-digit ID (too short)" {
    run validate_thread_id "1234567890123456"
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects 21-digit ID (too long)" {
    run validate_thread_id "123456789012345678901"
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects non-numeric" {
    run validate_thread_id "abc12345678901234"
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects empty string" {
    run validate_thread_id ""
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects ID with spaces" {
    run validate_thread_id "123456789 123456789"
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects ID with leading zeros that's too short" {
    run validate_thread_id "0000000000000001"
    [ "$status" -eq 1 ]
}

# =============================================================================
# validate_tty() tests
# =============================================================================

@test "validate_tty accepts valid TTY format" {
    run validate_tty "/dev/ttys001"
    [ "$status" -eq 0 ]
}

@test "validate_tty accepts three-digit TTY" {
    run validate_tty "/dev/ttys123"
    [ "$status" -eq 0 ]
}

@test "validate_tty accepts single-digit TTY" {
    run validate_tty "/dev/ttys0"
    [ "$status" -eq 0 ]
}

@test "validate_tty rejects pty format" {
    run validate_tty "/dev/pty001"
    [ "$status" -eq 1 ]
}

@test "validate_tty rejects absolute path without ttys" {
    run validate_tty "/tmp/fake"
    [ "$status" -eq 1 ]
}

@test "validate_tty rejects relative path" {
    run validate_tty "ttys001"
    [ "$status" -eq 1 ]
}

@test "validate_tty rejects empty string" {
    run validate_tty ""
    [ "$status" -eq 1 ]
}

@test "validate_tty rejects tty without number" {
    run validate_tty "/dev/ttys"
    [ "$status" -eq 1 ]
}

# =============================================================================
# init_registry() tests
# =============================================================================

@test "init_registry creates empty sessions file" {
    rm -f "$SESSIONS_FILE"
    init_registry
    
    [ -f "$SESSIONS_FILE" ]
    local content=$(cat "$SESSIONS_FILE")
    [ "$content" = '{"sessions":{}}' ]
}

@test "init_registry sets file permissions to 600" {
    rm -f "$SESSIONS_FILE"
    init_registry
    
    local perms=$(stat -f '%Lp' "$SESSIONS_FILE" 2>/dev/null || stat -c '%a' "$SESSIONS_FILE" 2>/dev/null)
    [ "$perms" = "600" ]
}

@test "init_registry is idempotent" {
    init_registry
    init_registry
    
    [ -f "$SESSIONS_FILE" ]
    local content=$(cat "$SESSIONS_FILE")
    [[ "$content" == *'"sessions"'* ]]
}

@test "init_registry preserves existing sessions" {
    create_test_session "1234567890123456789"
    
    init_registry
    
    local session=$(get_session "1234567890123456789")
    [ "$session" != "null" ]
}

# =============================================================================
# get_session() tests
# =============================================================================

@test "get_session returns null for unknown thread" {
    run get_session "9999999999999999999"
    [ "$output" = "null" ]
}

@test "get_session returns session data for known thread" {
    create_test_session "1234567890123456789" "/dev/ttys005" "12345"
    
    local session=$(get_session "1234567890123456789")
    local tty=$(echo "$session" | jq -r '.tty')
    
    [ "$tty" = "/dev/ttys005" ]
}

@test "get_session returns null when no sessions file" {
    rm -f "$SESSIONS_FILE"
    
    run get_session "1234567890123456789"
    [ "$output" = "null" ]
}

# =============================================================================
# register_session() tests
# =============================================================================

@test "register_session creates session with provided TTY" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "test-session"
    
    local session=$(get_session "1234567890123456789")
    local tty=$(echo "$session" | jq -r '.tty')
    
    [ "$tty" = "/dev/ttys005" ]
}

@test "register_session stores session name" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "my-project:main"
    
    local session=$(get_session "1234567890123456789")
    local name=$(echo "$session" | jq -r '.name')
    
    [ "$name" = "my-project:main" ]
}

@test "register_session stores PID" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="54321"
    
    register_session "1234567890123456789" "test"
    
    local session=$(get_session "1234567890123456789")
    local pid=$(echo "$session" | jq -r '.pid')
    
    [ "$pid" = "54321" ]
}

@test "register_session stores registration timestamp" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "test"
    
    local session=$(get_session "1234567890123456789")
    local registered=$(echo "$session" | jq -r '.registered')
    
    # Should be ISO 8601 format
    [[ "$registered" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "register_session rejects invalid thread ID" {
    export DROID_TTY="/dev/ttys005"
    
    run register_session "invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid thread ID"* ]]
}

@test "register_session rejects invalid TTY" {
    export DROID_TTY="/tmp/fake"
    
    run register_session "1234567890123456789"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid TTY"* ]]
}

@test "register_session updates existing session" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "first-name"
    
    export DROID_TTY="/dev/ttys006"
    register_session "1234567890123456789" "second-name"
    
    local session=$(get_session "1234567890123456789")
    local tty=$(echo "$session" | jq -r '.tty')
    local name=$(echo "$session" | jq -r '.name')
    
    [ "$tty" = "/dev/ttys006" ]
    [ "$name" = "second-name" ]
}

@test "register_session handles empty name" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" ""
    
    local session=$(get_session "1234567890123456789")
    [ "$session" != "null" ]
}

# =============================================================================
# deregister_session() tests
# =============================================================================

@test "deregister_session removes existing session" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "test-session"
    deregister_session "1234567890123456789"
    
    run get_session "1234567890123456789"
    [ "$output" = "null" ]
}

@test "deregister_session is idempotent" {
    deregister_session "9999999999999999999"
    deregister_session "9999999999999999999"
    
    # Should not error
    [ $? -eq 0 ]
}

@test "deregister_session preserves other sessions" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1111111111111111111" "session1"
    register_session "2222222222222222222" "session2"
    
    deregister_session "1111111111111111111"
    
    local session1=$(get_session "1111111111111111111")
    local session2=$(get_session "2222222222222222222")
    
    [ "$session1" = "null" ]
    [ "$session2" != "null" ]
}

# =============================================================================
# list_sessions() tests
# =============================================================================

@test "list_sessions shows empty message when no sessions" {
    run list_sessions
    [[ "$output" == *"No sessions"* ]] || [[ "$output" == *"Registered sessions"* ]]
}

@test "list_sessions shows registered sessions" {
    create_test_session "1234567890123456789" "/dev/ttys005"
    
    run list_sessions
    [[ "$output" == *"1234567890123456789"* ]]
    [[ "$output" == *"ttys005"* ]]
}

# =============================================================================
# get_pid_start_time() tests
# =============================================================================

@test "get_pid_start_time returns time for current process" {
    run get_pid_start_time "$$"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "get_pid_start_time fails for invalid PID" {
    run get_pid_start_time "999999999"
    [ "$status" -ne 0 ] || [ -z "$output" ]
}

@test "get_pid_start_time fails for non-numeric PID" {
    run get_pid_start_time "abc"
    [ "$status" -eq 1 ]
}

@test "get_pid_start_time fails for empty PID" {
    run get_pid_start_time ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# is_same_process() tests
# =============================================================================

@test "is_same_process returns true for current process" {
    local start_time
    start_time=$(get_pid_start_time "$$")
    
    run is_same_process "$$" "$start_time"
    [ "$status" -eq 0 ]
}

@test "is_same_process returns false for wrong start time" {
    run is_same_process "$$" "wrong_time"
    [ "$status" -eq 1 ]
}

@test "is_same_process returns false for null start time" {
    run is_same_process "$$" "null"
    [ "$status" -eq 1 ]
}

@test "is_same_process returns false for empty start time" {
    run is_same_process "$$" ""
    [ "$status" -eq 1 ]
}

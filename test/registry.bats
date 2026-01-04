#!/usr/bin/env bats
# Tests for lib/registry.sh

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

@test "validate_thread_id accepts valid Discord snowflake" {
    run validate_thread_id "1234567890123456789"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id accepts 17-digit ID" {
    run validate_thread_id "12345678901234567"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id accepts 20-digit ID" {
    run validate_thread_id "12345678901234567890"
    [ "$status" -eq 0 ]
}

@test "validate_thread_id rejects short ID" {
    run validate_thread_id "123456"
    [ "$status" -eq 1 ]
}

@test "validate_thread_id rejects non-numeric" {
    run validate_thread_id "abc123"
    [ "$status" -eq 1 ]
}

@test "validate_tty accepts valid TTY" {
    run validate_tty "/dev/ttys001"
    [ "$status" -eq 0 ]
}

@test "validate_tty rejects invalid path" {
    run validate_tty "/tmp/fake"
    [ "$status" -eq 1 ]
}

@test "init_registry creates empty sessions file" {
    rm -f "$SESSIONS_FILE"
    init_registry
    
    [ -f "$SESSIONS_FILE" ]
    local content=$(cat "$SESSIONS_FILE")
    [ "$content" = '{"sessions":{}}' ]
}

@test "get_session returns null for unknown thread" {
    run get_session "9999999999999999999"
    [ "$output" = "null" ]
}

@test "register and get session works" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "test-session"
    
    local session=$(get_session "1234567890123456789")
    local tty=$(echo "$session" | jq -r '.tty')
    local name=$(echo "$session" | jq -r '.name')
    
    [ "$tty" = "/dev/ttys005" ]
    [ "$name" = "test-session" ]
}

@test "deregister_session removes session" {
    export DROID_TTY="/dev/ttys005"
    export DROID_SESSION_PID="12345"
    
    register_session "1234567890123456789" "test-session"
    deregister_session "1234567890123456789"
    
    run get_session "1234567890123456789"
    [ "$output" = "null" ]
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

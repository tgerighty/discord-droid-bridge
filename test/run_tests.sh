#!/bin/bash
# Run all BATS tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo "BATS not found. Install with: brew install bats-core"
    exit 1
fi

echo "Running discord-droid-bridge tests..."
echo ""

# Run all .bats files
bats "$SCRIPT_DIR"/*.bats

echo ""
echo "All tests passed!"

#!/bin/sh
# Build the harness against the worktree's converter sources.
R="$(cd "$(dirname "$0")/../../../.." && pwd)/Sources/BrowserCore/ContentBlocking"
D="${ADBLOCK_SCRATCH:?Set ADBLOCK_SCRATCH to a scratch folder}/swiftharness"
mkdir -p "$D"
swiftc -O -o "$D/h" "$R/ContentRule.swift" "$R/FilterListConverter.swift" "$(dirname "$0")/main.swift"

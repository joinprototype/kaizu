#!/bin/bash
# Import a redacted Arc workspace, then verify the saved session in a fresh process.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d "${TMPDIR:-/tmp}/kaizu-switching.XXXXXXXX")
touch "$root/.switching-trial"
export KAIZU_SUPPORT="$root/support"
run_phase() {
    local phase=$1
    shift
    KAIZU_SWITCH_PHASE="$phase" swift test --scratch-path "$root/build" "$@" --filter ArcSwitchingTests
}
cleanup() {
    local result=$?
    if [[ -f "$KAIZU_SUPPORT/session.json" ]]; then
        run_phase cleanup --skip-build || result=1
    fi
    rm -rf "$root"
    exit "$result"
}
trap cleanup EXIT
run_phase seed
run_phase restart --skip-build

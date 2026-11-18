#!/bin/bash
set -euo pipefail

if [[ "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then
    echo "This release check requires a disposable GitHub-hosted account" >&2
    exit 1
fi

# Both WebRTC peers and the relay run on this Mac. The release fixture runs in a disposable account.
scratch=$(mktemp -d)
export KAIZU_TEST_TURN_PASSWORD
KAIZU_TEST_TURN_PASSWORD=$(openssl rand -hex 24)
turnserver -n --listening-ip=127.0.0.1 --relay-ip=127.0.0.1 --listening-port=3478 \
    --no-udp --no-tls --no-tcp-relay --no-cli --no-multicast-peers \
    --allow-loopback-peers --denied-peer-ip=0.0.0.0-255.255.255.255 --allowed-peer-ip=127.0.0.1 \
    --lt-cred-mech --realm=kaizu.test --user="kaizu-test:$KAIZU_TEST_TURN_PASSWORD" \
    --userdb="$scratch/turn.sqlite" --pidfile="$scratch/turn.pid" --log-file=stdout > "$scratch/relay.log" 2>&1 &
relay_pid=$!
trap 'kill "$relay_pid" 2>/dev/null || true; wait "$relay_pid" 2>/dev/null || true' EXIT
for ((i = 0; i < 50; i++)); do
    if ! kill -0 "$relay_pid" 2>/dev/null; then
        echo "TURN server exited before accepting connections" >&2
        exit 1
    fi
    if nc -z 127.0.0.1 3478 2>/dev/null; then break; fi
    sleep 0.1
done
nc -z 127.0.0.1 3478

fixture="$(dirname "$0")/check-release-launch.py"
export KAIZU_TEST_CLICK_HELPER="$scratch/click-test-call"
swiftc "$(dirname "$0")/click-test-call.swift" -o "$KAIZU_TEST_CLICK_HELPER"
export KAIZU_TEST_VIDEO_SOURCE=frames
session="$HOME/Library/Application Support/Kaizu"
[[ ! -e "$session" ]]
failures=0
round=0
for order in "immediate delay click" "click immediate delay" "delay click immediate"; do
    round=$((round + 1))
    for mode in $order; do
        result=0
        echo "Starting round=$round mode=$mode"
        KAIZU_TEST_CALL_START="$mode" python3 "$fixture" "$1" --media-call || result=$?
        echo "Result round=$round mode=$mode status=$result"
        if [[ "$result" != 0 ]]; then failures=$((failures + 1)); fi
        osascript -e 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'
        for attempt in {1..60}; do
            if ! pgrep -x Kaizu >/dev/null; then break; fi
            sleep .25
        done
        if pgrep -x Kaizu >/dev/null; then exit 1; fi
        if [[ -d "$session" ]]; then mv "$session" "$scratch/session-$round-$mode"; fi
    done
done
echo "$failures of nine H.264 checks failed"
[[ "$failures" == 0 ]]

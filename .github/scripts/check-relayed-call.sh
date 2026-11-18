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
if python3 "$fixture" "$1" --media-call; then
    exit 0
else
    result=$?
    [[ $result == 75 ]] || exit "$result"
fi

osascript -e 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'
swiftc -parse-as-library "$(dirname "$0")/check-webkit-call.swift" -o "$scratch/webkit-control"
if python3 "$fixture" "$scratch/webkit-control" --webkit-control; then
    echo "Plain WebKit captured canvas video on the same runner; the packaged browser failed" >&2
    exit 1
else
    result=$?
    [[ $result == 75 ]] || exit "$result"
fi

echo "Both canvas sources stalled before encoding. Checking decoded video from generated frames on the same relay."
KAIZU_TEST_VIDEO_SOURCE=frames python3 "$fixture" "$1" --media-call
KAIZU_TEST_VIDEO_SOURCE=frames python3 "$fixture" "$scratch/webkit-control" --webkit-control

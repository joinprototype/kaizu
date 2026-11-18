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
swiftc -parse-as-library "$(dirname "$0")/check-webkit-call.swift" -o "$scratch/webkit-control"
export KAIZU_TEST_VIDEO_SOURCE=frames
failures=0
trial() {
    local client="$1" codec="$2" round="$3" binary option outcome
    case "$client" in
        candidate) binary="$candidate_app"; option=--media-call ;;
        master) binary="$master_app"; option=--media-call ;;
        webkit) binary="$scratch/webkit-control"; option=--webkit-control ;;
    esac
    echo "Starting round=$round client=$client codec=$codec"
    outcome=0
    KAIZU_TEST_VIDEO_CODEC="$codec" python3 "$fixture" "$binary" "$option" || outcome=$?
    echo "Result round=$round client=$client codec=$codec status=$outcome"
    if [[ "$outcome" != 0 ]]; then failures=$((failures + 1)); fi
    if [[ "$client" != webkit ]]; then
        osascript -e 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'
        for attempt in {1..60}; do
            if ! pgrep -x Kaizu >/dev/null; then break; fi
            sleep .25
        done
        if pgrep -x Kaizu >/dev/null; then exit 1; fi
        if [[ -d "$session" ]]; then mv "$session" "$scratch/session-$round-$client-$codec"; fi
    fi
}
candidate_app="$1"
master_app="$2"
session="$HOME/Library/Application Support/Kaizu"
[[ ! -e "$session" ]]
for codec in default vp8; do
    for client in candidate webkit master; do trial "$client" "$codec" 1; done
done
for codec in vp8 default; do
    for client in master webkit candidate; do trial "$client" "$codec" 2; done
done
echo "$failures of twelve generated-video checks failed"
[[ "$failures" == 0 ]]

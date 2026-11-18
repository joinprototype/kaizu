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
session="$HOME/Library/Application Support/Kaizu"
install="$RUNNER_TEMP/matched-install"
mkdir "$install"
[[ ! -e "$session" ]]
trial() {
    local client="$1" pixels="$2" round="$3" binary option outcome
    if [[ "$client" == webkit ]]; then
        binary="$scratch/webkit-control"
        option=--webkit-control
    else
        ditto -x -k "$RUNNER_TEMP/$client.zip" "$install"
        binary="$install/Kaizu.app"
        codesign --verify --deep --strict "$binary"
        shasum -a 256 "$binary/Contents/MacOS/Kaizu"
        option=--media-call
    fi
    echo "Starting round=$round client=$client pixels=$pixels"
    outcome=0
    KAIZU_TEST_PIXEL_FORMAT="$pixels" python3 "$fixture" "$binary" "$option" || outcome=$?
    echo "Result round=$round client=$client pixels=$pixels status=$outcome"
    if [[ "$outcome" != 0 ]]; then failures=$((failures + 1)); fi
    if [[ "$client" != webkit ]]; then
        osascript -e 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'
        for attempt in {1..60}; do
            if ! pgrep -x Kaizu >/dev/null; then break; fi
            sleep .25
        done
        if pgrep -x Kaizu >/dev/null; then exit 1; fi
        mv "$binary" "$scratch/retired-$round-$client-$pixels.app"
        if [[ -d "$session" ]]; then mv "$session" "$scratch/session-$round-$client-$pixels"; fi
    fi
}
for pixels in RGBA NV12; do
    for client in parent candidate webkit; do trial "$client" "$pixels" 1; done
done
for pixels in NV12 RGBA; do
    for client in webkit candidate parent; do trial "$client" "$pixels" 2; done
done
echo "$failures of twelve H.264 checks failed"
[[ "$failures" == 0 ]]

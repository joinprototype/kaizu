#!/bin/bash
# Try a real self-update with your own clicks, on a throwaway copy of Kaizu.
#   scripts/try-update.sh         builds build 1 and a signed build 2, then opens build 1
#   scripts/try-update.sh clean   removes everything it made
# The copy has its own bundle id and data folder, so your Kaizu stays out of it.
set -euo pipefail
cd "$(dirname "$0")/.."

id=com.joinprototype.kaizu.qa
root="$HOME/Library/Caches/kaizu-try-update"
app="$root/Applications/Kaizu.app"
port=8742
key="${KAIZU_UPDATE_KEY:-$HOME/.config/kaizu/update-signing.key}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

clean() {
    # Only when it's running: telling a closed app to quit launches it first.
    if pgrep -f "$app/Contents/MacOS/" >/dev/null; then
        osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true
        sleep 2
    fi
    if [ -f "$root/server.pid" ]; then kill "$(cat "$root/server.pid")" 2>/dev/null || true; fi
    "$lsregister" -u "$app" 2>/dev/null || true
    "$lsregister" -u "$root/next/Kaizu.app" 2>/dev/null || true
    defaults delete "$id" 2>/dev/null || true
    rm -rf "$root" "$HOME/Library/WebKit/$id" "$HOME/Library/Caches/$id" "$HOME/Library/Preferences/$id.plist"
}

if [ "${1:-}" = clean ]; then
    clean
    echo "Removed the test copy."
    exit 0
fi

[ -r "$key" ] || { echo "No update signing key at $key" >&2; exit 1; }
clean
mkdir -p "$root/Applications" "$root/next" "$root/feed"

# Debug builds only: a release build ignores these settings and would use your real data.
# They sit in Info.plist because Restart relaunches through `open`, which drops shell variables.
prepare() { # <app> <version> <build>
    local plist="$1/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "$id" "$plist"
    plutil -replace CFBundleShortVersionString -string "$2" "$plist"
    plutil -replace CFBundleVersion -string "$3" "$plist"
    plutil -replace LSEnvironment -json "{\"KAIZU_SUPPORT\":\"$root/support\",\"KAIZU_UPDATE_FEED\":\"http://127.0.0.1:$port/version.json\"}" "$plist"
    codesign --force --sign - "$1" 2>/dev/null
}

make app APP="$app" >/dev/null
prepare "$app" 0.1.0 1
ditto "$app" "$root/next/Kaizu.app"
prepare "$root/next/Kaizu.app" 0.1.1 2
ditto -c -k --keepParent "$root/next/Kaizu.app" "$root/feed/update.zip"
signature=$(swift scripts/update-sign.swift sign "$key" "$root/feed/update.zip" 2)
cat > "$root/feed/version.json" <<JSON
{"version":"0.1.1","build":2,"url":"http://127.0.0.1:$port/version.json","archive":"http://127.0.0.1:$port/update.zip","signature":"$signature"}
JSON

nohup python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root/feed" >/dev/null 2>&1 &
echo $! > "$root/server.pid"
sleep 1
open "$app"

cat <<EOF

Kaizu 0.1.0 is open. This copy has its own data, so it starts empty.

1. In about 10 seconds a pill says "Kaizu 0.1.1 is ready" for 30 seconds. Click Restart.
   If you miss it: Kaizu > Check for Updates..., then Restart.
2. Kaizu closes and reopens by itself. Kaizu > About Kaizu should say 0.1.1.

To try install-on-quit instead, run this script again and quit with Cmd-Q at step 1.
When you're done: scripts/try-update.sh clean
EOF

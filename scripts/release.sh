#!/bin/bash
# Builds a release of Kaizu for download and for its self-update.
#   scripts/release.sh 0.1.1
# Bumps the version in Info.plist, then writes the DMG, the signed update zip
# and version.json into site/. Deploy with: cd site && npx wrangler deploy
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh <version>}"
# Installed copies only update from builds signed with this key, so keep it backed up.
key="${KAIZU_UPDATE_KEY:-$HOME/.config/kaizu/update-signing.key}"
[ -r "$key" ] || { echo "No update signing key at $key" >&2; exit 1; }
plist=Resources/Info.plist
current=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist")
current_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$plist")
# Re-running a release keeps its build number; a new version takes the next one.
if [ "$version" = "$current_version" ]; then build=$current; else build=$((current + 1)); fi
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
make app CONFIG=release APP="$work/stage/Kaizu.app" >/dev/null

mkdir -p site/updates
rm -f site/updates/Kaizu-*.zip
zip="site/updates/Kaizu-$version.zip"
ditto -c -k --keepParent "$work/stage/Kaizu.app" "$zip"
signature=$(swift scripts/update-sign.swift sign "$key" "$zip" "$build")

ln -s /Applications "$work/stage/Applications"

rm -f site/Kaizu-*.dmg
dmg="site/Kaizu-$version.dmg"
hdiutil create -quiet -volname Kaizu -srcfolder "$work/stage" -ov -format UDZO -fs HFS+ "$dmg"
hdiutil verify -quiet "$dmg"

cat > site/version.json <<JSON
{"version":"$version","build":$build,"url":"https://kaizu.joinprototype.com/download","archive":"https://kaizu.joinprototype.com/updates/$(basename "$zip")","signature":"$signature"}
JSON
printf '/download /%s 302\n' "$(basename "$dmg")" > site/_redirects
sed -i '' -E "s/(\"softwareVersion\": \"|[Vv]ersion )[0-9]+\.[0-9]+\.[0-9]+/\1$version/" site/index.html
echo "Kaizu $version (build $build): $dmg, $(du -h "$dmg" | cut -f1); $zip, $(du -h "$zip" | cut -f1)"

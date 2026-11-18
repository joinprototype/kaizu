#!/bin/bash
# Prepare the Mac download, the signed update and their site metadata.
set -euo pipefail
cd "$(dirname "$0")/.."

notarize=false
if [[ ${1:-} == --notarize ]]; then
    notarize=true
    shift
fi
if [[ $# != 1 || ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: scripts/release.sh [--notarize] <major.minor.patch>" >&2
    exit 2
fi
version=$1
if $notarize; then
    : "${KAIZU_DEVELOPER_ID:?Set the Developer ID Application signing identity}"
    : "${KAIZU_NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
fi
key="${KAIZU_UPDATE_KEY:-$HOME/.config/kaizu/update-signing.key}"
[ -r "$key" ] || { echo "No update signing key at $key" >&2; exit 1; }

# Work on a fresh source copy because SwiftPM embeds Info.plist in the binary.
# A failed build or submission leaves the previous release ready to deploy.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/source" "$work/stage"
cp -R Makefile Package.swift Resources Sources Tests "$work/source/"
plist="$work/source/Resources/Info.plist"
build=$(plutil -extract CFBundleVersion raw "$plist")
if [[ $version != "$(plutil -extract CFBundleShortVersionString raw "$plist")" ]]; then
    build=$((build + 1))
fi
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"
make -C "$work/source" app CONFIG=release >/dev/null
app="$work/stage/Kaizu.app"
mv "$work/source/build/Kaizu.app" "$app"

notarize_and_staple() {
    local submission=$1 target=$2 receipt="$work/notary.plist"
    if ! xcrun notarytool submit "$submission" --keychain-profile "$KAIZU_NOTARY_PROFILE" \
            --wait --output-format plist > "$receipt"; then
        cat "$receipt" >&2
        return 1
    fi
    local id status
    id=$(plutil -extract id raw "$receipt")
    status=$(plutil -extract status raw "$receipt")
    echo "Apple notarization $id: $status"
    if [[ $status != Accepted ]]; then
        echo "Inspect submission $id with xcrun notarytool log." >&2
        return 1
    fi
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
}

if $notarize; then
    codesign --force --sign "$KAIZU_DEVELOPER_ID" --options runtime --timestamp \
        --entitlements Resources/Kaizu.entitlements "$app"
    codesign --verify --strict -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
    ditto -c -k --keepParent "$app" "$work/submission.zip"
    notarize_and_staple "$work/submission.zip" "$app"
    spctl --assess --type execute "$app"
fi
codesign --verify --strict "$app"

# The updater verifies these exact bytes, including the app's stapled ticket.
zip="Kaizu-$version.zip"
dmg="Kaizu-$version.dmg"
ditto -c -k --keepParent "$app" "$work/$zip"
signature=$(swift scripts/update-sign.swift sign "$key" "$work/$zip" "$build")
ln -s /Applications "$work/stage/Applications"
hdiutil create -quiet -volname Kaizu -srcfolder "$work/stage" -format UDZO -fs HFS+ "$work/$dmg"
if $notarize; then
    codesign --sign "$KAIZU_DEVELOPER_ID" --timestamp "$work/$dmg"
    notarize_and_staple "$work/$dmg" "$work/$dmg"
    spctl --assess --type open --context context:primary-signature "$work/$dmg"
fi
hdiutil verify -quiet "$work/$dmg"

cat > "$work/version.json" <<JSON
{"version":"$version","build":$build,"url":"https://kaizu.joinprototype.com/download","archive":"https://kaizu.joinprototype.com/updates/$zip","signature":"$signature"}
JSON
printf '/download /%s 302\n' "$dmg" > "$work/redirects"
sed -E "s/(\"softwareVersion\": \"|[Vv]ersion )[0-9]+\.[0-9]+\.[0-9]+/\1$version/" site/index.html > "$work/index.html"

mkdir -p site/updates
mv "$work/$zip" "site/updates/$zip"
mv "$work/$dmg" "site/$dmg"
mv "$work/redirects" site/_redirects
mv "$work/index.html" site/index.html
mv "$plist" Resources/Info.plist
mv "$work/version.json" site/version.json
for previous in site/Kaizu-*.dmg site/updates/Kaizu-*.zip; do
    case "$previous" in
        "site/$dmg"|"site/updates/$zip") ;;
        *) rm -f "$previous" ;;
    esac
done
echo "Kaizu $version (build $build): site/$dmg, site/updates/$zip"

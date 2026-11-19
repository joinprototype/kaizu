#!/bin/bash
# Build the committed revision for local daily-use testing.
set -euo pipefail
cd "$(dirname "$0")/.."
revision=$(git rev-parse HEAD)
name="Kaizu-trial-${revision:0:7}.dmg"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/source" "$work/stage"
git archive "$revision" Makefile Package.swift Resources Sources Tests | tar -x -C "$work/source"
plutil -insert KaizuSourceRevision -string "$revision" "$work/source/Resources/Info.plist"
make -C "$work/source" app CONFIG=release
mv "$work/source/build/Kaizu.app" "$work/stage/"
codesign --verify --strict "$work/stage/Kaizu.app"
ln -s /Applications "$work/stage/Applications"
hdiutil create -quiet -volname Kaizu -srcfolder "$work/stage" -format UDZO -fs HFS+ "$work/$name"
hdiutil verify -quiet "$work/$name"
mkdir -p build
mv "$work/$name" "build/$name"
shasum -a 256 "build/$name"

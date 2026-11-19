#!/bin/bash
# Rebuilds Kaizu's autoconsent files from a published @duckduckgo/autoconsent
# release (see Resources/Scripts/README.md). Needs node and npm.
#   scripts/vendor-autoconsent.sh 16.61.0
set -euo pipefail
version=${1:?usage: $0 <autoconsent version>}
esbuild=0.28.2
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

npm pack --silent --pack-destination "$work" "@duckduckgo/autoconsent@$version" >/dev/null
tar -xzf "$work"/duckduckgo-autoconsent-*.tgz -C "$work"
package="$work/package"
scripts=Resources/Scripts

# v1: the standalone build, rules included, for the page's own world.
cp "$package/dist/autoconsent.standalone.js" "$scripts/autoconsent.js"
cp "$package/LICENSE" "$scripts/autoconsent-LICENSE.txt"
# v2: the library alone plus our glue, for the isolated world. The app keeps
# the rules and the eval snippets and hands each frame only what it needs.
cp scripts/autoconsent/content.js "$work/content.js"
npx --yes "esbuild@$esbuild" "$work/content.js" --bundle --format=iife --target=es2021 \
    --minify-whitespace --minify-syntax --legal-comments=none --log-level=warning \
    --outfile="$scripts/autoconsent-isolated.js"
cp "$package/rules/compact-rules.json" "$scripts/autoconsent-rules.json"
node scripts/autoconsent/snippets.cjs "$package" > "$scripts/autoconsent-snippets.json"
node scripts/autoconsent/parity.cjs "$package" > Tests/BrowserCoreTests/Fixtures/autoconsent-filter-parity.json

ls -l "$scripts"/autoconsent*

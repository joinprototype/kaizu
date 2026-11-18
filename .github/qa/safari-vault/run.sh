#!/bin/bash
set -euo pipefail
[[ "$RUNNER_ENVIRONMENT" == github-hosted ]]
root="$RUNNER_TEMP/vault-test"
curl --fail --location --retry 3 --silent --show-error -o "$root/Bitwarden.dmg" https://github.com/bitwarden/clients/releases/download/desktop-v2026.10.2/Bitwarden-2026.10.2-universal.dmg
(cd "$root" && echo 'f507ff8a5d9a65da787f0eec2a69443133485e951ea93909ce42aed6a2bb5f21  Bitwarden.dmg' | shasum -a 256 -c)
mkdir "$root/mounted"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$root/mounted" "$root/Bitwarden.dmg"
codesign --verify --strict "$root/mounted/Bitwarden.app/Contents/PlugIns/safari.appex"
# Include the UI driver only in this scratch build. Production app code is unchanged.
python3 - <<'PY'
from pathlib import Path
p=Path('Sources/Kaizu/App/DebugHooks.swift')
s=p.read_text()
marker='        case "extension":'
assert s.count(marker)==1
p.write_text(s.replace(marker,Path('.github/qa/safari-vault/hook.swift').read_text()+marker))
PY
make app
cp .github/qa/safari-vault/flow.js build/Kaizu.app/Contents/Resources/VaultQA.js
codesign --force --sign - build/Kaizu.app
export NSUnbufferedIO=YES KAIZU_DEBUG=safari-vault-acceptance KAIZU_SUPPORT="$root/kaizu" KAIZU_EXTENSION="$root/mounted/Bitwarden.app"
python3 - <<'PY'
import subprocess
subprocess.run(["build/Kaizu.app/Contents/MacOS/Kaizu"],timeout=170,check=True)
PY

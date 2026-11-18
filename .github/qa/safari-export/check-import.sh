#!/bin/bash
set -euo pipefail
[[ "$RUNNER_ENVIRONMENT" == github-hosted ]]
export KAIZU_IMPORT
KAIZU_IMPORT=$(python3 - <<'PY'
from pathlib import Path
paths = [p for name in ('Downloads','Desktop','Documents') for p in (Path.home()/name).glob('*.zip')]
assert len(paths) == 1, f"Expected one Safari export, found {len(paths)}"
print(paths[0])
PY
)
before=$(shasum -a 256 "$KAIZU_IMPORT")
# Add fixture assertions to the existing QA entry point for this runner build.
python3 - <<'PY'
from pathlib import Path
p=Path('Sources/Kaizu/App/DebugHooks.swift')
s=p.read_text()
def insert(anchor, extra):
    global s
    assert s.count(anchor) == 1
    s=s.replace(anchor,anchor+'\n'+extra)
insert('let pinnedBefore = space.pinned.count', '''                let expected = URL(string: "http://127.0.0.1:18784/")!
                precondition(data.visits.contains { $0.url == expected })
                precondition(!space.pinnedAddresses.contains(expected))''')
insert('log("toast \\(store.toast?.message ?? "none")")','''                let rows = await store.history?.recent(profile: profile) ?? []
                precondition(rows.contains { $0.url == expected } && space.pinnedAddresses.contains(expected))
                precondition(space.pinned.folders.last?.isExpanded == false)
                precondition(data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses) == nil)''')
insert('log("after undo \\(left) pages, pinned \\(space.pinned.count)")','''                let afterUndo = await store.history?.recent(profile: profile) ?? []
                precondition(!afterUndo.contains { $0.url == expected } && !space.pinnedAddresses.contains(expected))
                precondition(space.pinned.count == pinnedBefore && space.today.contains(moved))
                print("Safari-created history and bookmark verified in preview, storage, repeat preview and Undo")
                NSApp.terminate(nil)''')
p.write_text(s)
PY
make app > "$RUNNER_TEMP/kaizu-build.log" 2>&1 || { tail -30 "$RUNNER_TEMP/kaizu-build.log"; exit 1; }
export NSUnbufferedIO=YES KAIZU_SUPPORT="$RUNNER_TEMP/kaizu-safari-import" KAIZU_DEBUG=browsingdata
python3 - <<'PY'
import subprocess
subprocess.run(["build/Kaizu.app/Contents/MacOS/Kaizu"],check=True,timeout=60)
PY
[[ "$before" == "$(shasum -a 256 "$KAIZU_IMPORT")" ]]
echo 'Safari archive SHA-256 unchanged after import and Undo.'

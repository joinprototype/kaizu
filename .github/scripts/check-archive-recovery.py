"""Exercise archive reopening and abrupt process loss in a disposable Kaizu session."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


def identifier():
    return str(uuid.uuid4()).upper()


def space(name, profile):
    return dict(id=identifier(), name=name, profileID=profile, symbol="circle", hue=0.5, today=[], pinned=[])


def entry(title, destination):
    tab = dict(id=identifier(), url="about:blank#same-page", title="Same page", customTitle=title)
    return dict(tab=tab, spaceID=destination["id"], archivedAt="2026-01-01T00:00:00Z")


def main():
    binary = Path(sys.argv[1]).resolve(strict=True)
    if b"KAIZU_SUPPORT" not in binary.read_bytes():
        raise SystemExit("This fixture requires a debug build with scratch session support")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        profiles = [dict(id=identifier(), name=name, favorites=[]) for name in ("Personal", "Client")]
        home, work, client = (space("Home", profiles[0]["id"]), space("Work", profiles[0]["id"]),
                              space("Client", profiles[1]["id"]))
        saved = dict(schemaVersion=2, activeSpaceID=home["id"], isSidebarVisible=True,
                     sidebarWidth=248, profiles=profiles, spaces=[home, work, client])
        session = root / "session.json"
        archive = root / "archive.json"
        session.write_text(json.dumps(saved))
        rows = [entry("Quarterly notes", work), entry("Other profile", client)]
        archive.write_text(json.dumps(rows))

        def launch(mode):
            env = dict(os.environ, KAIZU_SUPPORT=directory, KAIZU_DEBUG=mode)
            subprocess.run([binary], env=env, check=True, timeout=60)

        launch("archive-interrupt")
        persisted = json.loads(session.read_text())
        restored = next(s for s in persisted["spaces"] if s["id"] == work["id"])
        if [t.get("customTitle") for t in restored["today"]] != ["Quarterly notes"]:
            raise SystemExit("Reopened tab missing from the saved Work space after process loss")
        if json.loads(archive.read_text()) != [rows[1]]:
            raise SystemExit("Expected only the other profile's tab in the legacy archive")
        # A crash after the session commit but before the compatibility copy can leave its old rows behind.
        archive.write_text(json.dumps(rows))
        launch("archive-restored")
        if json.loads(archive.read_text()) != [rows[1]]:
            raise SystemExit("The recovered archive was not available to an older build on quit")
        damaged = b"[incomplete archived entry"
        archive.write_bytes(damaged)
        launch("archive-restored")
        originals = list(root.glob("archive.unreadable-*.json"))
        if len(originals) != 1 or originals[0].read_bytes() != damaged or json.loads(archive.read_text()) != [rows[1]]:
            raise SystemExit("The damaged legacy archive did not survive repair")
        launch("archive-sweep-interrupt")
        swept = json.loads(session.read_text())
        current_work = next(s for s in swept["spaces"] if s["id"] == work["id"])
        after_sweep = swept["archivedTabs"]
        if [t.get("customTitle") for t in current_work["today"]] != ["Quarterly notes"]:
            raise SystemExit("Interrupted sweep left the stale tab in the workspace")
        if (len(after_sweep) != 2 or after_sweep[0]["spaceID"] != work["id"] or
                after_sweep[0]["tab"]["url"] != "about:blank#stale" or after_sweep[1] != rows[1]):
            raise SystemExit("Unexpected archived entries after interrupted sweep")
        if json.loads(archive.read_text()) != after_sweep or "#private" in session.read_text():
            raise SystemExit("Legacy archive mismatch or private tab in the regular session")
        print("Interrupted sweep kept the stale tab only in the archive and excluded the private tab.")
        print("Interrupted reopen preserved the tab, original space and profile, and other profile's archived entry.")


if __name__ == "__main__":
    main()

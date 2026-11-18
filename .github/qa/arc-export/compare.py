import json
import os
import subprocess
import sys
import time
from pathlib import Path

if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Requires a disposable GitHub-hosted Mac")
app, chooser, root = [Path(arg).resolve(strict=True) for arg in sys.argv[1:]]
record = Path.home() / "Library/Application Support/Kaizu/session.json"
if record.parent.exists():
    raise SystemExit("Expected a new Kaizu account")
work = "# Inbox\n## Clients\n- https://work.example.test/brief\n- https://work.example.test/projects\n"
personal = "# Inbox\n## Home\n- https://personal.example.test/calendar\n"
extra = "- https://work.example.test/new-brief\n"
source = root / "Arc Data Export.md"
if os.environ["READER"] not in ("before", "fixed"):
    raise SystemExit("Unknown candidate")

def launch():
    return subprocess.Popen(["open", "-n", "-W", "-a", str(app)])

def quit_app(process):
    subprocess.run(["osascript", "-e", 'tell application id "com.joinprototype.kaizu" to quit'], timeout=30, check=True)
    if process.wait(timeout=30):
        raise SystemExit("The packaged browser did not quit cleanly")

def choose(content, expected, action):
    source.write_text(content)
    script = """tell application "System Events"
        repeat 60 times
            if exists menu item "Import from Arc…" of menu "File" of menu bar 1 of process "Kaizu" then exit repeat
            delay 0.2
        end repeat
        tell process "Kaizu"
            set frontmost to true
            click menu item "Import from Arc…" of menu "File" of menu bar 1
        end tell
    end tell"""
    subprocess.run(["osascript", "-e", script], timeout=25, check=True)
    subprocess.run([chooser, source, expected, action], timeout=45, check=True)
    if source.read_text() != content:
        raise SystemExit("Import changed the source export")

def snapshot(expanded):
    result = {}
    for space in json.loads(record.read_text())["spaces"]:
        if space["name"] != "Inbox":
            continue
        folders = [item["folder"] for item in space["pinned"]]
        assert len(folders) == 1
        folder = folders[0]
        tabs = [item["tab"] for item in folder["children"]]
        result[folder["name"]] = (space["id"],space["profileID"],folder["id"],[(t["id"],t["pinnedURL"]) for t in tabs])
    expected = {"Clients":["https://work.example.test/brief","https://work.example.test/projects"],
                "Home":["https://personal.example.test/calendar"]}
    if expanded:
        expected["Clients"].append("https://work.example.test/new-brief")
    assert {k:[url for _,url in v[3]] for k,v in result.items()} == expected
    assert len({v[1] for v in result.values()}) == 2
    return result

def wait_for_snapshot(expanded):
    deadline = time.monotonic()+8
    while True:
        try:
            return snapshot(expanded)
        except (AssertionError, KeyError, FileNotFoundError, json.JSONDecodeError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(.1)

process = launch()
try:
    choose(work+personal, "Import 3 Tabs", "apply")
    original = wait_for_snapshot(False)
finally:
    quit_app(process)
assert snapshot(False) == original
process = launch()
try:
    if os.environ["READER"] == "before":
        choose(personal+work, "Import 3 Tabs", "cancel")
        print("Reproduced three spurious additions on the unchanged but reordered export.", flush=True)
    else:
        choose(personal+work, "Nothing New", "cancel")
        choose(personal+work+extra, "Import 1 Tab", "apply")
        changed = wait_for_snapshot(True)
        assert changed["Home"] == original["Home"]
        assert changed["Clients"][:3] == original["Clients"][:3]
        assert changed["Clients"][3][:-1] == original["Clients"][3]
        subprocess.run([chooser, source, "Undo", "undo"], timeout=12, check=True)
        assert wait_for_snapshot(False) == original
finally:
    quit_app(process)
assert snapshot(False) == original
print("Cold restart, profile and folder identity, original pin IDs and source contents verified.", flush=True)

"""Separate failures in an immediate quit from failures introduced by replacing an app."""
import importlib.util
import json
import os
import secrets
import subprocess
import uuid
from http.server import HTTPServer
from pathlib import Path

if os.getenv("RUNNER_ENVIRONMENT") != "github-hosted" or os.getenv("CI") != "true":
    raise SystemExit("Requires a disposable GitHub-hosted account")
scratch = Path(os.environ["RUNNER_TEMP"]) / "upgrade-comparison"
scratch.mkdir()
support = Path.home() / "Library/Application Support/Kaizu"
if support.exists():
    raise SystemExit("Expected a clean test account")

spec = importlib.util.spec_from_file_location("launch_fixture", Path(".github/scripts/check-release-launch.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
published = scratch.parent / "published.zip"
candidate = scratch.parent / "candidate/Kaizu.zip"
settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)

def checkpoint(profile, server):
    directory = Path.home() / "Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore" / str(uuid.UUID(profile))
    cookie_path = directory / "Cookies/Cookies.binarycookies"
    cookie = cookie_path.exists() and server.cookie.split("=", 1)[1].encode() in cookie_path.read_bytes()
    tokens = [server.storage_token.encode(encoding) for encoding in ("ascii", "utf-16-le", "utf-16-be")]
    files = [p for p in directory.rglob("*") if p.is_file() and "LocalStorage" in p.parts]
    present = False
    for path in files:
        try:
            data = path.read_bytes()
        except FileNotFoundError:
            continue
        present |= any(token in data for token in tokens)
    print(f"After quit on disk: cookie marker={cookie}, local storage marker={present}, local storage files={len(files)}")

def trial(folder, before, after):
    # Keep the path fixed between launches, including the same-version controls.
    subprocess.run(["ditto", "-x", "-k", before, folder], check=True)
    app = folder / "Kaizu.app"
    subprocess.run(["codesign", "--verify", "--strict", app], check=True)
    with HTTPServer(("127.0.0.1", 0), fixture.Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        server.storage_token = secrets.token_hex(16)
        server.check_first_page_blocking = False
        url = f"http://127.0.0.1:{server.server_port}/start"
        fixture.quit_app(fixture.launch(server, app, url))
        identity = fixture.saved_tab(url)
        checkpoint(identity[0], server)
        if before != after:
            app.rename(folder / "Retired.app")
            subprocess.run(["ditto", "-x", "-k", after, folder], check=True)
            subprocess.run(["codesign", "--verify", "--strict", app], check=True)
        server.issue_cookie = False
        fixture.quit_app(fixture.launch(server, app))
        if fixture.saved_tab(url) != identity:
            raise SystemExit("Tab or profile identity changed")
        return "cookie and local storage restored"

failed = False
for round_number in range(1, 4):
    for name, before, after in (("published-to-published", published, published),
                                ("published-to-candidate", published, candidate),
                                ("candidate-to-candidate", candidate, candidate)):
        print(f"Trial {round_number} {name}", flush=True)
        folder = scratch / f"{round_number}-{name}"
        folder.mkdir()
        try:
            outcome = trial(folder, before, after)
        except SystemExit as error:
            outcome = str(error)
            failed = True
        print(f"Result {round_number} {name}: {outcome}", flush=True)
        subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'], check=True, timeout=30)
        if support.exists():
            support.rename(folder / "test-profile")
if failed:
    raise SystemExit("At least one quit/restore or upgrade trial failed")

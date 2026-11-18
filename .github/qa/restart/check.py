"""Exercise the menu and relaunch on a fresh hosted macOS desktop."""
import hashlib
from http.server import HTTPServer
import importlib.util
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

if os.getenv("GITHUB_ACTIONS") != "true" or os.getenv("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Requires a disposable GitHub-hosted account")
root = Path(os.environ["RUNNER_TEMP"])
support = Path.home() / "Library/Application Support/Kaizu"
if support.exists():
    raise SystemExit("Expected an unused browser profile")

spec = importlib.util.spec_from_file_location("fixture", ".github/scripts/check-release-launch.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
app = root / "restart/Kaizu.app"
executable = Path("Contents/MacOS/Kaizu")
helper = root / "click-restart"
subprocess.run(["codesign", "--verify", "--strict", app], check=True)
subprocess.run(["plutil", "-replace", "CFBundleVersion", "-string", "0", app / "Contents/Info.plist"], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", app], check=True)
settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)

with HTTPServer(("127.0.0.1", 0), fixture.Page) as server:
    server.timeout = 0.5
    server.check_first_page_blocking = False
    server.cookie = "qa_restart=" + secrets.token_hex(16)
    server.storage_token = secrets.token_hex(16)
    server.issue_cookie = True
    url = f"http://127.0.0.1:{server.server_port}/start"
    process = fixture.launch(server, app, url)
    staged = fixture.staged_release(process)
    target = fixture.bundle_info(staged)
    digest = hashlib.sha256((staged / executable).read_bytes()).digest()
    original = fixture.saved_tab(url)
    first_pid = subprocess.check_output([helper, app, "pid"], text=True).strip()
    server.issue_cookie = False
    server.rendered = False
    server.page_failure = None
    server.challenge = secrets.token_hex(12)
    subprocess.run([helper, app, "click"], check=True, timeout=40)
    # No open command after the click. Only the updater can relaunch Kaizu.
    deadline = time.monotonic() + 90
    while not server.rendered:
        if server.page_failure:
            raise SystemExit(server.page_failure)
        if time.monotonic() >= deadline:
            raise SystemExit("The update did not reopen the saved page")
        server.handle_request()
    next_pid = subprocess.check_output([helper, app, "pid"], text=True).strip()
    if first_pid == next_pid:
        raise SystemExit("Expected a new browser process after Restart")
    subprocess.run(["codesign", "--verify", "--strict", app], check=True)
    if fixture.bundle_info(app)["CFBundleVersion"] != target["CFBundleVersion"] or hashlib.sha256((app / executable).read_bytes()).digest() != digest:
        raise SystemExit("Relaunched executable differs from the verified staged release")
    subprocess.run(["osascript","-e",'tell application id "com.joinprototype.kaizu" to quit'],check=True,timeout=30)
    if fixture.saved_tab(url) != original:
        raise SystemExit("Restored profile, space or tab identity changed")
    print(f"Restart relaunched signed Kaizu {target['CFBundleShortVersionString']} (build {target['CFBundleVersion']}) with its saved tab, HTTP-only cookie and local storage.")

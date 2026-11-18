"""Compare immediate quit with quit after the generated value reaches persistent storage."""
import importlib.util
import plistlib
import secrets
import subprocess
import tempfile
import time
import uuid
from http.server import HTTPServer
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("launch", here.parents[1] / "scripts/check-release-launch.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def build_control(directory, bundle_id):
    app = directory / "StorageControl.app/Contents"
    binary = app / "MacOS/StorageControl"
    binary.parent.mkdir(parents=True)
    subprocess.run(["swiftc", "-swift-version", "6", str(here / "main.swift"), "-o", str(binary)], check=True)
    info = dict(CFBundleName="WebKit Storage Control", CFBundleExecutable=binary.name,
                CFBundlePackageType="APPL", CFBundleVersion="1", CFBundleIdentifier=bundle_id)
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
    return binary


def wait_for_page(server, process):
    deadline = time.monotonic() + 40
    while not server.rendered and not server.page_failure:
        if process.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError("Control exited or timed out before the page responded")
        server.handle_request()


def trial(binary, bundle_id, wait_for_commit):
    profile = uuid.uuid4()
    directory = Path.home() / "Library/WebKit" / bundle_id / "WebsiteDataStore" / str(profile)
    with HTTPServer(("127.0.0.1", 0), fixture.Page) as server:
        url = f"http://127.0.0.1:{server.server_port}/start"
        server.timeout = 0.2
        server.storage_token = secrets.token_hex(16)
        server.navigation_cookie = "nav=" + secrets.token_hex(16)
        server.cookie = "login=" + secrets.token_hex(16)
        server.check_first_page_blocking = False

        for initial in (True, False):
            server.issue_cookie = initial
            server.rendered = False
            server.page_failure = server.first_storage_failure = None
            server.missing_probes = 0
            server.document_missing_lax = False
            server.challenge = secrets.token_hex(12)
            process = subprocess.Popen([str(binary), str(profile), url])
            try:
                wait_for_page(server, process)
                if initial and server.page_failure:
                    raise RuntimeError(server.page_failure)
                if initial:
                    start = time.monotonic()
                    state = fixture.storage_checkpoint(directory, server.storage_token)
                    print(f"After the site confirmed its write: {state}", flush=True)
                    if wait_for_commit:
                        while state != "value matches" and time.monotonic() - start < 15:
                            time.sleep(0.025)
                            state = fixture.storage_checkpoint(directory, server.storage_token)
                        if state != "value matches":
                            raise RuntimeError("No committed value appeared within 15 seconds")
                        print(f"Commit observed after {time.monotonic() - start:.3f}s", flush=True)
                subprocess.run(["osascript", "-e", f'tell application id "{bundle_id}" to quit'], check=True, timeout=15)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("Control did not quit cleanly")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
            print("After writer quit:" if initial else "After reader quit:",
                  fixture.storage_checkpoint(directory, server.storage_token), flush=True)
        return server.page_failure or "match"


with tempfile.TemporaryDirectory(prefix="kaizu-webkit-storage-") as scratch:
    identifier = "dev.kaizu.qa.webkit-storage." + uuid.uuid4().hex
    binary = build_control(Path(scratch), identifier)
    failures = 0
    for number in range(1, 7):
        for mode in ("immediate", "committed"):
            print(f"Trial {number} {mode}", flush=True)
            outcome = trial(binary, identifier, wait_for_commit=mode == "committed")
            print(f"Result {number} {mode}: {outcome}", flush=True)
            failures += outcome != "match"
    if failures:
        raise SystemExit(f"{failures} restores failed")

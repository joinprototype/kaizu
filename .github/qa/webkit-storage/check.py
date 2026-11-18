"""Compare immediate quit with quit after the generated value reaches persistent storage."""
import importlib.util
import json
import os
import selectors
import threading
import plistlib
import secrets
import subprocess
import tempfile
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/draft":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", self.server.cache_policy)
        self.end_headers()
        marker = json.dumps(self.server.marker)
        previous = json.dumps(self.server.previous)
        write = "localStorage.setItem('upgrade-test', expected);" if self.server.writing else ""
        final_edit = ""
        if self.server.writing and self.server.on_hide:
            final_edit = f"addEventListener('pagehide', () => localStorage.setItem('upgrade-test', {json.dumps(self.server.final)}));"
        self.wfile.write(f"""<!doctype html><title>Draft</title><link rel="icon" href="data:,">
            <script>
            try {{
                const expected = {marker};
                {write}
                {final_edit}
                const saved = localStorage.getItem('upgrade-test');
                webkit.messageHandlers.report.postMessage(
                    saved === expected ? 'match' : saved === null ? 'missing' :
                    saved === {previous} ? 'previous' : 'different');
            }} catch {{ webkit.messageHandlers.report.postMessage('error'); }}
            </script>""".encode())

    def log_message(self, *args):
        pass


def launch(binary, identifier, profile, server, *, writing, mode):
    server.writing = writing
    url = f"http://127.0.0.1:{server.server_port}/draft"
    folder = Path.home() / "Library/WebKit" / identifier / "WebsiteDataStore" / str(profile)
    with subprocess.Popen([str(binary), str(profile), url, mode],
                          stdout=subprocess.PIPE) as app:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(app.stdout, selectors.EVENT_READ)
                if not selector.select(timeout=20):
                    raise RuntimeError("No response from the page")
            outcome = app.stdout.readline().decode().strip()
            if outcome not in {"match", "previous", "different", "missing", "error"}:
                raise RuntimeError(f"Unexpected response from the page: {outcome!r}")
            if mode == "hold":
                if outcome != "match":
                    raise RuntimeError(f"Writer did not acknowledge its value: {outcome}")
                deadline = time.monotonic() + 10
                while fixture.storage_checkpoint(folder, server.marker) != "value matches":
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Timed out waiting for committed value")
                    time.sleep(.025)
                subprocess.run(["osascript", "-e", f'tell application id "{identifier}" to quit'],
                               check=True, timeout=10)
            if app.wait(timeout=10) != 0:
                raise RuntimeError("Test app did not quit normally")
            if mode in {"navigate", "drain"} and app.stdout.read().strip() != b"navigated":
                raise RuntimeError("Quit did not finish the requested navigation")
        finally:
            if app.poll() is None:
                app.terminate()
                app.wait(timeout=10)
    expected = server.final if writing and server.on_hide else server.marker
    state = fixture.storage_checkpoint(folder, expected)
    if state == "value differs" and server.previous is not None:
        if fixture.storage_checkpoint(folder, server.previous) == "value matches":
            state = "previous value"
    return outcome, state


if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Run this window-opening diagnostic on a GitHub Mac runner.")

with tempfile.TemporaryDirectory(prefix="kaizu-storage-navigation-") as scratch:
    identifier = "dev.kaizu.qa.webkit-storage." + uuid.uuid4().hex
    binary = build_control(Path(scratch), identifier)
    failures = {}
    for number in range(1, 7):
        for mode, on_hide in (("quit", False), ("navigate", False), ("drain", False),
                              ("navigate", True), ("drain", True)):
            profile = uuid.uuid4()
            with ThreadingHTTPServer(("127.0.0.1", 0), Page) as server:
                thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": .05}, daemon=True)
                thread.start()
                try:
                    server.previous = None
                    server.on_hide = False
                    # Revalidate the reader document even when testing a cacheable writer.
                    server.cache_policy = "no-store"
                    server.marker = secrets.token_hex(16)
                    launch(binary, identifier, profile, server, writing=True, mode="hold")
                    server.previous = server.marker
                    server.marker = secrets.token_hex(16)
                    server.final = secrets.token_hex(16)
                    server.on_hide = on_hide
                    policy = "no-cache" if number % 2 == 0 else "no-store"
                    server.cache_policy = policy
                    writer, disk = launch(binary, identifier, profile, server, writing=True, mode=mode)
                    if writer != "match":
                        raise RuntimeError(f"Writer did not read back its value: {writer}")
                    if on_hide:
                        server.previous, server.marker = server.marker, server.final
                    server.on_hide = False
                    server.cache_policy = "no-store"
                    reader, after = launch(binary, identifier, profile, server, writing=False, mode="quit")
                    label = f"{mode} {'pagehide' if on_hide else 'edit'}"
                    print(f"Trial {number} {label} {policy}: disk={disk}, reader={reader}, final={after}", flush=True)
                    if disk != "value matches" or reader != "match" or after != "value matches":
                        failures[label] = failures.get(label, 0) + 1
                finally:
                    server.shutdown()
                    thread.join()
    print("Failed trials by mode", failures, flush=True)
    if failures:
        raise SystemExit(1)

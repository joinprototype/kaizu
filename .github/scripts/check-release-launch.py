"""Exercise the actual app bundles in a disposable macOS account."""

import argparse
import hashlib
import json
import os
import plistlib
import secrets
import shutil
import subprocess
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        server = self.server
        if self.path == "/start":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            if server.issue_cookie:
                self.send_header("Set-Cookie", server.cookie + "; Max-Age=3600; Path=/; HttpOnly; SameSite=Strict")
            self.end_headers()
            storage_check = ""
            if getattr(server, "storage_token", None):
                # Only the original app may create the marker. The restored page must read it.
                seed = "localStorage.setItem('upgrade-test', marker);" if server.issue_cookie else ""
                storage_check = f"""
                    try {{
                        const marker = {json.dumps(server.storage_token)};
                        {seed}
                        headers['X-Kaizu-Storage'] = localStorage.getItem('upgrade-test') === marker ? 'match' : 'missing';
                    }} catch {{
                        headers['X-Kaizu-Storage'] = 'unavailable';
                    }}
                """
            blocker_probe = ""
            if server.check_first_page_blocking:
                blocker_probe = '<script src="/ads/cbr.js"></script><script src="/launch-control.js"></script>'
            self.wfile.write(f"""<!doctype html><title>Kaizu launch test</title><link rel="icon" href="data:,">
                <body><h1>Ready</h1>{blocker_probe}<script>
                const headers = {{}};
                {storage_check}
                if ({json.dumps(server.check_first_page_blocking)} && !window.launchControl) throw Error("Control script did not run");
                if (document.querySelector('h1').textContent === 'Ready') fetch('/{server.challenge}', {{headers}});
                </script></body>""".encode())
        elif self.path == "/ads/cbr.js":
            # This script path matches a bundled EasyList rule.
            server.page_failure = "The first page reached a blocked script before the rule lists were installed"
            self.send_error(403)
        elif self.path == "/launch-control.js":
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript")
            self.end_headers()
            self.wfile.write(b"window.launchControl = true;")
        elif self.path == "/" + server.challenge:
            cookie_matches = server.cookie in self.headers.get("Cookie", "").split("; ")
            storage = self.headers.get("X-Kaizu-Storage", "unreported")
            check_storage = bool(getattr(server, "storage_token", None))
            if not cookie_matches or (check_storage and storage != "match"):
                phase = "initial launch" if server.issue_cookie else "restored launch"
                server.page_failure = (f"{phase}: login cookie {'match' if cookie_matches else 'missing'}, "
                                       f"local storage {storage if check_storage else 'not checked'}")
                self.send_error(403)
                return
            self.send_response(204)
            self.end_headers()
            server.rendered = True
        elif self.path == "/media-call/ice":
            config = {"iceServers": []}
            password = os.environ.get("KAIZU_TEST_TURN_PASSWORD")
            if password:
                config = {"iceTransportPolicy": "relay", "iceServers": [{
                    "urls": "turn:127.0.0.1:3478?transport=tcp", "username": "kaizu-test", "credential": password
                }]}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(json.dumps(config).encode())
        elif self.path in ("/media-call", "/media-call?codec=vp8"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(Path(__file__).with_name("check-media-call.html").read_bytes())
        elif self.path.startswith(("/media-call/failure?", "/extension-test/failure?")):
            server.page_failure = self.path
            self.send_response(204)
            self.end_headers()
        elif self.path.startswith("/extension-test/"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<!doctype html><title>Extension window check</title>")
        else:
            self.send_response(404)
            self.end_headers()


def launch(server, app, *urls):
    process = subprocess.Popen(["open", "-W", "-n", "-a", str(app), *urls])
    wait_for_page(server, process, app)
    return process


def wait_for_page(server, process, app):
    server.rendered = False
    server.page_failure = None
    server.challenge = secrets.token_hex(12)
    deadline = time.monotonic() + 90
    while not server.rendered:
        if process.poll() is not None:
            raise SystemExit(f"{app} exited before rendering the page")
        if server.page_failure:
            raise SystemExit(server.page_failure)
        if time.monotonic() >= deadline:
            raise SystemExit("Timed out waiting for Kaizu to render the page")
        server.handle_request()


def quit_app(process):
    subprocess.run(["osascript", "-e", 'tell application id "com.joinprototype.kaizu" to quit'],
                   check=True, timeout=30)
    if process.wait(timeout=30) != 0:
        raise SystemExit("Kaizu did not quit cleanly")


def saved_tab(url):
    session = Path.home() / "Library/Application Support/Kaizu/session.json"
    record = json.loads(session.read_text())
    matches = [(space["profileID"], space["id"], tab["id"]) for space in record["spaces"]
               for tab in space["today"] if tab["url"] == url]
    if len(matches) != 1:
        raise SystemExit(f"Expected one saved test tab, found {len(matches)}")
    return matches[0]


def bundle_info(app):
    with (app / "Contents/Info.plist").open("rb") as info:
        return plistlib.load(info)


def staged_release(process):
    cache = Path.home() / "Library/Caches/com.joinprototype.kaizu/Updates"
    predicate = 'subsystem == "com.joinprototype.kaizu" AND category == "updates"'
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline and process.poll() is None:
        for staged in cache.glob("*/unpacked/Kaizu.app"):
            # Extraction starts before validation finishes. Wait for the updater
            # to confirm the signature, bundle and build and enable install-on-quit.
            build = staged.parent.parent.name
            if not build.isdecimal():
                continue
            ready = f' AND eventMessage == "Update {build} staged"'
            logs = subprocess.check_output(["/usr/bin/log", "show", "--last", "5m", "--style", "compact",
                                            "--predicate", predicate + ready], text=True, timeout=20)
            if any(line.endswith(f" Update {build} staged") for line in logs.splitlines()):
                return staged
        time.sleep(1)
    subprocess.run(["/usr/bin/log", "show", "--last", "5m", "--style", "compact", "--predicate", predicate],
                   timeout=20)
    raise SystemExit("The app did not stage a signed release from the production feed")


def install_signed_update(server, app, url):
    # Only this disposable bundle advertises build zero. The updater, feed
    # URL and embedded verification key are from the candidate release binary.
    subprocess.run(["plutil", "-replace", "CFBundleVersion", "-string", "0", str(app / "Contents/Info.plist")],
                   check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", "--preserve-metadata=flags,runtime,entitlements",
                    str(app)], check=True)
    process = launch(server, app, url)
    staged = staged_release(process)
    info = bundle_info(staged)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    executable = Path("Contents/MacOS/Kaizu")
    digest = hashlib.sha256((staged / executable).read_bytes()).digest()
    if int(build) <= 0 or info["CFBundleIdentifier"] != "com.joinprototype.kaizu":
        raise SystemExit("The app staged an unexpected release")
    quit_app(process)

    # The detached install helper replaces the bundle after the original PID exits.
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            if bundle_info(app)["CFBundleVersion"] == build:
                break
        except FileNotFoundError:
            pass
        time.sleep(0.25)
    else:
        raise SystemExit("Quitting did not install the staged release")
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    if hashlib.sha256((app / executable).read_bytes()).digest() != digest:
        raise SystemExit("The installed executable differs from the verified staged release")
    print(f"The candidate's updater installed signed release {version} (build {build}) on quit.")


def install_test_extension():
    extension_id = str(uuid.uuid4()).upper()
    folder = Path.home() / "Library/Application Support/Kaizu/Extensions" / extension_id
    folder.mkdir(parents=True)
    manifest = {"manifest_version": 2, "name": "Window selection check", "version": "1.0",
                "permissions": ["tabs", "http://127.0.0.1/*"], "background": {"scripts": ["background.js"]}}
    (folder / "manifest.json").write_text(json.dumps(manifest))
    shutil.copyfile(Path(__file__).with_name("check-extension-windows.js"), folder / "background.js")
    records = [{"id": extension_id, "kind": "folder", "path": str(folder)}]
    subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "installedExtensions", "-data",
                    json.dumps(records).encode().hex()], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("previous", type=Path, nargs="?")
    mode.add_argument("--signed-update", action="store_true")
    mode.add_argument("--extension-windows", action="store_true")
    mode.add_argument("--media-call", action="store_true")
    mode.add_argument("--webkit-control", action="store_true")
    args = parser.parse_args()
    candidate = args.candidate.resolve(strict=True)
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        server.storage_token = secrets.token_hex(16) if args.previous or args.signed_update else None
        url = f"http://127.0.0.1:{server.server_port}/start"
        server.check_first_page_blocking = not (args.previous or args.signed_update or args.extension_windows or args.media_call or args.webkit_control)
        if args.webkit_control:
            process = subprocess.Popen([candidate, f"http://127.0.0.1:{server.server_port}/media-call"])
            try:
                wait_for_page(server, process, candidate)
                print("The plain WebKit control rendered video, decoded audio and echoed the message.")
            finally:
                process.terminate()
                process.wait(timeout=10)
            return
        if server.check_first_page_blocking:
            launch(server, candidate, url)
            print("On the first external page, WebKit blocked the matching script and ran the control script with cookies.")
            return

        if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
            raise SystemExit("This test requires a disposable GitHub-hosted runner account")
        # Open the test link as a saved tab using the app's current-space setting.
        settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
        subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
        if args.media_call:
            suffix = "?codec=vp8" if os.environ.get("KAIZU_TEST_VIDEO_CODEC") == "vp8" else ""
            quit_app(launch(server, candidate, f"http://127.0.0.1:{server.server_port}/media-call{suffix}"))
            print("The receiving WebRTC peer decoded non-silent audio, rendered video and echoed a data-channel message.")
            return
        if args.extension_windows:
            install_test_extension()
            quit_app(launch(server, candidate, f"http://127.0.0.1:{server.server_port}/extension-test/first"))
            print("The extension activated a background tab in its owning window and preserved the other selection.")
            return
        if args.signed_update:
            install_signed_update(server, candidate, url)
            installed = candidate
        else:
            installed = args.previous.resolve(strict=True)
            quit_app(launch(server, installed, url))
            installed.rename(installed.with_name("Retired.app"))
            candidate.rename(installed)

        before = saved_tab(url)
        server.issue_cookie = False
        # No URL is passed. Only the restored tab can request the new challenge.
        quit_app(launch(server, installed))
        if saved_tab(url) != before:
            raise SystemExit("The profile, space or tab identity changed across the upgrade")
        print("Restored the tab in its original space and profile with its login cookie and local storage.")


if __name__ == "__main__":
    main()

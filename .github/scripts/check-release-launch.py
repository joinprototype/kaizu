"""Exercise the actual app bundles in a disposable macOS account."""

import argparse
import hashlib
import json
import os
import plistlib
import secrets
import subprocess
import time
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
            self.wfile.write(f"""<!doctype html><title>Kaizu launch test</title><link rel="icon" href="data:,">
                <body><h1>Ready</h1><script>
                if (document.querySelector('h1').textContent === 'Ready') fetch('/{server.challenge}');
                </script></body>""".encode())
        elif self.path == "/" + server.challenge:
            if server.cookie not in self.headers.get("Cookie", "").split("; "):
                self.send_error(403)
                server.missing_cookie = True
                return
            self.send_response(204)
            self.end_headers()
            server.rendered = True
        else:
            self.send_response(404)
            self.end_headers()


def launch(server, app, *urls):
    server.rendered = False
    server.missing_cookie = False
    server.challenge = secrets.token_hex(12)
    process = subprocess.Popen(["open", "-W", "-n", "-a", str(app), *urls])
    deadline = time.monotonic() + 90
    while not server.rendered:
        if process.poll() is not None:
            raise SystemExit(f"{app} exited before rendering the page")
        if server.missing_cookie:
            raise SystemExit("The page loaded without the expected login cookie")
        if time.monotonic() >= deadline:
            raise SystemExit("Timed out waiting for Kaizu to render the page")
        server.handle_request()
    return process


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
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("previous", type=Path, nargs="?")
    mode.add_argument("--signed-update", action="store_true")
    args = parser.parse_args()
    candidate = args.candidate.resolve(strict=True)
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        url = f"http://127.0.0.1:{server.server_port}/start"
        if args.previous is None and not args.signed_update:
            launch(server, candidate, url)
            print("Release app opened the external link and WebKit executed the page with cookies.")
            return

        if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
            raise SystemExit("The upgrade test requires a disposable GitHub-hosted runner account")
        # Open the test link as a saved tab using the app's current-space setting.
        settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
        subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
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
        print("Restored the tab in its original space and profile with its login cookie.")


if __name__ == "__main__":
    main()

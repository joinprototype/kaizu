"""Exercise the actual app bundles in a disposable macOS account."""

import json
import os
import secrets
import subprocess
import sys
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
            self.wfile.write(f"""<!doctype html><title>Kaizu launch test</title>
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
            self.send_error(404)


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


def main():
    candidate = Path(sys.argv[1]).resolve(strict=True)
    previous = Path(sys.argv[2]).resolve(strict=True) if len(sys.argv) == 3 else None
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        url = f"http://127.0.0.1:{server.server_port}/start"
        if previous is None:
            launch(server, candidate, url)
            print("Release app opened the external link and WebKit executed the page with cookies.")
            return

        if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
            raise SystemExit("The upgrade test requires a disposable GitHub-hosted runner account")
        # Open the test link as a saved tab using the app's current-space setting.
        settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
        subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
        quit_app(launch(server, previous, url))
        before = saved_tab(url)

        previous.rename(previous.with_name("Retired.app"))
        candidate.rename(previous)
        server.issue_cookie = False
        # No URL is passed. Only the restored tab can request the new challenge.
        quit_app(launch(server, previous))
        if saved_tab(url) != before:
            raise SystemExit("The profile, space or tab identity changed across the upgrade")
        print("Restored the v0.2.5 tab in its original space and profile with its login cookie.")


if __name__ == "__main__":
    main()

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
            if not server.issue_cookie and getattr(server, "storage_token", None):
                received = server.cookie in self.headers.get("Cookie", "").split("; ")
                print(f"Restored document request included the test cookie: {received}", flush=True)
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
            self.wfile.write(f"""<!doctype html><title>Kaizu launch test</title><link rel="icon" href="data:,">
                <body><h1>Ready</h1><script>
                const headers = {{}};
                {storage_check}
                async function checkLogin() {{
                    for (const delay of [0, 1000, 4000, 10000]) {{
                        if (delay) await new Promise(resolve => setTimeout(resolve, delay));
                        const result = await fetch('/{server.challenge}', {{headers, cache: 'no-store'}});
                        if (result.status !== 202) return;
                    }}
                }}
                if (document.querySelector('h1').textContent === 'Ready') checkLogin();
                </script></body>""".encode())
        elif self.path == "/" + server.challenge:
            cookie_matches = server.cookie in self.headers.get("Cookie", "").split("; ")
            storage = self.headers.get("X-Kaizu-Storage", "unreported")
            check_storage = bool(getattr(server, "storage_token", None))
            if not server.issue_cookie and not cookie_matches and storage == "match" and server.missing_probes < 3:
                server.missing_probes += 1
                print(f"Restored login cookie missing on probe {server.missing_probes}, local storage matched", flush=True)
                self.send_response(202)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            if server.missing_probes and cookie_matches:
                server.page_failure = f"Restored login cookie appeared only after {server.missing_probes} failed probes"
                self.send_error(403)
                return
            if not cookie_matches or (check_storage and storage != "match"):
                phase = "initial launch" if server.issue_cookie else "restored launch"
                server.page_failure = (f"{phase}: login cookie {'match' if cookie_matches else 'missing'}, "
                                       f"local storage {storage if check_storage else 'not checked'}")
                self.send_error(403)
                return
            self.send_response(204)
            self.end_headers()
            server.rendered = True
        elif self.path == "/media-call":
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
    server.rendered = False
    server.page_failure = None
    server.missing_probes = 0
    server.challenge = secrets.token_hex(12)
    process = subprocess.Popen(["open", "-W", "-n", "-a", str(app), *urls])
    deadline = time.monotonic() + 90
    while not server.rendered:
        if process.poll() is not None:
            raise SystemExit(f"{app} exited before rendering the page")
        if server.page_failure:
            raise SystemExit(server.page_failure)
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


def report_cookie_checkpoint(server, path, phase):
    # This file belongs to the generated profile in a disposable hosted account.
    # Report only whether the fixture's random value appears in WebKit's on-disk file.
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        status = "no cookie file"
    except OSError as error:
        status = f"file unavailable ({error.errno})"
    else:
        token = server.cookie.partition("=")[2].encode()
        status = f"fixture marker {'present' if token in data else 'absent'} in {len(data)} bytes"
    print(f"Cookie checkpoint {phase}: {status}", flush=True)


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
    try:
        profile_id = str(uuid.UUID(saved_tab(url)[0]))
    except (FileNotFoundError, SystemExit):
        profile_id = None   # The throttled session save may still be pending.
    cookie_root = Path.home() / "Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore"
    if profile_id:
        report_cookie_checkpoint(server, cookie_root / profile_id / "Cookies/Cookies.binarycookies", "before quit")
    quit_app(process)
    profile_id = str(uuid.UUID(saved_tab(url)[0]))
    cookie_file = cookie_root / profile_id / "Cookies/Cookies.binarycookies"
    report_cookie_checkpoint(server, cookie_file, "after quit")

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
    report_cookie_checkpoint(server, cookie_file, "after bundle swap")
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
    args = parser.parse_args()
    candidate = args.candidate.resolve(strict=True)
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        server.storage_token = secrets.token_hex(16) if args.previous or args.signed_update else None
        url = f"http://127.0.0.1:{server.server_port}/start"
        if args.previous is None and not (args.signed_update or args.extension_windows or args.media_call):
            launch(server, candidate, url)
            print("Release app opened the external link and WebKit executed the page with cookies.")
            return

        if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
            raise SystemExit("This test requires a disposable GitHub-hosted runner account")
        # Open the test link as a saved tab using the app's current-space setting.
        settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
        subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
        if args.media_call:
            quit_app(launch(server, candidate, f"http://127.0.0.1:{server.server_port}/media-call"))
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

"""Exercise the actual app bundles in a disposable macOS account."""

import argparse
import hashlib
import json
import os
import plistlib
import secrets
import shutil
import sqlite3
import subprocess
import time
import uuid
from contextlib import closing
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class Page(BaseHTTPRequestHandler):
    # An idle WebKit preconnection must return control to the launch deadline.
    timeout = 3

    def request_recheck(self):
        self.send_response(202)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def check_login(self):
        server = self.server
        cookies = self.headers.get("Cookie", "").split("; ")
        strict = server.cookie in cookies
        lax = server.navigation_cookie in cookies if server.navigation_cookie else None
        storage = self.headers.get("X-Kaizu-Storage", "unreported")
        cookies_match = strict and lax is not False
        storage_matches = not server.storage_token or storage == "match"
        if cookies_match and storage_matches and not server.document_missing_lax and not server.failed_probes:
            self.send_response(204)
            self.end_headers()
            server.rendered = True
            return

        observation = f"page Strict={strict}, Lax={lax}, local storage={storage}"
        server.failed_probes.append(observation)
        probe = len(server.failed_probes)
        phase = "initial" if server.issue_cookie else "restored"
        print(f"{phase} login probe {probe}: {observation}", flush=True)
        if not server.issue_cookie and probe == 1 and getattr(server, "cookie_file", None):
            report_cookie_checkpoint(server, server.cookie_file, "at first failed page check")

        # The first failed read is final. Later requests show whether WebKit
        # eventually supplied the cookies or the draft while the same page was open.
        retry_cookies = not cookies_match and probe < 4
        retry_storage = not storage_matches and probe == 1
        if not server.issue_cookie and (retry_cookies or retry_storage):
            self.request_recheck()
            return
        server.page_failure = (f"{phase} login: first document missing Lax={server.document_missing_lax}; "
                               + " then ".join(server.failed_probes))
        self.send_error(403)

    def do_GET(self):
        server = self.server
        if self.path == "/start":
            if not server.issue_cookie and server.navigation_cookie:
                cookies = self.headers.get("Cookie", "").split("; ")
                strict = server.cookie in cookies
                lax = server.navigation_cookie in cookies
                print(f"Restored document cookies: Lax={lax}, Strict={strict}", flush=True)
                if not lax:
                    server.document_missing_lax = True
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            if server.issue_cookie:
                self.send_header("Set-Cookie", server.cookie + "; Max-Age=3600; Path=/; HttpOnly; SameSite=Strict")
                if server.navigation_cookie:
                    self.send_header("Set-Cookie", server.navigation_cookie + "; Max-Age=3600; Path=/; HttpOnly; SameSite=Lax")
            self.end_headers()
            storage_check = ""
            if getattr(server, "storage_token", None):
                # Only the original app may create the marker. The restored page must read it.
                seed = "localStorage.setItem('upgrade-test', marker);" if server.issue_cookie else ""
                storage_check = f"""
                    try {{
                        const marker = {json.dumps(server.storage_token)};
                        {seed}
                        const value = localStorage.getItem('upgrade-test');
                        if (value === null) headers['X-Kaizu-Storage'] = 'missing';
                        else headers['X-Kaizu-Storage'] = value === marker ? 'match' : 'different';
                    }} catch {{
                        headers['X-Kaizu-Storage'] = 'unavailable';
                    }}
                """
            save_on_exit = ""
            if getattr(server, "last_edit", None):
                save_on_exit = f"addEventListener('pagehide', () => localStorage.setItem('upgrade-test', {json.dumps(server.last_edit)}), {{once:true}});"
            blocker_probe = ""
            if server.check_first_page_blocking:
                blocker_probe = '<script src="/ads/cbr.js"></script><script src="/launch-control.js"></script>'
            self.wfile.write(f"""<!doctype html><title>Kaizu launch test</title><link rel="icon" href="data:,">
                <body><h1>Ready</h1>{blocker_probe}<script>
                {save_on_exit}
                if ({json.dumps(server.check_first_page_blocking)} && !window.launchControl) throw Error("Control script did not run");
                async function checkLogin() {{
                    for (const delay of [0, 1000, 4000, 10000]) {{
                        if (delay) await new Promise(resolve => setTimeout(resolve, delay));
                        const headers = {{}};
                        {storage_check}
                        const result = await fetch('/{server.challenge}', {{headers, cache: 'no-store'}});
                        if (result.status !== 202) return;
                    }}
                }}
                if (document.querySelector('h1').textContent === 'Ready') checkLogin();
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
            self.check_login()
        elif self.path == "/media-call/video-source.js":
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript")
            self.end_headers()
            self.wfile.write(Path(__file__).with_name("check-video-source.js").read_bytes())
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
        elif self.path.partition("?")[0] == "/media-call":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(Path(__file__).with_name("check-media-call.html").read_bytes())
        elif self.path.startswith(("/media-call/failure?", "/media-call/canvas-stall?", "/extension-test/failure?")):
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
    server.failed_probes = []
    server.document_missing_lax = False
    server.challenge = secrets.token_hex(12)
    deadline = time.monotonic() + 90
    while not server.rendered:
        if process.poll() is not None:
            raise SystemExit(f"{app} exited before rendering the page")
        if server.page_failure:
            if server.page_failure.startswith("/media-call/canvas-stall?"):
                print(server.page_failure, flush=True)
                raise SystemExit(75)  # The relay wrapper compares this result with plain WebKit.
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
                if (staged.parent.parent / "update.zip").exists():
                    raise SystemExit("The updater retained the downloaded ZIP after staging the verified app")
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
        strict = server.cookie.partition("=")[2].encode() in data
        lax = server.navigation_cookie.partition("=")[2].encode() in data
        status = f"Strict={strict}, Lax={lax}, {len(data)} bytes"
    print(f"Cookie checkpoint {phase}: {status}", flush=True)


def storage_checkpoint(profile_directory, marker):
    # Query the committed row, including its WAL. Deleted rows can still leave marker bytes on disk.
    if not profile_directory.is_dir():
        return "profile directory unavailable"
    expected = (marker, marker.encode("ascii"), marker.encode("utf-16-le"), marker.encode("utf-16-be"))
    results = []
    for database in sorted(profile_directory.rglob("localstorage.sqlite3")):
        try:
            with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=0)) as connection:
                row = connection.execute("SELECT value FROM ItemTable WHERE key = ?", ("upgrade-test",)).fetchone()
        except sqlite3.Error as error:
            results.append(f"unreadable ({type(error).__name__})")
            continue
        if row is None:
            results.append("key absent")
        elif row[0] in expected:
            results.append("value matches")
        else:
            results.append("value differs")
    return ", ".join(results) if results else "no local storage database found"


def seed_legacy_session(server, app, url, stores):
    # v0.2.5 can exit after acknowledging a write but before WebKit commits it.
    process = launch(server, app, url)
    state = "waiting for saved tab"
    cookie_file = None
    try:
        deadline = time.monotonic() + 30
        while process.poll() is None and time.monotonic() < deadline:
            try:
                profile, _, _ = saved_tab(url)
            except (FileNotFoundError, SystemExit):
                pass  # The original app saves its new tab asynchronously.
            else:
                profile_directory = stores / str(uuid.UUID(profile))
                cookie_file = profile_directory / "Cookies/Cookies.binarycookies"
                state = storage_checkpoint(profile_directory, server.storage_token)
                if "value matches" in state.split(", "):
                    print("Confirmed the source value in the v0.2.5 profile before quit.", flush=True)
                    return
            time.sleep(.05)
        raise SystemExit(f"v0.2.5 did not commit the acknowledged value: {state}")
    finally:
        if cookie_file:
            report_cookie_checkpoint(server, cookie_file, "before v0.2.5 quit")
        if process.poll() is None:
            quit_app(process)
        if cookie_file:
            report_cookie_checkpoint(server, cookie_file, "after v0.2.5 quit")


def check_restored_session(server, installed, url, identity, profile_directory):
    before_launch = storage_checkpoint(profile_directory, server.storage_token)
    cookie_file = profile_directory / "Cookies/Cookies.binarycookies"
    server.cookie_file = cookie_file
    report_cookie_checkpoint(server, cookie_file, "before restored launch")
    print("Before restored launch:", before_launch, flush=True)
    # No URL is passed. Only the restored tab can request the new challenge.
    try:
        quit_app(launch(server, installed))
    finally:
        report_cookie_checkpoint(server, cookie_file, "after restore attempt")
        if server.last_edit:
            print("Shutdown edit after restore attempt:", storage_checkpoint(profile_directory, server.last_edit), flush=True)
        else:
            print("Original draft after restore attempt:", storage_checkpoint(profile_directory, server.storage_token), flush=True)
    if "value matches" not in before_launch.split(", "):
        raise SystemExit(f"Expected draft was absent before the reader launched: {before_launch}")
    if saved_tab(url) != identity:
        raise SystemExit("The profile, space or tab identity changed across the restart")


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
    mode.add_argument("--webkit-control", action="store_true")
    args = parser.parse_args()
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise SystemExit("This test requires a disposable GitHub-hosted runner account")
    candidate = args.candidate.resolve(strict=True)
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.timeout = 1
        server.issue_cookie = True
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        server.storage_token = secrets.token_hex(16) if args.previous or args.signed_update else None
        # A top-level GET can carry Lax even when navigation withholds Strict.
        # The same-site request from the loaded page must carry both.
        server.navigation_cookie = "kaizu_navigation=" + secrets.token_hex(16) if server.storage_token else None
        url = f"http://127.0.0.1:{server.server_port}/start"
        server.last_edit = secrets.token_hex(16) if args.signed_update else None
        server.check_first_page_blocking = not (args.previous or args.signed_update or args.extension_windows or args.media_call or args.webkit_control)
        media_url = f"http://127.0.0.1:{server.server_port}/media-call"
        if os.environ.get("KAIZU_TEST_VIDEO_SOURCE") == "frames":
            media_url += "?source=frames"
        if args.webkit_control:
            process = subprocess.Popen([candidate, media_url])
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

        # Open the test link as a saved tab using the app's current-space setting.
        settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
        subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
        if args.media_call:
            if os.environ.get("KAIZU_TEST_VIDEO_CODEC") == "vp8":
                media_url += ("&" if "?" in media_url else "?") + "codec=vp8"
            quit_app(launch(server, candidate, media_url))
            print("The receiving WebRTC peer decoded non-silent audio, rendered video and echoed a data-channel message.")
            return
        if args.extension_windows:
            install_test_extension()
            quit_app(launch(server, candidate, f"http://127.0.0.1:{server.server_port}/extension-test/first"))
            print("The extension activated a background tab in its owning window and preserved the other selection.")
            return
        stores = Path.home() / "Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore"
        if args.signed_update:
            install_signed_update(server, candidate, url)
            # Only the outgoing page can have saved this edit while quitting.
            server.storage_token = server.last_edit
            server.last_edit = None
            installed = candidate
        else:
            installed = args.previous.resolve(strict=True)
            seed_legacy_session(server, installed, url, stores)
            installed.rename(installed.with_name("Retired.app"))
            candidate.rename(installed)
            # The candidate must both restore the old value and save a distinct edit on its own quit.
            server.last_edit = secrets.token_hex(16)

        before = saved_tab(url)
        profile_directory = stores / str(uuid.UUID(before[0]))
        server.issue_cookie = False
        check_restored_session(server, installed, url, before, profile_directory)
        print("Restored the tab in its original space and profile with its login cookie and local storage.")
        if args.previous:
            server.storage_token = server.last_edit
            server.last_edit = None
            check_restored_session(server, installed, url, before, profile_directory)
            print("The candidate restored its final pagehide edit on the first read after an ordinary quit.")


if __name__ == "__main__":
    main()

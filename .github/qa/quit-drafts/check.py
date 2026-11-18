"""Exercise two regular profiles, the last saved edit and Back across a real app quit."""
import json
import os
import plistlib
import secrets
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def identifier():
    return str(uuid.uuid4()).upper()


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = self.path.strip("/").split("/")
        if len(parts) != 2 or parts[0] not in ("A", "B"):
            self.send_error(404)
            return
        profile, route = parts
        server = self.server
        if route == "edit":
            if not server.edit.wait(60):
                self.send_error(504)
                return
            body = ""
        elif route in ("seeded", "edited", "match", "missing", "previous", "different", "back", "wrong-entry", "storage-error"):
            with server.condition:
                server.events.add((profile, route))
                server.condition.notify_all()
            if server.reading:
                print(f"Reader reported {profile}/{route}", flush=True)
            body = ""
        elif route in ("start", "draft"):
            if server.reading:
                print(f"Reader requested {profile}/{route}", flush=True)
                if route == "draft" and server.first and profile != server.first:
                    # Serve this window only after its peer has already gone Back.
                    # The server is threaded so the peer can request and render normally.
                    with server.condition:
                        earlier_back = server.condition.wait_for(
                            lambda: (server.first, "back") in server.events, timeout=15)
                    print(f"Serving {profile}/draft after peer Back={earlier_back}", flush=True)
                    server.order_observed = earlier_back
            previous, updated, final = (json.dumps(v) for v in server.values[profile])
            if server.reading:
                expected = final if profile == "B" else updated
                js = f"""
                    if (location.pathname.endsWith('/start')) {{
                        fetch('./back');
                    }} else {{
                        let first;
                        try {{ first = localStorage.getItem('draft'); }}
                        catch {{ await fetch('./storage-error'); return; }}
                        const result = first === {expected} ? 'match' : first === null ? 'missing' :
                            first === {previous} ? 'previous' : 'different';
                        addEventListener('popstate', () => fetch(location.pathname.endsWith('/start') ? './back' : './wrong-entry'));
                        await fetch('./' + result);
                        history.back();
                    }}
                """
            else:
                hide = f"addEventListener('pagehide', () => localStorage.setItem('draft', {final}));" if profile == "B" else ""
                js = f"""
                    history.pushState({{}}, '', './draft');
                    localStorage.setItem('draft', {previous});
                    await fetch('./seeded');
                    await fetch('./edit');
                    {hide}
                    localStorage.setItem('draft', {updated});
                    if (localStorage.getItem('draft') === {updated}) await fetch('./edited');
                """
            body = "<!doctype html><title>Draft " + profile + "</title><link rel='icon' href='data:,'><script>(async () => {" + js + "})()</script>"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *args):
        pass


def wait_for(server, predicate, process):
    with server.condition:
        deadline = time.monotonic() + 75
        while not predicate():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError(f"Browser exited or timed out. Observed {sorted(server.events)}")
            server.condition.wait(.1)


def seed(support, origin):
    profiles, spaces, ids = [], [], {}
    for label in ("A", "B"):
        profile, space, tab = (identifier() for _ in range(3))
        ids[label] = profile, space, tab
        profiles.append(dict(id=profile, name=label, favorites=[]))
        spaces.append(dict(id=space, profileID=profile, name=label, symbol="circle", hue=.5,
                           selectedTabID=tab, pinned=[], today=[dict(id=tab, title=label, url=f"{origin}/{label}/start")]))
    _, second, selected = ids["B"]
    extra = dict(activeSpaceID=second, selectedTabIDs=[second, selected], isSidebarVisible=True, sidebarWidth=248)
    record = dict(schemaVersion=2, profiles=profiles, spaces=spaces, activeSpaceID=ids["A"][1],
                  isSidebarVisible=True, sidebarWidth=248, extraWindows=[extra])
    (support / "session.json").write_text(json.dumps(record))
    return ids


def stored(profile, token):
    for path in profile.rglob("localstorage.sqlite3"):
        try:
            with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=.05)) as connection:
                row = connection.execute("SELECT value FROM ItemTable WHERE key=?", ("draft",)).fetchone()
                if row and row[0] in (token, token.encode(), token.encode("utf-16-le"), token.encode("utf-16-be")):
                    return True
        except sqlite3.OperationalError:
            continue
    return False


def trial(app, number):
    bundle = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    assert bundle == "com.joinprototype.kaizu"
    support = Path.home() / "Library/Application Support/Kaizu"
    origin_store = Path.home() / "Library/WebKit" / bundle / "WebsiteDataStore"
    with ThreadingHTTPServer(("127.0.0.1", 0), Page) as server:
        origin = f"http://127.0.0.1:{server.server_port}"
        if number == 1:
            support.mkdir(parents=True, exist_ok=False)
        server.first = (None, "B", "A")[(number - 1) % 3]
        server.order_observed = False
        print(f"Starting trial {number} with two fresh profiles, first Back={server.first or 'unconstrained'}", flush=True)
        ids = seed(support, origin)
        server.values = {key: [secrets.token_hex(16) for _ in range(3)] for key in ids}
        server.condition = threading.Condition()
        server.edit = threading.Event()
        server.events = set()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        outcomes = {}
        try:
            for reading in (False, True):
                server.reading = reading
                with subprocess.Popen([str(app / "Contents/MacOS/Kaizu")]) as proc:
                    try:
                        start = time.monotonic()
                        if reading:
                            states = {"match", "missing", "previous", "different", "storage-error"}
                            wait_for(server, lambda: all(any((label, state) in server.events for state in states) for label in ids), proc)
                            outcomes = {label: next(s for s in states if (label,s) in server.events) for label in ids}
                            wait_for(server, lambda: all((label,"back") in server.events for label in ids), proc)
                            if server.first and not server.order_observed:
                                raise RuntimeError("Both pages reported but the requested navigation order was not observed")
                        else:
                            wait_for(server, lambda: all((label,"seeded") in server.events for label in ids), proc)
                            while not all(stored(origin_store / profile.lower(), server.values[label][0])
                                          for label, (profile, _, _) in ids.items()):
                                if time.monotonic() - start > 90:
                                    raise RuntimeError("Previous drafts did not commit in both profiles")
                                time.sleep(.025)
                            print("Both previous drafts committed", flush=True)
                            server.edit.set()
                            wait_for(server, lambda: all((label,"edited") in server.events for label in ids), proc)
                        subprocess.run(["osascript","-e",f'tell application id "{bundle}" to quit'],check=True,timeout=20)
                        if proc.wait(timeout=15) != 0:
                            raise RuntimeError("Browser did not quit cleanly")
                    except RuntimeError:
                        if reading and proc.poll() is None:
                            window_script = Path(__file__).with_name("window-report.swift")
                            subprocess.run(["swift", str(window_script), str(proc.pid)], timeout=30, check=False)
                            print("Navigation and renderer logs for this synthetic browser:", flush=True)
                            subprocess.run(["/usr/bin/log", "show", "--last", "2m", "--style", "compact",
                                            "--predicate", f'processIdentifier == {proc.pid} AND subsystem == "com.joinprototype.kaizu"'],
                                           timeout=30, check=False)
                        raise
                    finally:
                        if proc.poll() is None:
                            proc.terminate()
                            proc.wait(timeout=10)
                if not reading:
                    record = json.loads((support / "session.json").read_text())
                    first_space = record.get("activeSpaceID")
                    second_windows = record.get("extraWindows") or []
                    print(f"Saved window count after quit: {1 + len(second_windows)}", flush=True)
                    for label,(profile,space,tab) in ids.items():
                        saved = next(s for s in record["spaces"] if s["id"] == space and s["profileID"] == profile)
                        assert any(t["id"] == tab and t["url"] == f"{origin}/{label}/draft" for t in saved["today"]), saved
                        state_bytes = (support / "TabStates" / (tab + ".state")).stat().st_size
                        if first_space == space:
                            shown = saved.get("selectedTabID") == tab
                        else:
                            shown = any(w.get("activeSpaceID") == space and
                                        (space, tab) in zip(w["selectedTabIDs"][::2], w["selectedTabIDs"][1::2])
                                        for w in second_windows)
                        expected = server.values[label][2 if label == "B" else 1]
                        persistent = stored(origin_store / profile.lower(), expected)
                        print(f"After writer quit, {label}: selected in restored window={shown}, "
                              f"history bytes={state_bytes}, latest draft row matches={persistent}", flush=True)
                        assert shown and state_bytes > 0 and persistent, f"Missing saved selection, history or draft for {label}"
            print(f"Trial {number}: normal edit={outcomes['A']}, pagehide edit={outcomes['B']}, both tab histories restored",flush=True)
            return all(s == "match" for s in outcomes.values())
        finally:
            server.edit.set()
            server.shutdown()
            thread.join()


if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Run only on a fresh GitHub-hosted Mac.")
app = Path(sys.argv[1]).resolve(strict=True)
results = [trial(app, n) for n in range(1, 13)]
if not all(results):
    raise SystemExit(f"{results.count(False)} of {len(results)} paired-profile restores failed")

"""Place a bidirectional call between two browser processes on a disposable hosted Mac."""
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"


class PeerPage(BaseHTTPRequestHandler):
    def respond(self, body, mime="application/json", status=200):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # A peer can quit after its final result with a candidate read outstanding.
            pass

    def exchange(self, kind, side, value):
        remote = (kind, "B" if side == "A" else "A")
        with self.server.changed:
            self.server.messages[kind, side] = value
            self.server.changed.notify_all()
            ready = self.server.changed.wait_for(lambda: remote in self.server.messages or self.server.closing, 70)
            answer = self.server.messages.get(remote)
        self.respond(json.dumps(answer).encode(), status=200 if ready and answer is not None else 504)

    def do_GET(self):
        path = urlsplit(self.path).path
        parts = path.strip("/").split("/")
        if (len(parts) == 4 and parts[0] == "ice" and parts[1] in ("A", "B")
                and parts[2] in ("offer", "answer") and parts[3].isdigit()):
            key, cursor = (parts[1], parts[2]), int(parts[3])
            with self.server.changed:
                items = self.server.candidates.setdefault(key, [])
                self.server.changed.wait_for(lambda: len(items) > cursor or self.server.closing, 10)
                batch = items[cursor:]
            self.respond(json.dumps(batch).encode())
        elif path == "/media-call":
            self.respond((SCRIPTS / "check-media-call.html").read_bytes(), "text/html")
        elif path == "/media-call/video-source.js":
            self.respond((SCRIPTS / "check-video-source.js").read_bytes(), "text/javascript")
        elif path == "/media-call/ice":
            server = {"urls":"turn:127.0.0.1:3478?transport=tcp","username":"kaizu-test",
                      "credential":os.environ["KAIZU_TEST_TURN_PASSWORD"]}
            self.respond(json.dumps({"iceServers":[server],"iceTransportPolicy":"relay"}).encode())
        elif len(parts) == 2 and parts[1] in ("A", "B") and parts[0] in ("sources", "ready", "done"):
            self.exchange(parts[0], parts[1], True)
        elif path in ("/loaded/A", "/loaded/B"):
            with self.server.changed:
                self.server.loaded.add(parts[1])
                self.server.changed.notify_all()
            self.respond(b"{}")
        else:
            self.send_error(404)

    def do_POST(self):
        parts = self.path.strip("/").split("/")
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size < 100_000 or len(parts) < 2 or parts[1] not in ("A", "B"):
            self.send_error(400)
            return
        value = json.loads(self.rfile.read(size))
        if parts[0] == "signal" and len(parts) == 3 and parts[2] in ("offer", "answer"):
            self.exchange(parts[2], parts[1], value)
        elif parts[0] == "ice" and len(parts) == 3 and parts[2] in ("offer", "answer"):
            with self.server.changed:
                self.server.candidates.setdefault((parts[1], parts[2]), []).append(value)
                self.server.changed.notify_all()
            self.respond(b"{}")
        elif parts[0] == "result" and len(parts) == 2:
            with self.server.changed:
                self.server.results.setdefault(parts[1], value)
                self.server.changed.notify_all()
            self.respond(b"{}")
        else:
            self.send_error(404)

    def log_message(self, *_):
        pass


def native_probes(label, modes):
    results = []
    for mode in modes:
        print(f"Testing native encoder {label}, mode={mode}", flush=True)
        try:
            process = subprocess.run([os.environ["KAIZU_ENCODER_PROBE"], mode], timeout=15)
            results.append(process.returncode == 0)
        except subprocess.TimeoutExpired:
            print(f"Native encoder {mode} timed out", flush=True)
            results.append(False)
    return all(results)


def trial(app, webkit, clients, number, timing):
    with ThreadingHTTPServer(("127.0.0.1", 0), PeerPage) as server:
        server.changed = threading.Condition()
        server.messages, server.candidates, server.results = {}, {}, {}
        server.loaded = set()
        server.closing = False
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        processes = []
        try:
            print(f"Starting trial {number} {clients} source={timing}", flush=True)
            for side, client in zip("AB", clients):
                if side == "B":
                    with server.changed:
                        if not server.changed.wait_for(lambda: "A" in server.loaded, 45):
                            raise RuntimeError("The first browser did not load the page")
                    time.sleep(15)
                url = f"http://127.0.0.1:{server.server_port}/media-call?side={side}&source=frames&timing={timing}"
                cmd = ["open","-W","-n","-a",app,url] if client == "kaizu" else [webkit,url]
                processes.append((client, subprocess.Popen(cmd)))
            with server.changed:
                deadline = time.monotonic() + 150
                while len(server.results) < 2 and time.monotonic() < deadline:
                    if any(proc.poll() is not None for _,proc in processes): break
                    server.changed.wait(0.2)
            for side, client in zip("AB", clients):
                print(f"Trial {number} {side}={client}: {json.dumps(server.results.get(side))}", flush=True)
            native_ok = native_probes(f"after call {number}, both browsers still open",
                                      ("default", "software") if number % 2 else ("software", "default"))
            return native_ok and len(server.results) == 2 and all(
                r["result"] == "pass" and r["sender"]["relay"] and r["receiver"]["relay"]
                for r in server.results.values()
            )
        finally:
            with server.changed:
                server.closing = True
                server.changed.notify_all()
            for client, proc in processes:
                if proc.poll() is None:
                    if client == "kaizu":
                        subprocess.run(["osascript","-e",'tell application id "com.joinprototype.kaizu" to quit'],
                                       check=True,timeout=25)
                    else:
                        proc.terminate()
                    proc.wait(timeout=25)
            server.shutdown()
            thread.join()


if __name__ == "__main__":
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Requires a disposable hosted Mac")
    support = Path.home() / "Library/Application Support/Kaizu"
    if support.exists(): raise SystemExit("Expected a fresh hosted account")
    settings = json.dumps({"externalLinks":"currentSpace"}).encode().hex()
    subprocess.run(["defaults","write","com.joinprototype.kaizu","settings","-data",settings],check=True)
    cases = [("webkit", "webkit"), ("webkit", "kaizu"), ("webkit", "kaizu"), ("webkit", "webkit")]
    baseline = native_probes("before opening browsers", ("default", "software"))
    outcomes = []
    for number, clients in enumerate(cases, 1):
        outcomes.append(trial(*sys.argv[1:3], clients, number, "paired"))
        if support.exists(): support.rename(Path(os.environ["RUNNER_TEMP"]) / f"peer-session-{number}")
    if not baseline or not all(outcomes):
        raise SystemExit(f"Native baseline passed={baseline}; {outcomes.count(False)} of {len(cases)} trials failed")

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
        elif path in ("/ready/A", "/ready/B"):
            self.exchange("ready", path[-1], True)
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


def trial(app, webkit, clients, number):
    with ThreadingHTTPServer(("127.0.0.1", 0), PeerPage) as server:
        server.changed = threading.Condition()
        server.messages, server.candidates, server.results = {}, {}, {}
        server.closing = False
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        processes = []
        try:
            for side, client in zip("AB", clients):
                url = f"http://127.0.0.1:{server.server_port}/media-call?side={side}&source=frames"
                cmd = ["open","-W","-n","-a",app,url] if client == "kaizu" else [webkit,url]
                processes.append((client, subprocess.Popen(cmd)))
            with server.changed:
                deadline = time.monotonic() + 150
                while len(server.results) < 2 and time.monotonic() < deadline:
                    if any(proc.poll() is not None for _,proc in processes): break
                    server.changed.wait(0.2)
            for side, client in zip("AB", clients):
                print(f"Trial {number} {side}={client}: {json.dumps(server.results.get(side))}", flush=True)
            return len(server.results) == 2 and all(
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
    cases = [("webkit","webkit"),("kaizu","webkit"),("webkit","kaizu"),
             ("webkit","kaizu"),("kaizu","webkit"),("webkit","webkit")]
    outcomes = []
    for number, clients in enumerate(cases, 1):
        outcomes.append(trial(*sys.argv[1:3], clients, number))
        if support.exists(): support.rename(Path(os.environ["RUNNER_TEMP"]) / f"peer-session-{number}")
    if not all(outcomes): raise SystemExit(f"{outcomes.count(False)} of {len(cases)} paired calls failed")

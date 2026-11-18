"""Compare an immediate v0.2.5 quit with a quit after observing the committed SQLite row."""
import importlib.util
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import ExitStack
from http.server import HTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location("fixture", Path(__file__).with_name("check-release-launch.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class Page(fixture.Page):
    def do_GET(self):
        if not self.server.issue_cookie and self.path == "/" + self.server.challenge:
            self.server.reads.append(self.headers.get("X-Kaizu-Storage", "unreported"))
        super().do_GET()


def wait_until_committed(url, marker, stores):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            profile = str(uuid.UUID(fixture.saved_tab(url)[0]))
        except (FileNotFoundError, SystemExit):
            pass  # The writer may still be saving its first session.
        else:
            if fixture.storage_checkpoint(stores / profile, marker) == "value matches":
                return
        time.sleep(.025)
    raise RuntimeError("The original app never committed the acknowledged write while open")


def trial(root, gate, reader, published, candidate, support, stores):
    with tempfile.TemporaryDirectory(dir=root) as scratch, ExitStack() as cleanup:
        folder = Path(scratch)
        app = folder / "Kaizu.app"
        subprocess.run(["ditto", "-x", "-k", published, folder], check=True)
        subprocess.run(["codesign", "--verify", "--strict", app], check=True)
        def retire_session():
            if support.exists():
                support.rename(folder / "session")
        cleanup.callback(retire_session)
        # Both processes must exit before a later trial starts a fresh generated profile.
        def stop_app():
            if subprocess.run(["pgrep", "-x", "Kaizu"], stdout=subprocess.DEVNULL).returncode == 1:
                return
            subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'], check=True, timeout=30)
            deadline = time.monotonic() + 30
            while subprocess.run(["pgrep", "-x", "Kaizu"], stdout=subprocess.DEVNULL).returncode == 0:
                if time.monotonic() >= deadline:
                    raise RuntimeError("The previous trial's browser is still running")
                time.sleep(.1)
        cleanup.callback(stop_app)
        with HTTPServer(("127.0.0.1", 0), Page) as server:
            server.timeout = 1
            server.cookie = "kaizu_login=" + secrets.token_hex(16)
            server.navigation_cookie = "kaizu_navigation=" + secrets.token_hex(16)
            server.storage_token = secrets.token_hex(16)
            server.check_first_page_blocking = False
            server.issue_cookie = True
            server.reads = []
            url = f"http://127.0.0.1:{server.server_port}/start"
            writer = fixture.launch(server, app, url)
            if gate == "committed":
                wait_until_committed(url, server.storage_token, stores)
            fixture.quit_app(writer)
            identity = fixture.saved_tab(url)
            directory = stores / str(uuid.UUID(identity[0]))
            after_quit = fixture.storage_checkpoint(directory, server.storage_token)
            if reader == "candidate":
                app.rename(folder / "Retired.app")
                subprocess.run(["ditto", "-x", "-k", candidate, folder], check=True)
                subprocess.run(["codesign", "--verify", "--strict", app], check=True)
            before_launch = fixture.storage_checkpoint(directory, server.storage_token)
            server.issue_cookie = False
            problem = None
            try:
                fixture.quit_app(fixture.launch(server, app))
            except SystemExit as error:
                problem = str(error)
            after_read = fixture.storage_checkpoint(directory, server.storage_token)
            same_tab = fixture.saved_tab(url) == identity
            print(f"Result quit={gate} reader={reader} after_old_quit={after_quit!r} "
                  f"before_reader={before_launch!r} after_reader={after_read!r} "
                  f"page_reads={server.reads} same_tab={same_tab} error={problem!r}", flush=True)
            return (problem is None and same_tab and server.reads == ["match"]
                    and after_quit == before_launch == after_read == "value matches")


if __name__ == "__main__":
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Requires a disposable GitHub-hosted Mac")
    root = Path(os.environ["RUNNER_TEMP"])
    support = Path.home() / "Library/Application Support/Kaizu"
    stores = Path.home() / "Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore"
    if support.exists():
        raise SystemExit("Expected a clean hosted account")
    settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
    subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
    cases = [(gate, reader) for gate in ("immediate", "committed") for reader in ("published", "candidate")]
    results = []
    for round_number in range(3):
        # Rotate the cold-start condition across otherwise identically prepared trials.
        for gate, reader in cases[round_number:] + cases[:round_number]:
            print(f"Starting round {round_number + 1}, quit={gate}, reader={reader}", flush=True)
            results.append(trial(root, gate, reader, *map(Path, sys.argv[1:]), support, stores))
    if not all(results):
        raise SystemExit(f"{results.count(False)} of {len(results)} quit/restore comparisons failed")

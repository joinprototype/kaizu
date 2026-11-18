"""Compare an established login with a freshly rotated one across a real bundle swap."""
import json
import os
from pathlib import Path
import runpy
import secrets
import subprocess
import sys
import uuid
from http.server import HTTPServer

qa = runpy.run_path(str(Path(__file__).with_name("check-release-launch.py")))


class ReturningPage(qa["Page"]):
    def do_GET(self):
        if self.path == "/start" and self.server.phase == "rotate":
            old_cookie = self.server.previous_navigation_cookie
            if old_cookie not in self.headers.get("Cookie", "").split("; "):
                self.server.page_failure = "The returning v0.2.5 session already lost the original navigation cookie"
                self.send_error(403)
                return
            print("The returning v0.2.5 document sent the original Lax cookie.", flush=True)
        super().do_GET()

    def send_header(self, keyword, value):
        # Rotate only the navigation cookie. The Strict login must survive both quits untouched.
        if self.server.phase == "rotate" and keyword == "Set-Cookie" and value.startswith("kaizu_login="):
            return
        super().send_header(keyword, value)


def main():
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Requires a disposable GitHub-hosted Mac")
    if (Path.home() / "Library/Application Support/Kaizu").exists():
        raise SystemExit("Expected a fresh account")
    writer, reader = [Path(arg).resolve(strict=True) for arg in sys.argv[1:]]
    settings = json.dumps({"externalLinks": "currentSpace"}).encode().hex()
    subprocess.run(["defaults", "write", "com.joinprototype.kaizu", "settings", "-data", settings], check=True)
    stores = Path.home() / "Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore"

    with HTTPServer(("127.0.0.1", 0), ReturningPage) as server:
        server.timeout = 1
        server.phase = "seed"
        server.issue_cookie = True
        server.check_first_page_blocking = False
        server.last_edit = None
        server.storage_token = secrets.token_hex(16)
        server.cookie = "kaizu_login=" + secrets.token_hex(16)
        server.navigation_cookie = "kaizu_navigation=" + secrets.token_hex(16)
        url = f"http://127.0.0.1:{server.server_port}/start"
        qa["seed_legacy_session"](server, writer, url, stores)
        identity = qa["saved_tab"](url)
        directory = stores / str(uuid.UUID(identity[0]))
        cookie_file = directory / "Cookies/Cookies.binarycookies"

        server.phase = "rotate"
        server.previous_navigation_cookie = server.navigation_cookie
        server.navigation_cookie = "kaizu_navigation=" + secrets.token_hex(16)
        # Only session restoration can open /start. The inherited probe requires both
        # the unchanged Strict login and the freshly rotated Lax value on the page.
        process = qa["launch"](server, writer)
        try:
            print("The returning legacy page sent the untouched login and rotated cookie together.", flush=True)
            qa["report_cookie_checkpoint"](server, cookie_file, "before returning v0.2.5 quit")
        finally:
            qa["quit_app"](process)
        qa["report_cookie_checkpoint"](server, cookie_file, "after returning v0.2.5 quit")
        writer.rename(writer.with_name("Retired.app"))
        reader.rename(writer)

        server.phase = "read"
        server.issue_cookie = False
        qa["check_restored_session"](server, writer, url, identity, directory)
        print("First restored document sent the rotated cookie. Its first same-origin request sent both logins and read the original draft.", flush=True)


if __name__ == "__main__":
    main()

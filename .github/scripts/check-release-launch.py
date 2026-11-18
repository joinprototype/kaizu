"""Run the built release app in a disposable macOS runner account."""

import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/start":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Set-Cookie", "kaizu_launch_test=ok; Path=/; SameSite=Strict")
            self.end_headers()
            self.wfile.write(b"""<!doctype html><title>Kaizu launch test</title>
                <body><h1>Ready</h1><script>
                if (document.querySelector('h1').textContent === 'Ready') fetch('/rendered');
                </script></body>""")
        elif self.path == "/rendered" and "kaizu_launch_test=ok" in self.headers.get("Cookie", "").split("; "):
            self.server.rendered = True
            self.send_response(204)
            self.end_headers()
        else:
            self.send_error(404)


def main():
    app = Path(sys.argv[1]).resolve(strict=True)
    with HTTPServer(("127.0.0.1", 0), Page) as server:
        server.rendered = False
        server.timeout = 1
        url = f"http://127.0.0.1:{server.server_port}/start"
        subprocess.run(["open", "-n", "-a", str(app), url], check=True, timeout=30)
        deadline = time.monotonic() + 90
        while not server.rendered:
            if time.monotonic() >= deadline:
                raise SystemExit("Timed out waiting for Kaizu to render the page and return its cookie")
            server.handle_request()
    print("Release app opened the external link and WebKit executed the page with cookies.")


if __name__ == "__main__":
    main()

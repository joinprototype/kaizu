from http.server import BaseHTTPRequestHandler, HTTPServer
import ssl

class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"""<!doctype html><title>Kaizu autofill test</title>
        <form><label>Username <input name="username" autocomplete="username"></label>
        <label>Password <input type="password" name="password" autocomplete="current-password"></label>
        <button>Sign in</button></form>""")

server = HTTPServer(("127.0.0.1", 18764), Page)
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
tls.load_cert_chain("tls.crt", "tls.key")
server.socket = tls.wrap_socket(server.socket, server_side=True)
server.serve_forever()

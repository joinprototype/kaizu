import json, os, secrets, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

if os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
    raise SystemExit('This trial requires a disposable hosted Mac')
root = Path(os.environ['RUNNER_TEMP'])
vendor = Path(sys.argv[1])
binary = Path('build/Kaizu.app/Contents/MacOS/Kaizu').resolve()
password, vault_key = secrets.token_urlsafe(18), secrets.token_urlsafe(28)
user, title = 'kaizu-test-user', 'Kaizu disposable login'
database = root/'kaizu-autotype.kdbx'
driver = root/'trigger'
cli = vendor/'Contents/MacOS/keepassxc-cli'
if not cli.is_file():
    cli = next(vendor.rglob('keepassxc-cli'))
def run(*args, stdin):
    subprocess.run(args, input=stdin, stdout=subprocess.DEVNULL, text=True, check=True, timeout=40)
run(cli, 'db-create', '-p', database, stdin=f'{vault_key}\n{vault_key}\n')
run(cli, 'add', '-u', user, '-p', database, title, stdin=f'{vault_key}\n{password}\n')
# Confirm the generated key and entry independently before testing the GUI.
listing = subprocess.run([cli, 'ls', database], input=vault_key+'\n', capture_output=True,
                         text=True, check=True, timeout=20)
if title not in listing.stdout.splitlines():
    raise SystemExit('The synthetic entry was absent from the unlocked CLI database')
print('The CLI unlocked the generated vault and found its test entry.', flush=True)
config = root/'autotype.ini'
config.write_text('[General]\nUpdateCheckMessageShown=true\nGlobalAutoTypeKey=75\nGlobalAutoTypeModifiers=167772160\n[GUI]\nCheckForUpdates=false\n')
ready, received = threading.Event(), threading.Event()
fields = [False, False]
class Page(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        if self.path != '/login':
            self.send_error(404); return
        body = b'''<!doctype html><title>Kaizu disposable login</title><form>
          <input name="username" autofocus><input type="password" name="password"><button>Submit</button></form>
          <script>const f=document.querySelector('form');const u=f.elements.username;
          const timer=setInterval(()=>{u.focus();if(document.activeElement===u){clearInterval(timer);fetch('/ready',{method:'POST'})}},150);
          f.addEventListener('input',()=>fetch('/fields',{method:'POST',body:JSON.stringify([u.value,f.elements.password.value])}));
          f.onsubmit=e=>{e.preventDefault();fetch('/filled',{method:'POST',body:JSON.stringify([u.value,f.elements.password.value])})};</script>'''
        self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
    def do_POST(self):
        body=self.rfile.read(int(self.headers.get('Content-Length',0)))
        if self.path=='/ready':ready.set()
        if self.path=='/fields':
            entered=json.loads(body)
            fields[:] = [entered[0]==user, entered[1]==password]
        if self.path=='/filled' and json.loads(body)==[user,password]:received.set()
        self.send_response(204); self.end_headers()
with ThreadingHTTPServer(('127.0.0.1',0),Page) as server:
    threading.Thread(target=server.serve_forever,daemon=True).start()
    keepass=subprocess.Popen([vendor/'Contents/MacOS/KeePassXC','--config',config,'--pw-stdin',database],stdin=subprocess.PIPE,text=True)
    try:
        keepass.stdin.write(vault_key+'\n'); keepass.stdin.close()
        for _ in range(12):
            probe = subprocess.run([driver,'vault'])
            if probe.returncode == 0:break
            time.sleep(1)
        else:raise SystemExit("KeePassXC did not expose the unlocked synthetic entry before the trial")
        kaizu=subprocess.Popen([binary],env=dict(os.environ,KAIZU_SUPPORT=str(root/'kaizu-fixture'),KAIZU_DEBUG='open',
                                                KAIZU_URL=f'http://127.0.0.1:{server.server_port}/login'))
        try:
            if not ready.wait(45):raise SystemExit('The fixture username field did not receive focus')
            subprocess.run([driver,'trigger'],check=True)
            if not received.wait(4):subprocess.run([driver,'confirm'],check=True)
            if not received.wait(8):
                print("Matched fields (username/password):", fields, flush=True)
                raise SystemExit('No matching credential submission reached the loopback fixture')
            print('KeePassXC selected and filled the synthetic Kaizu login. The local form submitted both expected fields.')
        finally:
            kaizu.terminate();kaizu.wait(timeout=15)
    finally:
        keepass.terminate()
        try:keepass.wait(timeout=5)
        except subprocess.TimeoutExpired:
            keepass.kill();keepass.wait(timeout=5)

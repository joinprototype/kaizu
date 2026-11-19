import http.server, socketserver, sys, threading

LOG = sys.argv[1]
PORT = int(sys.argv[2])

PAGE = b"""<!doctype html><html><head><meta charset=utf-8>
<link rel=stylesheet href="/t/css">
<style>@font-face{font-family:x;src:url(/t/font)} body{font-family:x}</style>
<script src="/t/script"></script></head><body>
<img src="/t/img"><audio src="/t/media" preload=auto></audio><iframe src="/t/frame"></iframe>
<script>
fetch('/t/fetch').catch(()=>{});
var x=new XMLHttpRequest();x.open('GET','/t/xhr');x.send();
navigator.sendBeacon('/t/beacon','x');
try{new EventSource('/t/sse')}catch(e){}
try{new WebSocket('ws://127.0.0.1:%d/t/ws')}catch(e){}
var l=document.createElement('link');l.rel='preload';l.as='fetch';l.href='/t/preload';document.head.appendChild(l);
</script>
<a id=a href="/t/pingdest" ping="/t/ping">p</a>
<script>setTimeout(function(){document.getElementById('a').click()},800)</script>
</body></html>""" % PORT

CSSPAGE = b"""<!doctype html><html><body>
<div id="0_pweumum7">a</div><div class="h-[90px]">b</div><div class="lg:min-h-[290px]">c</div>
<div class="group/ads">d</div><div class="!min-h-[250px]">e</div><div class="bg-[#f8f8f8]">f</div>
<div class="ad-desktop:block">g</div><div id="finbold.com_middle">h</div><div class="w-[10px]">i</div>
<div class="x:y">j</div><div class="keep">k</div><div class="keep2" id="keep3">l</div>
<script>
setTimeout(function(){
 var out=[];
 document.querySelectorAll('div').forEach(function(d){
   var n=(d.id||d.className).replace(/[^A-Za-z0-9]/g,'_');
   out.push(n+'='+(getComputedStyle(d).display==='none'?'hidden':'visible'));
 });
 fetch('/r/'+encodeURIComponent(out.join(',')));
},800);
</script></body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(LOG, 'a') as f:
            f.write(self.path + '\n')
        if self.path.startswith('/css'):
            body = CSSPAGE; ct = 'text/html'
        elif self.path.startswith('/page'):
            body = PAGE; ct = 'text/html'
        elif self.path.startswith('/t/css'):
            body = b'a{}'; ct = 'text/css'
        elif self.path.startswith('/t/script'):
            body = b''; ct = 'text/javascript'
        elif self.path.startswith('/t/img'):
            body = b''; ct = 'image/png'
        elif self.path.startswith('/t/sse'):
            body = b''; ct = 'text/event-stream'
        else:
            body = b'ok'; ct = 'text/plain'
        self.send_response(200)
        self.send_header('Content-Type', ct)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        self.rfile.read(n)
        with open(LOG, 'a') as f:
            f.write(self.path + '\n')
        self.send_response(200); self.send_header('Content-Length', '0'); self.end_headers()
    def log_message(self, *a): pass

class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

S(('127.0.0.1', PORT), H).serve_forever()

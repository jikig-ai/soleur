import http.server, ssl, sys, threading, json, time
LOG="/out/capture.log"
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n=int(self.headers.get("Content-Length") or 0); b=self.rfile.read(n)
        with open(LOG,"ab") as f: f.write(("%s %s %s %s\n"%(time.time(), self.server.server_port, self.path, b.decode(errors="replace"))).encode())
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(b'{"id":"0"}')
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self,*a): pass
def serve(port, tls):
    s=http.server.ThreadingHTTPServer(("0.0.0.0",port),H)
    if tls:
        c=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain("/pki/srv.crt","/pki/srv.key"); s.socket=c.wrap_socket(s.socket,server_side=True)
    s.serve_forever()
threading.Thread(target=serve,args=(80,False),daemon=True).start()
open("/out/stub.ready","w").write("1")
serve(443,True)

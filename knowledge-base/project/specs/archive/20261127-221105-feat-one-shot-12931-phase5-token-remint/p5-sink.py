#!/usr/bin/env python3
"""p5-sink.py -- the one-shot 127.0.0.1 hand-off sink for p5-mint.js (#12931 Phase 5 token slice, CTO ruling D1).

    python3 -I p5-sink.py --out <absolute path> [--port 0] [--timeout 900]

Binds 127.0.0.1 only and serves EXACTLY ONE request, then exits; a second request finds no listener. It
prints one line on start, then one result line, and never the value:

    SOLEUR_P5_SINK url=http://127.0.0.1:<port>/<nonce>#<answer>
                                                           pass this verbatim as p5-mint.js `sink_url`. The sink
                                                           answers a written value with exactly <answer> (32
                                                           characters, fresh per run, never sent: a URL fragment),
                                                           so a process that rebound the port cannot fake the reply
    SOLEUR_P5_SINK result=written                          exit 0: the value is in --out, mode 0600
    SOLEUR_P5_SINK result=refused reason=<r>               exit 1 (request refused) or 2 (bad --out)
    SOLEUR_P5_SINK result=timeout                          exit 3: no request within --timeout seconds

The one request is written only when ALL hold: the peer is 127.0.0.1; method POST; path is /<nonce> (a fresh
random nonce, so a stray local client cannot feed a value in); no Origin header (a browser page cannot reach
it); a Content-Length of 20..1024 bytes of token characters. The body is the token value, written byte-exact
with O_CREAT|O_EXCL|O_NOFOLLOW at mode 0600. Any other first request is refused and still ends the sink (fail
closed: the mint then deletes its new token). --out must be absolute, must not exist, and must sit outside
every git work tree (runbook: the session scratchpad). Refusal reasons: peer, method, path, origin, length,
body, write (the create, a write or the fsync failed; a partial file is unlinked), malformed; for --out:
out-relative, out-exists, out-parent, out-in-git.
"""
import argparse
import hmac
import http.server
import os
import re
import secrets
import socket
import sys

TOKEN_RE = re.compile(rb"\A[A-Za-z0-9._~+/=-]{20,1024}\Z")


def say(line):
    sys.stdout.write("SOLEUR_P5_SINK " + line + "\n")
    sys.stdout.flush()


def in_git_tree(path):
    d = os.path.dirname(path)
    while True:
        if os.path.lexists(os.path.join(d, ".git")):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def check_out(out):
    if not os.path.isabs(out):
        return "out-relative"
    out = os.path.normpath(out)
    if os.path.lexists(out):
        return "out-exists"
    if not os.path.isdir(os.path.dirname(out)):
        return "out-parent"
    if in_git_tree(os.path.realpath(out)):
        return "out-in-git"
    return None


def main():
    ap = argparse.ArgumentParser(description="one-shot 127.0.0.1 token sink")
    ap.add_argument("--out", required=True)
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--timeout", type=float, default=900.0)
    opt = ap.parse_args()

    bad = check_out(opt.out)
    if bad:
        say("result=refused reason=" + bad)
        return 2
    out = os.path.normpath(opt.out)
    nonce = secrets.token_urlsafe(24)
    answer = secrets.token_urlsafe(24).encode()
    # A connection that never sends a request line ends the sink as `malformed`; a request or the timeout
    # overwrites this.
    outcome = {"line": "result=refused reason=malformed", "code": 1}

    class Handler(http.server.BaseHTTPRequestHandler):
        timeout = 15  # per-connection socket timeout: a stalled client cannot hold the one request open

        def log_message(self, *_a):  # the default handler logs to stderr; this sink logs nothing
            return

        def refuse(self, code, reason):
            outcome["line"] = "result=refused reason=" + reason
            outcome["code"] = 1
            try:
                self.send_response(code)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", "7")
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(b"refused")
            except OSError:
                pass

        def handle_one(self):
            if self.client_address[0] != "127.0.0.1":
                return self.refuse(403, "peer")
            if self.command != "POST":
                return self.refuse(405, "method")
            if not hmac.compare_digest(self.path.encode(), ("/" + nonce).encode()):
                return self.refuse(404, "path")
            if self.headers.get("Origin") is not None:
                return self.refuse(403, "origin")
            try:
                n = int(self.headers.get("Content-Length", ""))
            except ValueError:
                n = -1
            if n < 20 or n > 1024:
                return self.refuse(400, "length")
            body = self.rfile.read(n)
            if len(body) != n or not TOKEN_RE.match(body):
                return self.refuse(400, "body")
            old = os.umask(0o077)
            try:
                fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
            except OSError:
                return self.refuse(500, "write")
            finally:
                os.umask(old)
            # A failed write or fsync leaves no partial file: unlink it, refuse `write` (the mint then deletes
            # its new token).
            written = False
            try:
                os.fchmod(fd, 0o600)
                view = memoryview(body)
                while view:
                    view = view[os.write(fd, view):]
                os.fsync(fd)
                written = True
            except OSError:
                written = False
            finally:
                try:
                    os.close(fd)
                except OSError:
                    written = False
            if not written:
                try:
                    os.unlink(out)
                except OSError:
                    pass
                return self.refuse(500, "write")
            outcome["line"] = "result=written"
            outcome["code"] = 0
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(answer)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(answer)
            return None

        def do_POST(self):
            self.handle_one()

        do_GET = do_PUT = do_DELETE = do_HEAD = do_PATCH = do_OPTIONS = do_POST

    class OneShot(http.server.HTTPServer):
        address_family = socket.AF_INET
        allow_reuse_address = False

        def handle_timeout(self):
            outcome["line"] = "result=timeout"
            outcome["code"] = 3

    httpd = OneShot(("127.0.0.1", opt.port), Handler)
    httpd.timeout = opt.timeout
    try:
        say("url=http://127.0.0.1:%d/%s#%s" % (httpd.server_address[1], nonce, answer.decode()))
        httpd.handle_request()  # exactly one request (or the timeout), then close the listener
    finally:
        httpd.server_close()
    say(outcome["line"])
    return outcome["code"]


if __name__ == "__main__":
    sys.exit(main())

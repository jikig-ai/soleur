#!/usr/bin/env python3
"""Capture Playwright-MCP stdio fixtures from the surface (#7980, Phase 0.2).

    python3 capture-playwright-mcp-fixtures.py <output-dir> -- <server argv...>

Serves a synthesized form on 127.0.0.1 (no real credential, no real origin),
drives the given MCP server over its own stdin/stdout with hand-written
JSON-RPC, and writes ONE JSON file per captured message into <output-dir>:

    initialize.json            tools-list.json          roots-list-request.json
    navigate.json              snapshot.json            snapshot-filename.json
    snapshot-meta-json.json    snapshot-meta-raw.json   find.json
    evaluate.json              screenshot.json          close.json
    raw-stdout.bin             framing.json             page.html

The page puts the sentinel `ZZQP-SENTINEL-7980` ONLY in credential-named inputs
(password, Token) and `ZZQP-BENIGN-7980` in Notes, so a redaction assertion can
count both halves. Every `@playwright/mcp` bump re-runs this driver so the suite
tests captures from the pinned surface, never from the author (ADR-213 round 3).

Framing assertion (row 12): every server stdout message is one `\n`-terminated
line that parses as a JSON object, no embedded newline, no `Content-Length`.

stdlib only. Exit 0 on a complete capture, 1 on a framing violation, 2 on usage.
"""
from __future__ import annotations

import http.server
import json
import os
import selectors
import subprocess
import sys
import threading
import time

PAGE_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>probe 7980</title></head>
<body>
<form>
  <label>Enter your password <input type="password" value="ZZQP-SENTINEL-7980"></label>
  <label>Token <input type="text" readonly value="ZZQP-SENTINEL-7980"></label>
  <label>Email address <input type="email" value="probe-user@example.invalid"></label>
  <label>Notes <textarea>ZZQP-BENIGN-7980</textarea></label>
  <button type="button">Go</button>
</form>
</body></html>
"""


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):  # noqa: D401 - silence the server
        pass

    def do_GET(self):  # noqa: N802 - http.server API
        body = PAGE_HTML.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve_page():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Quiet)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}/page.html"


class Driver:
    def __init__(self, argv, out):
        self.out = out
        self.child = subprocess.Popen(
            argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, bufsize=0
        )
        self.sel = selectors.DefaultSelector()
        self.sel.register(self.child.stdout, selectors.EVENT_READ)
        self.buf = bytearray()
        self.raw = bytearray()
        self.next_id = 1
        self.violations = []

    def send(self, obj):
        line = json.dumps(obj, separators=(",", ":")).encode() + b"\n"
        self.child.stdin.write(line)
        self.child.stdin.flush()

    def request(self, method, params=None):
        rid = self.next_id
        self.next_id += 1
        msg = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            msg["params"] = params
        self.send(msg)
        return rid

    def read_line(self, timeout=60.0):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buf:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("no line from server within timeout")
            if not self.sel.select(timeout=remaining):
                continue
            chunk = os.read(self.child.stdout.fileno(), 65536)
            if not chunk:
                raise EOFError("server closed stdout")
            self.buf += chunk
            self.raw += chunk
        line, _, rest = bytes(self.buf).partition(b"\n")
        self.buf = bytearray(rest)
        return line

    def wait_response(self, rid, name):
        """Read until the response for `rid` arrives; capture server requests on the way."""
        while True:
            line = self.read_line()
            if line.startswith(b"Content-Length"):
                self.violations.append("Content-Length header on stdout")
            try:
                obj = json.loads(line.decode("utf-8", errors="replace"))
            except json.JSONDecodeError:
                self.violations.append(f"non-JSON stdout line ({len(line)} bytes)")
                continue
            if not isinstance(obj, dict):
                self.violations.append("stdout line is not a JSON object")
                continue
            if "method" in obj and "id" in obj:
                # server -> client request (roots/list); answer it and record it.
                self.save("roots-list-request" if obj["method"] == "roots/list" else f"server-request-{obj['method'].replace('/', '-')}", obj)
                self.send({"jsonrpc": "2.0", "id": obj["id"], "result": {"roots": []}})
                continue
            if "method" in obj:
                self.save(f"notification-{obj['method'].replace('/', '-')}", obj)
                continue
            if obj.get("id") == rid:
                self.save(name, obj)
                return obj
            self.save(f"unexpected-{obj.get('id')}", obj)

    def save(self, name, obj):
        path = os.path.join(self.out, f"{name}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, indent=2, ensure_ascii=False)
            fh.write("\n")

    def call(self, name, tool, arguments=None):
        rid = self.request("tools/call", {"name": tool, "arguments": arguments or {}})
        return self.wait_response(rid, name)

    def finish(self):
        try:
            self.child.stdin.close()
        except OSError:
            pass
        try:
            self.child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.child.kill()
        with open(os.path.join(self.out, "raw-stdout.bin"), "wb") as fh:
            fh.write(bytes(self.raw))
        lines = bytes(self.raw).split(b"\n")
        trailing = lines[-1]
        if trailing:
            self.violations.append("stdout did not end with a newline")
        framing = {
            "messages": len(lines) - 1,
            "content_length_header": any(l.startswith(b"Content-Length") for l in lines),
            "every_line_is_json_object": all(
                isinstance(json.loads(l.decode("utf-8", errors="replace")), dict) for l in lines[:-1]
            ),
            "violations": self.violations,
        }
        self.save("framing", framing)
        return framing


def main(argv):
    if "--" not in argv or argv.index("--") != 1 or len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    out = argv[0]
    server_argv = argv[2:]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "page.html"), "w", encoding="utf-8") as fh:
        fh.write(PAGE_HTML)
    srv, url = serve_page()
    try:
        d = Driver(server_argv, out)
        rid = d.request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {"roots": {"listChanged": True}},
                "clientInfo": {"name": "capture-playwright-mcp-fixtures", "version": "7980"},
            },
        )
        d.wait_response(rid, "initialize")
        d.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        d.wait_response(d.request("tools/list"), "tools-list")
        d.call("navigate", "browser_navigate", {"url": url})
        d.call("snapshot", "browser_snapshot")
        d.call("snapshot-filename", "browser_snapshot", {"filename": "explicit-snap.yml"})
        d.call("snapshot-meta-json", "browser_snapshot", {"_meta": {"json": True}})
        d.call("snapshot-meta-raw", "browser_snapshot", {"_meta": {"raw": True}})
        d.call("find", "browser_find", {"text": "Token"})
        d.call("evaluate", "browser_evaluate", {"function": "() => ({a: 1, b: [1,2]})"})
        d.call("screenshot", "browser_take_screenshot", {"type": "png"})
        d.call("close", "browser_close")
        framing = d.finish()
    finally:
        srv.shutdown()
    print(json.dumps(framing))
    return 1 if framing["violations"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

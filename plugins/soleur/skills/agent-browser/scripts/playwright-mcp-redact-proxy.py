#!/usr/bin/env python3
"""Redacting stdio JSON-RPC proxy in front of the Playwright MCP server (#7980).

    python3 playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 [server args...]

WHAT THIS BUYS (property P7 on the Playwright-MCP path)
-------------------------------------------------------
An accessibility snapshot serializes the VALUE of input fields. On the
Playwright-MCP path the tree reaches the model inside a tool result, and
nothing between the server and the model applies the credential predicate:
the PreToolUse hook gates `Bash` (not `mcp__playwright__browser_snapshot`),
PostToolUse cannot rewrite output, and `--secrets` masks only values named in
advance. This proxy sits on the transport itself -- Claude Code's stdin/stdout
on one side, the server's pipes on the other -- and rewrites the text of every
`tools/call` result through the SAME `redact_text` the agent-browser Bash path
uses, before the model reads it. No agent action is required for that to hold
on a registration routed through this file (this repository's `.mcp.json`).

REACH, STATED PER SURFACE (not a Jikigai safety undertaking)
------------------------------------------------------------
  * this repository's `.mcp.json` -- declared there and asserted by the suite;
  * a customer's own registration -- the plugin ships this file but registers
    NO Playwright server, so a customer is wrapped only by their own
    configuration (#8156);
  * the hosted agent-runner registers no Playwright server;
  * the Inngest fleet overlay is NOT wrapped (it gets `--snapshot-mode none`
    directly; PA-31 §(g)).

THREE FAIL-CLOSED ARMS, ALL LOUD, NO KILL SWITCH
-----------------------------------------------
  (i)  startup -- the sibling redactor cannot be loaded or fails its self-test,
       or the wrapped argv/config/env names a RAW SINK (`--save-session`,
       config `saveSession`, `DEBUG` matching `*`/`pw:mcp*`, `DEBUG_FILE`):
       stderr `refusing to start: <reason>`, exit 2, no child spawned;
  (ii) per result -- an exception, the 4 MiB cap, an unrecognised result
       shape, or a link-shaped result (the disk sink reappearing) replaces the
       result with an `isError` text result that names the tool and never
       quotes the input;
  (iii) transport -- a dead child ends the proxy with the clamped exit code;
       a closed stdin tears the child's process group down.
One's own `.mcp.json` is the off switch. There is deliberately no env-var
bypass: a silent fail-open is exactly what the issue forbids.

ENUMERATIVE CLOSURE OF THE DISK SINK, BOUND TO THE 0.0.78 PIN
-------------------------------------------------------------
`--snapshot-mode none` is appended to the child argv (measured: the CLI flag
wins over a config file, and action tools then write no `page-*.yml`);
`browser_snapshot` with a `filename` key and ANY `tools/call` whose arguments
carry `_meta` are refused before they reach the server (`_meta.json` returns
the tree as one escaped string the line-anchored predicate cannot see);
`--save-session`/`saveSession`/`DEBUG`/`DEBUG_FILE` are refused at startup.
The drift arm (a `- [Snapshot](` line in a result is withheld) and the Phase 0
re-capture on every version bump are the complement.

NAMED RESIDUALS (restated in ADR-213 and the Article 30 register)
------------------------------------------------------------------
`browser_take_screenshot` returns an image block (a readonly credential panel
renders in clear); values the agent deliberately extracts
(`browser_network_request` headers/body, `browser_evaluate`,
`browser_run_code_unsafe`, console messages) are outside the snapshot
mechanism; non-tree disk sinks the server writes without agent action (console
logs, PNGs, downloads); prose the predicate is inert on (`- Page URL:` with a
token in the query, titles, dialog messages); the redactor's own stated
bypasses; and when the drift arm withholds a link, the file the server already
wrote persists on disk -- a relay does not delete.

Single-threaded `selectors` loop, stdlib only, POSIX. The predicate has exactly
one source: the four names bound from the sibling `redact-a11y-snapshot.py`.
Fail-closed contract per ADR-095: reasons never quote the input, on stdout or
on stderr (Claude Code persists this process's stderr to
`~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl`).
"""
from __future__ import annotations

import importlib.util
import json
import os
import selectors
import signal
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

PREFIX = "playwright-mcp-redact-proxy:"
REDACTOR_BASENAME = "redact-a11y-snapshot.py"
# 64 MiB: a hostile page can push a tree toward Node's string limit, and an
# OOM-killed proxy runs no teardown (CWE-400). Pending calls are answered.
MAX_LINE_BYTES = 64 * 1024 * 1024
# Chrome can exceed 5 s on SIGTERM alone (learning 2026-07-05, orphan servers).
GRACE_S = 5.0
TOOLS_LIST_MARKER = (
    " [Soleur: output is redacted in flight by the a11y-snapshot redactor;"
    " filename is refused — call browser_snapshot with no filename.]"
)
TRAILER = "[Soleur: redacted in flight by playwright-mcp-redact-proxy]"
CAVEAT = (
    "A screenshot is safe for a masked input (the browser renders dots) and NOT for a"
    " panel displaying a freshly-minted value, which renders in clear. A page over the"
    " redactor's cap cannot be snapshotted on this path — narrow it with target: or"
    " depth:. The filename form is only for an unwrapped registration; behind this"
    " proxy call browser_snapshot with no filename."
)
RESULT_KEYS = {"content", "isError", "isClose"}
TEXT_KEYS = {"type", "text", "annotations"}
BINARY_KEYS = {"type", "data", "mimeType", "annotations"}


def log(msg: str) -> None:
    sys.stderr.write(f"{PREFIX} {msg}\n")
    sys.stderr.flush()


def refuse_start(reason: str) -> None:
    log(f"refusing to start: {reason}")
    sys.stderr.flush()
    os._exit(2)


# ---------------------------------------------------------------------------
# B1 -- argv
# ---------------------------------------------------------------------------
def parse_argv(argv: List[str]) -> List[str]:
    if "--" not in argv:
        refuse_start("usage: playwright-mcp-redact-proxy.py -- <server argv...> (no `--` separator)")
    server = argv[argv.index("--") + 1 :]
    if not server:
        refuse_start("usage: playwright-mcp-redact-proxy.py -- <server argv...> (empty server argv)")
    return server


# ---------------------------------------------------------------------------
# B2 -- the one predicate, bound by path; four names, all at startup
# ---------------------------------------------------------------------------
def load_redactor() -> Tuple[Any, Any, int, str]:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), REDACTOR_BASENAME)
    if not os.path.isfile(path):
        refuse_start(f"sibling {REDACTOR_BASENAME} is missing (drifted plugin install?)")
    try:
        spec = importlib.util.spec_from_file_location("redact_a11y_snapshot", path)
        if spec is None or spec.loader is None:
            raise ImportError("no loader")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except BaseException as exc:  # noqa: BLE001 - any failure to load is a refusal
        refuse_start(f"cannot load {REDACTOR_BASENAME}: {type(exc).__name__}")
    missing = [n for n in ("redact_text", "looks_like_a11y_tree", "MAX_INPUT_BYTES", "REDACTED") if not hasattr(mod, n)]
    if missing:
        refuse_start(f"{REDACTOR_BASENAME} does not export {', '.join(missing)}")
    return mod.redact_text, mod.looks_like_a11y_tree, int(mod.MAX_INPUT_BYTES), str(mod.REDACTED)


# ---------------------------------------------------------------------------
# B3 -- self-test: the predicate must redact a sentinel row AND remove the value
# ---------------------------------------------------------------------------
def self_test(redact_text: Any, looks_like_a11y_tree: Any, redacted: str) -> None:
    row = '- textbox "Token" [ref=e1]: ZZQP-SENTINEL-7980'
    try:
        out = redact_text(row)
    except BaseException as exc:  # noqa: BLE001
        refuse_start(f"redactor self-test raised {type(exc).__name__}")
    if redacted not in out or "ZZQP-SENTINEL-7980" in out:
        refuse_start("redactor self-test did not redact the sentinel row")
    try:
        tree_true = looks_like_a11y_tree(row)
        prose_false = looks_like_a11y_tree("### Page\n- Page URL: x")
    except BaseException as exc:  # noqa: BLE001
        refuse_start(f"looks_like_a11y_tree raised {type(exc).__name__}")
    if not tree_true or prose_false:
        refuse_start("looks_like_a11y_tree self-test failed (tree row / prose row)")


# ---------------------------------------------------------------------------
# B2 (second half) -- raw sinks refused before spawn
# ---------------------------------------------------------------------------
def refuse_argv_and_env(server: List[str], env: Dict[str, str]) -> None:
    if "--save-session" in server:
        refuse_start("--save-session writes every response to a session.md on disk")
    config_path: Optional[str] = None
    for i, a in enumerate(server):
        if a.startswith("--config="):
            config_path = a[len("--config=") :]
        elif a == "--config" and i + 1 < len(server):
            config_path = server[i + 1]
    if config_path is None:
        config_path = env.get("PLAYWRIGHT_MCP_CONFIG") or None
    if config_path and os.path.isfile(config_path):
        try:
            with open(config_path, "rb") as fh:
                cfg = json.load(fh)
        except (OSError, ValueError):
            cfg = None
        if isinstance(cfg, dict) and cfg.get("saveSession"):
            refuse_start("config saveSession is set (a raw session.md sink)")
    debug = env.get("DEBUG", "")
    if debug and ("*" in debug.split(",") or any(p.strip().startswith("pw:mcp") for p in debug.split(","))):
        refuse_start("DEBUG matches the server's response logger (pw:mcp*), which prints unredacted results to stderr")
    if env.get("DEBUG_FILE"):
        refuse_start("DEBUG_FILE is set (a raw debug sink on disk)")


# ---------------------------------------------------------------------------
# B4 -- spawn; the child leads a new session so the whole tree is one group
# ---------------------------------------------------------------------------
def spawn_child(server: List[str]) -> subprocess.Popen:
    argv = list(server) + ["--snapshot-mode", "none"]
    child = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None, bufsize=0, start_new_session=True)
    log(f"child pgid {os.getpgid(child.pid)}")
    return child


def write_line(fobj: Any, data: bytes) -> None:
    fobj.write(data if data.endswith(b"\n") else data + b"\n")
    fobj.flush()


# ---------------------------------------------------------------------------
# B9 -- ONE builder for every synthesized client-bound result
# ---------------------------------------------------------------------------
def error_result(rid: Any, tool: str, reason: str, *, refused: bool = False) -> bytes:
    kind = "refused" if refused else "withheld"
    head = "refused:" if refused else "snapshot withheld:"
    text = f"### Error\n{head} {reason} (tool: {tool})\n{CAVEAT}"
    log(f"{kind} tool={tool} id={json.dumps(rid)} reason={reason}")
    obj = {"jsonrpc": "2.0", "id": rid, "result": {"content": [{"type": "text", "text": text}], "isError": True}}
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode()


# ---------------------------------------------------------------------------
# B5 -- client -> server
# ---------------------------------------------------------------------------
def id_key(rid: Any) -> Tuple[str, Any]:
    return (type(rid).__name__, rid)


def refuse_request(req: Dict[str, Any]) -> Optional[bytes]:
    """Return an error_result line for a request that must never reach the server, else None."""
    if req.get("method") != "tools/call":
        return None
    params = req.get("params") if isinstance(req.get("params"), dict) else {}
    name = str(params.get("name", ""))
    args = params.get("arguments")
    if not isinstance(args, dict):
        return None
    if "_meta" in args:
        return error_result(req.get("id"), name, "arguments._meta is an undocumented hook that returns the tree in a shape the redactor cannot see; call the tool without _meta", refused=True)
    if name == "browser_snapshot" and "filename" in args:
        return error_result(req.get("id"), name, "filename writes the raw tree to disk; call browser_snapshot with no filename (the file form is only for an unwrapped registration)", refused=True)
    return None


class Proxy:
    def __init__(self, server: List[str], redactor: Tuple[Any, Any, int, str]) -> None:
        self.redact_text, self.looks_like_a11y_tree, self.max_input_bytes, self.redacted = redactor
        self.pending: Dict[Tuple[str, Any], Tuple[str, str]] = {}  # key -> (method, tool name)
        self.child = spawn_child(server)
        self.pgid = os.getpgid(self.child.pid)
        self.out = sys.stdout.buffer
        self.stdin_open = True
        self.child_open = True
        self.grace = GRACE_S
        try:
            self.grace = float(os.environ.get("PLAYWRIGHT_MCP_PROXY_GRACE_S", GRACE_S))
        except ValueError:
            pass

    # -- B5 -----------------------------------------------------------------
    def pump_client_to_server(self, line: bytes) -> None:
        try:
            req = json.loads(line.decode("utf-8", errors="replace"))
        except ValueError:
            log(f"forwarded unparsable client line ({len(line)} bytes)")
            write_line(self.child.stdin, line)
            return
        if isinstance(req, list):
            log(f"dropped list line from client ({len(line)} bytes)")
            return
        if not isinstance(req, dict):
            write_line(self.child.stdin, line)
            return
        refusal = refuse_request(req)
        if refusal is not None:
            write_line(self.out, refusal)
            return
        if "method" in req and "id" in req:
            params = req.get("params") if isinstance(req.get("params"), dict) else {}
            key = id_key(req["id"])
            self.pending.pop(key, None)  # a reused id: the stale entry goes first
            self.pending[key] = (str(req["method"]), str(params.get("name", "")))
        write_line(self.child.stdin, line)

    # -- B6/B7/B8 -----------------------------------------------------------
    def pump_server_to_client(self, line: bytes) -> None:
        try:
            msg = json.loads(line.decode("utf-8", errors="replace"))
        except ValueError:
            log(f"dropped unparsable server line ({len(line)} bytes)")
            return
        if isinstance(msg, list):
            answered = 0
            for el in msg:
                if isinstance(el, dict) and ("result" in el or "error" in el) and id_key(el.get("id")) in self.pending:
                    _method, tool = self.pending.pop(id_key(el.get("id")))
                    write_line(self.out, error_result(el.get("id"), tool, "the server answered inside a JSON list line, which the proxy does not relay"))
                    answered += 1
            log(f"dropped list line from server ({len(line)} bytes, {answered} pending answered)")
            return
        if not isinstance(msg, dict):
            log(f"dropped unparsable server line ({len(line)} bytes)")
            return
        kind = self.classify(msg)
        if kind == "passthrough":
            write_line(self.out, line)
            return
        if kind == "unknown":
            log(f"dropped unknown-id response id={json.dumps(msg.get('id'))} ({len(line)} bytes)")
            return
        method, tool = self.pending.pop(id_key(msg.get("id")))
        if "method" in msg:
            write_line(self.out, error_result(msg.get("id"), tool, "unrecognised result shape (response carries a method)"))
            return
        if method == "tools/call":
            write_line(self.out, self.rewrite_result(msg, line, tool))
        elif method == "tools/list":
            write_line(self.out, self.annotate_tools_list(msg, line))
        elif method == "initialize":
            info = msg.get("result", {}) if isinstance(msg.get("result"), dict) else {}
            si = info.get("serverInfo", {}) if isinstance(info.get("serverInfo"), dict) else {}
            log(f"wrapping {si.get('name', '?')} {si.get('version', '?')} protocol {info.get('protocolVersion', '?')}")
            write_line(self.out, line)
        else:
            write_line(self.out, line)

    def classify(self, msg: Dict[str, Any]) -> str:
        """'pending' (a response to a request we recorded), 'unknown' (a response we did not), 'passthrough' (a server request or notification)."""
        if "result" not in msg and "error" not in msg:
            return "passthrough"
        return "pending" if id_key(msg.get("id")) in self.pending else "unknown"

    def rewrite_result(self, msg: Dict[str, Any], line: bytes, tool: str) -> bytes:
        rid = msg.get("id")
        try:
            if "error" in msg:
                err = msg["error"]
                if isinstance(err, dict) and "data" in err:
                    return error_result(rid, tool, "error response carried structured data")
                return line
            result = msg.get("result")
            if not isinstance(result, dict) or not set(result.keys()) <= RESULT_KEYS:
                return error_result(rid, tool, "unrecognised result shape")
            content = result.get("content")
            if not isinstance(content, list):
                return error_result(rid, tool, "unrecognised result shape")
            changed = False
            tree_seen = False
            new_content: List[Dict[str, Any]] = []
            for block in content:
                if not isinstance(block, dict):
                    return error_result(rid, tool, "unrecognised result shape")
                btype = block.get("type")
                if btype == "text":
                    if not set(block.keys()) <= TEXT_KEYS or not isinstance(block.get("text"), str):
                        return error_result(rid, tool, "unrecognised result shape")
                    text = block["text"]
                    if len(text.encode("utf-8", "surrogatepass")) > self.max_input_bytes:
                        return error_result(rid, tool, "result exceeds the redactor's size cap")
                    for tline in text.split("\n"):
                        if tline.startswith("- [Snapshot]("):
                            return error_result(rid, tool, "the server wrote a raw file under its output directory; do not read it")
                    if self.looks_like_a11y_tree(text):
                        tree_seen = True
                    new_text = self.redact_text(text)
                    if new_text != text:
                        changed = True
                        block = dict(block)
                        block["text"] = new_text
                elif btype in ("image", "audio"):
                    if not set(block.keys()) <= BINARY_KEYS:
                        return error_result(rid, tool, "unrecognised result shape")
                else:
                    return error_result(rid, tool, "unrecognised result shape")
                new_content.append(block)
            if tree_seen:
                new_content.append({"type": "text", "text": TRAILER})
                changed = True
            if not changed:
                return line
            new_result = dict(result)
            new_result["content"] = new_content
            out = dict(msg)
            out["result"] = new_result
            return json.dumps(out, separators=(",", ":"), ensure_ascii=True).encode()
        except BaseException as exc:  # noqa: BLE001 - any failure withholds
            return error_result(rid, tool, f"redaction raised {type(exc).__name__}")

    def annotate_tools_list(self, msg: Dict[str, Any], line: bytes) -> bytes:
        try:
            tools = msg["result"]["tools"]
            hit = False
            for t in tools:
                if t.get("name") == "browser_snapshot" and isinstance(t.get("description"), str):
                    t["description"] = t["description"] + TOOLS_LIST_MARKER
                    hit = True
            if not hit:
                raise KeyError("browser_snapshot")
            return json.dumps(msg, separators=(",", ":"), ensure_ascii=True).encode()
        except BaseException as exc:  # noqa: BLE001 - fail safe: original bytes
            log(f"annotate failed: {type(exc).__name__}")
            return line

    # -- B10 ----------------------------------------------------------------
    def teardown(self, why: str) -> None:
        try:
            if self.child.stdin and not self.child.stdin.closed:
                self.child.stdin.close()
        except OSError:
            pass
        try:
            self.child.wait(timeout=0.2)
        except subprocess.TimeoutExpired:
            pass
        if self.child.poll() is None:
            try:
                os.killpg(self.pgid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.child.wait(timeout=self.grace)
            except subprocess.TimeoutExpired:
                log(f"group {self.pgid} survived SIGTERM; SIGKILL sent")
                try:
                    os.killpg(self.pgid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    self.child.wait(timeout=self.grace)
                except subprocess.TimeoutExpired:
                    pass
        rc = self.child.returncode
        if rc is None:
            rc = 1
        sig = -rc if rc < 0 else 0
        log(f"child exited rc={rc} signal={sig} ({why})")
        code = rc if rc >= 0 else 128 - rc
        sys.stderr.flush()
        try:
            self.out.flush()
        except (OSError, ValueError):
            pass
        os._exit(code)

    # -- B4 -- the single loop ------------------------------------------------
    def run(self) -> None:
        sel = selectors.DefaultSelector()
        stdin_fd = sys.stdin.buffer.fileno()
        child_fd = self.child.stdout.fileno()
        sel.register(stdin_fd, selectors.EVENT_READ, "client")
        sel.register(child_fd, selectors.EVENT_READ, "server")
        bufs = {"client": bytearray(), "server": bytearray()}
        discarding = {"client": False, "server": False}

        def on_signal(_signum: int, _frame: Any) -> None:
            self.teardown("signal")

        signal.signal(signal.SIGTERM, on_signal)
        signal.signal(signal.SIGINT, on_signal)
        while True:
            try:
                for key, _mask in sel.select():
                    side = key.data
                    fd = key.fd
                    try:
                        data = os.read(fd, 65536)
                    except OSError:
                        data = b""
                    if not data:
                        sel.unregister(fd)
                        if side == "client":
                            self.stdin_open = False
                            self.teardown("stdin EOF")
                        else:
                            self.child_open = False
                            self.teardown("child stdout EOF")
                        return
                    buf = bufs[side]
                    buf += data
                    while True:
                        nl = buf.find(b"\n")
                        if nl < 0:
                            if len(buf) > MAX_LINE_BYTES and not discarding[side]:
                                discarding[side] = True
                                log(f"discarding oversize {side} line (> {MAX_LINE_BYTES} bytes, buffered {len(buf)})")
                                if side == "server":
                                    for k, (_m, tool) in list(self.pending.items()):
                                        write_line(self.out, error_result(k[1], tool, "oversize"))
                                        self.pending.pop(k, None)
                                del buf[:]
                            elif discarding[side]:
                                del buf[:]
                            break
                        line = bytes(buf[:nl])
                        del buf[: nl + 1]
                        if discarding[side]:
                            discarding[side] = False
                            continue
                        if side == "client":
                            self.pump_client_to_server(line)
                        else:
                            self.pump_server_to_client(line)
            except BaseException as exc:  # noqa: BLE001 - a dead pump is a silent hang
                if isinstance(exc, SystemExit):
                    raise
                log(f"pump error: {type(exc).__name__}: {exc}")
                if not self.stdin_open or self.child.poll() is not None:
                    self.teardown("pump error after EOF")
                    return


def main(argv: List[str]) -> int:
    server = parse_argv(argv)
    redactor = load_redactor()
    self_test(redactor[0], redactor[1], redactor[3])
    refuse_argv_and_env(server, dict(os.environ))
    Proxy(server, redactor).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

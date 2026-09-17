#!/usr/bin/env python3
"""Redacting stdio JSON-RPC proxy in front of the Playwright MCP server (#7980).

    python3 playwright-mcp-redact-proxy.py -- npx @playwright/mcp@0.0.78 [server args...]

Sits on the transport between Claude Code and the server and rewrites the text of
every `tools/call` result through the SAME `redact_text` the agent-browser Bash
path uses (loaded by path from the sibling `redact-a11y-snapshot.py`; this file
defines no predicate of its own). Three fail-closed arms, no bypass variable:

  * startup  -- `refuse_argv_and_env`, `load_redactor`, `self_test`: stderr
                `refusing to start: <reason>`, exit 2, no child spawned;
  * per call -- `refuse_request` / `rewrite_result`: an `isError` result naming the
                tool, built by `error_result`, whose reason never quotes input;
  * transport -- `teardown`: the child's whole process group is ended on stdin
                EOF, a signal, or child exit, with the child's exit code clamped.

Reasons never quote page content, on stdout or stderr: Claude Code persists this
process's stderr (and the server's, which it inherits) under
`~/.cache/claude-cli-nodejs/<project>/mcp-logs-playwright/*.jsonl`.

Decision, reach per surface, the enumerated raw-sink closure and the named
residuals: ADR-213 (#7980 addendum) and `agent-browser/SKILL.md` §"Wrapping the
server". Stdlib only, single `selectors` loop, POSIX.
"""
from __future__ import annotations

import importlib.util
import json
import os
import selectors
import signal
import subprocess
import sys
import time
from typing import Any, Dict, List, NoReturn, Optional, Tuple

PREFIX = "playwright-mcp-redact-proxy:"
REDACTOR_BASENAME = "redact-a11y-snapshot.py"
# 64 MiB per line: a memory budget. A hostile page can inflate a tree and an
# OOM-killed proxy runs no teardown (CWE-400). A line whose newline arrives in the
# same read that crosses the cap is still parsed whole, so the real ceiling is
# the cap plus one read (READ_CHUNK); the 4 MiB result cap then withholds it.
MAX_LINE_BYTES = 64 * 1024 * 1024
READ_CHUNK = 65536
# Seconds between SIGTERM and SIGKILL for the child's process group. The suite
# shortens it with PLAYWRIGHT_MCP_PROXY_GRACE_S; it changes timing only.
GRACE_S = 5.0
STDIN_CLOSE_WAIT_S = 0.2
REFUSED_HEAD = "refused by playwright-mcp-redact-proxy:"
WITHHELD_HEAD = "withheld by playwright-mcp-redact-proxy:"
TOOLS_LIST_MARKER = (
    " [Soleur: output is redacted in flight by the a11y-snapshot redactor;"
    " filename is refused — call browser_snapshot with no filename.]"
)
TRAILER = "[Soleur: redacted in flight by playwright-mcp-redact-proxy]"
REFUSED_NEXT = "Behind this proxy call browser_snapshot with no filename, and call tools without _meta."
WITHHELD_NEXT = (
    "The tool itself may have run: its result was withheld, not its action. Before"
    " retrying, call browser_snapshot with no filename to see the page state. If"
    " browser_snapshot is over the redactor's size cap, narrow it with target: or depth:."
)
SNAPSHOT_LINK_NOTICE = (
    "- [Snapshot withheld by playwright-mcp-redact-proxy: the server wrote a raw tree"
    " file under its output directory (default .playwright-mcp/); do not read it]"
)
UNRECOGNISED = "unrecognised result shape"
RESULT_KEYS = {"content", "isError", "isClose"}
TEXT_KEYS = {"type", "text", "annotations"}
BINARY_KEYS = {"type", "data", "mimeType", "annotations"}
ERROR_KEYS = {"code", "message"}
# Server-to-client messages relayed, each rebuilt from its method and ids only
# (`relay_server_message`). 0.0.78 emits no notification at all and one server
# request, `roots/list`; anything else could carry page text around the rewrite,
# so it is dropped (a request is answered on the server's side so the server
# does not wait on it).
PASSTHROUGH_REQUESTS = {"roots/list"}
PASSTHROUGH_NOTIFICATIONS = {"notifications/tools/list_changed", "notifications/cancelled"}
# `--caps` values that open no raw sink: `vision` adds coordinate tools. devtools
# (tracing, annotate), pdf and storage write raw page state the proxy never sees.
SAFE_CAPS = {"vision"}


def log(msg: str) -> None:
    sys.stderr.write(f"{PREFIX} {msg}\n")
    sys.stderr.flush()


def refuse_start(reason: str) -> NoReturn:
    log(f"refusing to start: {reason}")
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
    except BaseException as exc:  # noqa: BLE001 - a module-level sys.exit is a refusal too
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
def argv_values(server: List[str], flag: str) -> List[str]:
    """Every value given to `flag` as `--flag v` or `--flag=v`, in order."""
    values: List[str] = []
    for i, a in enumerate(server):
        if a.startswith(flag + "="):
            values.append(a[len(flag) + 1 :])
        elif a == flag and i + 1 < len(server):
            values.append(server[i + 1])
    return values


def debug_pattern_enables_pw(pattern: str) -> bool:
    """True when a `debug` namespace pattern can enable any `pw:` logger.

    The `debug` package splits DEBUG on whitespace and commas, skips `-`-prefixed
    exclusions, and treats `*` as its only wildcard, matching anywhere. So a
    pattern enables some `pw:<x>` namespace iff it reaches a `*` before
    diverging from `pw:`, or consumes `pw:` literally.
    """
    target = "pw:"
    for i, ch in enumerate(pattern):
        if ch == "*":
            return True
        if i >= len(target):
            return True
        if ch != target[i]:
            return False
    return False


def caps_open_sinks(values: List[str]) -> bool:
    for v in values:
        for cap in v.replace(",", " ").split():
            if cap not in SAFE_CAPS:
                return True
    return False


def refuse_argv_and_env(server: List[str], env: Dict[str, str]) -> None:
    if "--save-session" in server:
        refuse_start("--save-session writes every response to a session.md on disk")
    if argv_values(server, "--port") or "--port" in server or env.get("PLAYWRIGHT_MCP_PORT"):
        refuse_start("--port serves the tools over HTTP, around this stdio relay")
    if argv_values(server, "--host") or "--host" in server or env.get("PLAYWRIGHT_MCP_HOST"):
        refuse_start("--host binds an HTTP transport around this stdio relay")
    if caps_open_sinks(argv_values(server, "--caps")) or caps_open_sinks([env.get("PLAYWRIGHT_MCP_CAPS", "")]):
        refuse_start("--caps enables a capability other than vision (devtools, pdf and storage write raw page state)")
    if any(v != "stdout" for v in argv_values(server, "--output-mode")):
        refuse_start("--output-mode file writes snapshots and logs to disk")
    config_path: Optional[str] = None
    named = argv_values(server, "--config")
    if named:
        config_path = named[-1]
    elif env.get("PLAYWRIGHT_MCP_CONFIG"):
        config_path = env["PLAYWRIGHT_MCP_CONFIG"]
    if config_path:
        if not os.path.isfile(config_path):
            refuse_start("the config file named by --config or PLAYWRIGHT_MCP_CONFIG does not exist")
        try:
            with open(config_path, "rb") as fh:
                cfg = json.loads(fh.read().decode("utf-8-sig"))
        except (OSError, ValueError, RecursionError):
            # The server falls back to an INI parser, where saveSession is a typed
            # key; a file this proxy cannot read is a file it cannot vet.
            refuse_start("the config file is not JSON, so its raw-sink settings cannot be checked")
        if not isinstance(cfg, dict):
            refuse_start("the config file is not a JSON object, so its raw-sink settings cannot be checked")
        if cfg.get("saveSession"):
            refuse_start("config saveSession is set (a raw session.md sink)")
        if cfg.get("saveVideo"):
            refuse_start("config saveVideo is set (video frames of every page are written to disk)")
        caps = cfg.get("capabilities")
        if caps is not None and (not isinstance(caps, list) or caps_open_sinks([str(c) for c in caps])):
            refuse_start("config capabilities enables a capability other than vision")
        srv = cfg.get("server")
        if isinstance(srv, dict) and (srv.get("port") is not None or srv.get("host") is not None):
            refuse_start("config server.port/server.host serves the tools over HTTP, around this stdio relay")
    patterns = env.get("DEBUG", "").replace(",", " ").split()
    if any(debug_pattern_enables_pw(p) for p in patterns if not p.startswith("-")):
        refuse_start("DEBUG enables a pw:* logger, which prints unredacted results to stderr")
    if env.get("DEBUG_FILE"):
        refuse_start("DEBUG_FILE is set (a raw debug sink on disk)")


# ---------------------------------------------------------------------------
# B9 -- ONE builder for every synthesized client-bound tools/call result
# ---------------------------------------------------------------------------
def error_result(rid: Any, tool: str, reason: str, *, refused: bool = False) -> bytes:
    kind = "refused" if refused else "withheld"
    head = REFUSED_HEAD if refused else WITHHELD_HEAD
    text = f"### Error\n{head} {reason} (tool: {tool})\n{REFUSED_NEXT if refused else WITHHELD_NEXT}"
    log(f"{kind} tool={tool} reason={reason}")
    obj = {"jsonrpc": "2.0", "id": rid, "result": {"content": [{"type": "text", "text": text}], "isError": True}}
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode()


def jsonrpc_error(rid: Any, code: int, message: str) -> bytes:
    obj = {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode()


def write_line(fobj: Any, data: bytes) -> None:
    fobj.write(data + b"\n")
    fobj.flush()


# ---------------------------------------------------------------------------
# B5 -- client -> server
# ---------------------------------------------------------------------------
def id_key(rid: Any) -> str:
    """The JSON text of the id: keeps 2 and "2" apart and is hashable for any id shape."""
    return json.dumps(rid, sort_keys=True)


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
        # measured: `_meta.json` returns the tree as one JSON-escaped string the
        # line-anchored predicate cannot see.
        return error_result(req.get("id"), name, "arguments._meta is an undocumented hook that returns the tree in a shape the redactor cannot see; call the tool without _meta", refused=True)
    if name == "browser_snapshot" and "filename" in args:
        return error_result(req.get("id"), name, "filename writes the raw tree to disk; call browser_snapshot with no filename", refused=True)
    return None


def json_strings(node: Any) -> List[str]:
    if isinstance(node, str):
        return [node]
    if isinstance(node, dict):
        return [s for v in node.values() for s in json_strings(v)]
    if isinstance(node, list):
        return [s for v in node for s in json_strings(v)]
    return []


class Proxy:
    def __init__(self, server: List[str], redactor: Tuple[Any, Any, int, str]) -> None:
        self.redact_text, self.looks_like_a11y_tree, self.max_input_bytes, self.redacted = redactor
        self.pending: Dict[str, Tuple[Any, str, str]] = {}  # id_key -> (raw id, method, tool name)
        self.out = sys.stdout.buffer
        self.child: Optional[subprocess.Popen] = None
        self.pgid = 0
        self.tearing_down = False
        self.grace = GRACE_S
        try:
            self.grace = float(os.environ.get("PLAYWRIGHT_MCP_PROXY_GRACE_S", GRACE_S))
        except ValueError:
            log("ignored a non-numeric PLAYWRIGHT_MCP_PROXY_GRACE_S")
        # Installed BEFORE the spawn, so a signal in between still ends the group.
        signal.signal(signal.SIGTERM, self.on_signal)
        signal.signal(signal.SIGINT, self.on_signal)
        argv = list(server) + ["--snapshot-mode", "none"]
        self.child = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None, bufsize=0, start_new_session=True)
        self.pgid = os.getpgid(self.child.pid)
        log(f"child pgid {self.pgid}")

    def on_signal(self, _signum: int, _frame: Any) -> None:
        self.teardown("signal")

    # -- B5 -----------------------------------------------------------------
    def pump_client_to_server(self, line: bytes) -> None:
        assert self.child is not None and self.child.stdin is not None
        try:
            req = json.loads(line.decode("utf-8", errors="replace"))
        except (ValueError, RecursionError):
            # Never forwarded: a line this proxy cannot read is a line it cannot
            # vet for filename/_meta, and a JSON parser the server uses may still
            # accept it (e.g. an integer past Python's digit limit).
            log(f"dropped unparsable client line ({len(line)} bytes)")
            return
        if isinstance(req, list):
            log(f"dropped list line from client ({len(line)} bytes)")
            return
        if not isinstance(req, dict):
            log(f"dropped non-object client line ({len(line)} bytes)")
            return
        refusal = refuse_request(req)
        if refusal is not None:
            write_line(self.out, refusal)
            return
        if "method" in req and "id" in req:
            rid = req["id"]
            key = id_key(rid)
            if key in self.pending:
                log("refused a request reusing a pending id")
                write_line(self.out, jsonrpc_error(rid, -32600, "request id is already pending (refused by playwright-mcp-redact-proxy)"))
                return
            params = req.get("params") if isinstance(req.get("params"), dict) else {}
            self.pending[key] = (rid, str(req["method"]), str(params.get("name", "")))
        write_line(self.child.stdin, line)

    # -- B6/B7/B8 -----------------------------------------------------------
    def pump_server_to_client(self, line: bytes) -> None:
        try:
            msg = json.loads(line.decode("utf-8", errors="replace"))
        except (ValueError, RecursionError):
            log(f"dropped unparsable server line ({len(line)} bytes)")
            return
        if isinstance(msg, list):
            answered = 0
            for el in msg:
                if isinstance(el, dict) and ("result" in el or "error" in el):
                    entry = self.pending.pop(self.safe_key(el.get("id")), None)
                    if entry is not None:
                        write_line(self.out, error_result(entry[0], entry[2], "the server answered inside a JSON list line, which the proxy does not relay"))
                        answered += 1
            log(f"dropped list line from server ({len(line)} bytes, {answered} pending answered)")
            return
        if not isinstance(msg, dict):
            log(f"dropped non-object server line ({len(line)} bytes)")
            return
        if "result" not in msg and "error" not in msg:
            self.relay_server_message(msg)
            return
        entry = self.pending.pop(self.safe_key(msg.get("id")), None)
        if entry is None:
            log(f"dropped unknown-id response ({len(line)} bytes)")
            return
        rid, method, tool = entry
        if "method" in msg:
            write_line(self.out, error_result(rid, tool, UNRECOGNISED + " (response carries a method)"))
            return
        result = msg.get("result")
        if method == "tools/call" or (isinstance(result, dict) and "content" in result):
            # Routed by SHAPE as well as by method: a content-bearing result is
            # rewritten whatever request it answers.
            write_line(self.out, self.rewrite_result(msg, line, tool))
        elif "error" in msg:
            write_line(self.out, self.vet_error(msg, line, tool))
        elif method == "tools/list":
            write_line(self.out, self.annotate_tools_list(msg, line))
        elif method == "initialize":
            info = result if isinstance(result, dict) else {}
            si = info.get("serverInfo", {}) if isinstance(info.get("serverInfo"), dict) else {}
            log(f"wrapping {si.get('name', '?')} {si.get('version', '?')} protocol {info.get('protocolVersion', '?')}")
            write_line(self.out, line)
        else:
            write_line(self.out, line)

    def safe_key(self, rid: Any) -> str:
        try:
            return id_key(rid)
        except (TypeError, ValueError):
            return "\x00unkeyable"

    def plain_id(self, value: Any) -> bool:
        """An id the proxy may echo: an integer, or a string with no tree row or redactable value."""
        if isinstance(value, bool):
            return False
        if isinstance(value, int):
            return True
        return isinstance(value, str) and not self.looks_like_a11y_tree(value) and self.redact_text(value) == value

    def relay_server_message(self, msg: Dict[str, Any]) -> None:
        """A server request or notification: relay only the ones 0.0.78 can send,
        rebuilt from method and ids alone so no params field (a cancel reason, a
        _meta) carries page text past the proxy."""
        method = msg.get("method")
        if "id" in msg:
            if method in PASSTHROUGH_REQUESTS and self.plain_id(msg.get("id")):
                write_line(self.out, json.dumps({"jsonrpc": "2.0", "id": msg["id"], "method": method}, separators=(",", ":")).encode())
                return
            log("dropped a server request other than roots/list")
            assert self.child is not None and self.child.stdin is not None
            try:
                write_line(self.child.stdin, jsonrpc_error(msg.get("id"), -32601, "method not relayed by playwright-mcp-redact-proxy"))
            except (OSError, ValueError):
                pass
            return
        if method in PASSTHROUGH_NOTIFICATIONS:
            rebuilt: Dict[str, Any] = {"jsonrpc": "2.0", "method": method}
            params = msg.get("params")
            if method == "notifications/cancelled":
                if not isinstance(params, dict) or not self.plain_id(params.get("requestId")):
                    log("dropped a cancellation whose requestId is not a plain id")
                    return
                rebuilt["params"] = {"requestId": params["requestId"]}
            write_line(self.out, json.dumps(rebuilt, separators=(",", ":")).encode())
            return
        log("dropped a server notification outside the relayed set")

    def vet_error(self, msg: Dict[str, Any], line: bytes, tool: str) -> bytes:
        err = msg.get("error")
        if "result" in msg or not isinstance(err, dict) or not set(err.keys()) <= ERROR_KEYS:
            return error_result(msg.get("id"), tool, "error response had an unrecognised shape")
        message = err.get("message", "")
        if not isinstance(message, str) or self.looks_like_a11y_tree(message) or self.redact_text(message) != message:
            return error_result(msg.get("id"), tool, "error message carried tree-shaped text")
        return line

    def escaped_tree_in(self, text: str) -> bool:
        """True when a `### Result` body (or a JSON line) carries a JSON-escaped tree.

        `browser_run_code_unsafe` and `browser_evaluate` return JSON; an
        `ariaSnapshot()` returned that way is one escaped string the line-anchored
        predicate cannot see, the same shape the `_meta` refusal exists for.
        """
        candidates: List[str] = []
        section: List[str] = []
        in_result = False
        for tline in text.split("\n") + ["### end"]:
            if tline.startswith("### "):
                if in_result:
                    candidates.append("\n".join(section))
                in_result = tline == "### Result"
                section = []
            elif in_result:
                section.append(tline)
            stripped = tline.strip().rstrip(",")
            if stripped[:1] in ('"', "{", "["):
                candidates.append(stripped)
                if stripped.startswith('"') and '":' in stripped:
                    candidates.append("{" + stripped + "}")
        for cand in candidates:
            try:
                parsed = json.loads(cand)
            except (ValueError, RecursionError):
                continue
            # No newline requirement: one row returned by `ariaSnapshot()` on a
            # single locator is a whole tree to the redactor's predicate.
            if any(self.looks_like_a11y_tree(s) for s in json_strings(parsed)):
                return True
        return False

    def rewrite_result(self, msg: Dict[str, Any], line: bytes, tool: str) -> bytes:
        rid = msg.get("id")
        try:
            if "error" in msg:
                return self.vet_error(msg, line, tool)
            result = msg.get("result")
            if not isinstance(result, dict) or not set(result.keys()) <= RESULT_KEYS:
                return error_result(rid, tool, UNRECOGNISED)
            if not isinstance(result.get("isError", False), bool):
                return error_result(rid, tool, UNRECOGNISED)
            content = result.get("content")
            if not isinstance(content, list):
                return error_result(rid, tool, UNRECOGNISED)
            changed = False
            tree_seen = False
            new_content: List[Dict[str, Any]] = []
            for block in content:
                if not isinstance(block, dict):
                    return error_result(rid, tool, UNRECOGNISED)
                btype = block.get("type")
                if btype == "text":
                    if not set(block.keys()) <= TEXT_KEYS or not isinstance(block.get("text"), str):
                        return error_result(rid, tool, UNRECOGNISED)
                    text = block["text"]
                    if len(text.encode("utf-8", "surrogatepass")) > self.max_input_bytes:
                        return error_result(rid, tool, "result exceeds the redactor's size cap")
                    if self.escaped_tree_in(text):
                        return error_result(rid, tool, "result carries a JSON-escaped accessibility tree")
                    lines = text.split("\n")
                    in_snapshot = False
                    for i, tline in enumerate(lines):
                        if tline.startswith("### "):
                            in_snapshot = tline == "### Snapshot"
                        elif in_snapshot and tline.startswith("- [Snapshot]("):
                            # The disk sink reappearing (a version bump). The file
                            # is already written; hide the path, keep the result.
                            lines[i] = SNAPSHOT_LINK_NOTICE
                            log(f"replaced a snapshot file link tool={tool}")
                    relinked = "\n".join(lines)
                    if self.looks_like_a11y_tree(relinked):
                        tree_seen = True
                    new_text = self.redact_text(relinked)
                    if new_text != text:
                        changed = True
                        block = dict(block)
                        block["text"] = new_text
                elif btype in ("image", "audio"):
                    if not set(block.keys()) <= BINARY_KEYS:
                        return error_result(rid, tool, UNRECOGNISED)
                else:
                    return error_result(rid, tool, UNRECOGNISED)
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
            return json.dumps(out, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode()
        except Exception as exc:  # noqa: BLE001 - any failure withholds
            return error_result(rid, tool, f"redaction raised {type(exc).__name__}")

    def annotate_tools_list(self, msg: Dict[str, Any], line: bytes) -> bytes:
        try:
            for t in msg["result"]["tools"]:
                if t.get("name") == "browser_snapshot" and isinstance(t.get("description"), str):
                    t["description"] = t["description"] + TOOLS_LIST_MARKER
            return json.dumps(msg, separators=(",", ":"), ensure_ascii=True).encode()
        except Exception as exc:  # noqa: BLE001 - fail safe: original bytes (no content key reaches here)
            log(f"annotate failed: {type(exc).__name__}")
            return line

    # -- B10 ----------------------------------------------------------------
    def group_alive(self) -> bool:
        try:
            os.killpg(self.pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def wait_group_empty(self, seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.child is not None and self.child.poll() is None:
                try:
                    self.child.wait(timeout=0.05)
                except subprocess.TimeoutExpired:
                    pass
            if not self.group_alive():
                return True
            time.sleep(0.05)
        return not self.group_alive()

    def teardown(self, why: str) -> NoReturn:
        if self.tearing_down:
            os._exit(1)
        self.tearing_down = True
        child = self.child
        if child is None:
            log(f"no child to tear down ({why})")
            os._exit(1)
        try:
            if child.stdin and not child.stdin.closed:
                child.stdin.close()
        except OSError:
            pass
        try:
            child.wait(timeout=STDIN_CLOSE_WAIT_S)
        except subprocess.TimeoutExpired:
            pass
        # Always signal the GROUP: the direct child (npx) may already have exited
        # while Chrome, its grandchild, still holds the group.
        try:
            os.killpg(self.pgid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if not self.wait_group_empty(self.grace):
            log(f"group {self.pgid} survived SIGTERM; SIGKILL sent")
            try:
                os.killpg(self.pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.wait_group_empty(self.grace)
        try:
            child.wait(timeout=self.grace)
        except subprocess.TimeoutExpired:
            pass
        rc = child.returncode
        if rc is None:
            rc = 1
        sig = -rc if rc < 0 else 0
        log(f"child exited rc={rc} signal={sig} ({why})")
        code = rc if rc >= 0 else 128 - rc
        try:
            self.out.flush()
        except (OSError, ValueError):
            pass
        os._exit(code)

    # -- B4 -- the single loop ------------------------------------------------
    def run(self) -> NoReturn:
        assert self.child is not None and self.child.stdout is not None
        sel = selectors.DefaultSelector()
        sel.register(sys.stdin.buffer.fileno(), selectors.EVENT_READ, "client")
        sel.register(self.child.stdout.fileno(), selectors.EVENT_READ, "server")
        bufs = {"client": bytearray(), "server": bytearray()}
        discarding = {"client": False, "server": False}
        while True:
            for key, _mask in sel.select():
                side = key.data
                try:
                    data = os.read(key.fd, READ_CHUNK)
                except OSError:
                    data = b""
                if not data:
                    self.teardown("stdin EOF" if side == "client" else "child stdout EOF")
                buf = bufs[side]
                buf += data
                while True:
                    nl = buf.find(b"\n")
                    if nl < 0:
                        if len(buf) > MAX_LINE_BYTES and not discarding[side]:
                            discarding[side] = True
                            log(f"discarding oversize {side} line (> {MAX_LINE_BYTES} bytes, buffered {len(buf)})")
                            if side == "server":
                                for k, (rid, _m, tool) in list(self.pending.items()):
                                    write_line(self.out, error_result(rid, tool, "oversize"))
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
                    try:
                        if side == "client":
                            self.pump_client_to_server(line)
                        else:
                            self.pump_server_to_client(line)
                    except Exception as exc:  # noqa: BLE001 - one bad line must not strand the lines behind it
                        log(f"pump error: {type(exc).__name__}")
                        if self.child.poll() is not None:
                            self.teardown("pump error after child exit")


def main(argv: List[str]) -> int:
    server = parse_argv(argv)
    redactor = load_redactor()
    self_test(redactor[0], redactor[1], redactor[3])
    refuse_argv_and_env(server, dict(os.environ))
    Proxy(server, redactor).run()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

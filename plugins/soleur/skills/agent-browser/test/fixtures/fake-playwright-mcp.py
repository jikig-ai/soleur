#!/usr/bin/env python3
"""Table-driven stub of @playwright/mcp for the proxy suite (#7980). stdlib only.

Answers initialize / tools/list / tools/call from FAKE_PW_FIXTURE_DIR (default:
the sibling playwright-mcp-<pin>/ directory) keyed by tool name. Odd shapes come
from FAKE_PW_RESULT_FILE: a JSON file holding "result" or "error" (used for the
next tools/call), "raw_b64" (bytes emitted verbatim, "{id}" substituted), or
"list_of": [tool, tool] (two pending calls answered by ONE JSON-array line).
Flags only where a file cannot express the behaviour: FAKE_PW_ROOTS_COLLIDE,
FAKE_PW_ARGV_OUT, FAKE_PW_REQUEST_LOG, FAKE_PW_EXIT_CODE, FAKE_PW_HOLD,
FAKE_PW_UNPROMPTED, FAKE_PW_OVERSIZE. `browser_snapshot` with a `filename`
argument WRITES the raw fixture tree to that path (as the real server does).
"""
import base64, json, os, signal, subprocess, sys, time  # noqa: E401

E = os.environ
HERE = os.path.dirname(os.path.abspath(__file__))
FX = E.get("FAKE_PW_FIXTURE_DIR") or os.path.join(HERE, "playwright-mcp-0.0.78")
TOOL_FILE = {"browser_navigate": "navigate", "browser_snapshot": "snapshot", "browser_find": "find",
             "browser_evaluate": "evaluate", "browser_take_screenshot": "screenshot", "browser_close": "close"}
out = sys.stdout.buffer
if E.get("FAKE_PW_ARGV_OUT"):
    open(E["FAKE_PW_ARGV_OUT"], "w").write("\n".join(sys.argv[1:]) + "\n")
if E.get("FAKE_PW_HOLD"):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    hold = subprocess.Popen(["sleep", "300"])  # models Chrome: same group, outlives EOF


def fixture(name):
    return json.load(open(os.path.join(FX, name + ".json")))


def emit(obj):
    out.write(json.dumps(obj, separators=(",", ":")).encode() + b"\n"); out.flush()


def respond(rid, result):
    emit({"jsonrpc": "2.0", "id": rid, "result": result})


pending_list = []
first_call_done = False
for raw in sys.stdin.buffer:
    try:
        req = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        emit({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}); continue
    if not isinstance(req, dict) or "method" not in req:
        continue
    method, rid, params = req["method"], req.get("id"), req.get("params") or {}
    if E.get("FAKE_PW_REQUEST_LOG"):
        with open(E["FAKE_PW_REQUEST_LOG"], "a") as fh:
            fh.write(json.dumps({"method": method, "name": params.get("name"), "arguments": params.get("arguments")}) + "\n")
    if method == "initialize":
        respond(rid, fixture("initialize")["result"])
    elif method == "tools/list":
        respond(rid, fixture("tools-list")["result"])
    elif method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if E.get("FAKE_PW_ROOTS_COLLIDE"):
            emit({"jsonrpc": "2.0", "id": rid, "method": "roots/list"})
        if E.get("FAKE_PW_UNPROMPTED"):
            respond(999, fixture("snapshot")["result"])
        if E.get("FAKE_PW_OVERSIZE"):
            head = json.dumps({"jsonrpc": "2.0", "id": rid, "result": {"content": [{"type": "text", "text": ""}]}}, separators=(",", ":"))
            pad = int(E["FAKE_PW_OVERSIZE"]) - len(head)
            out.write(head[:-len('"}]}}')].encode() + b"A" * pad + b'"}]}}\n'); out.flush()
        elif E.get("FAKE_PW_RESULT_FILE"):
            odd = json.load(open(E["FAKE_PW_RESULT_FILE"]))
            if "list_of" in odd:
                pending_list.append(rid)
                if len(pending_list) == 2:
                    out.write(json.dumps([{"jsonrpc": "2.0", "id": i, "result": fixture(t)["result"]} for i, t in zip(pending_list, odd["list_of"])]).encode() + b"\n"); out.flush()
            elif "raw_b64" in odd:
                out.write(base64.b64decode(odd["raw_b64"]).replace(b"{id}", json.dumps(rid).encode()) + b"\n"); out.flush()
            elif "error" in odd:
                emit({"jsonrpc": "2.0", "id": rid, "error": odd["error"]})
            else:
                emit({"jsonrpc": "2.0", "id": rid, "result": odd["result"], **({"method": odd["method"]} if "method" in odd else {})})
        else:
            if name == "browser_snapshot" and args.get("filename"):
                tree = fixture("snapshot-meta-raw")["result"]["content"][0]["text"]
                open(args["filename"], "w").write(tree)
                respond(rid, fixture("snapshot-filename")["result"])
            elif name == "browser_snapshot" and "_meta" in args:
                respond(rid, fixture("snapshot-meta-json")["result"])
            else:
                respond(rid, fixture(TOOL_FILE.get(name, "navigate"))["result"])
        if E.get("FAKE_PW_EXIT_CODE") and not first_call_done:
            sys.exit(int(E["FAKE_PW_EXIT_CODE"]))
        first_call_done = True
if E.get("FAKE_PW_HOLD"):
    while True:
        time.sleep(1)  # ignore EOF; only SIGKILL ends this group

#!/usr/bin/env python3
"""Table-driven stub of @playwright/mcp for the proxy suite (#7980). stdlib only.

Answers initialize / tools/list / tools/call from FAKE_PW_FIXTURE_DIR (REQUIRED:
the suite derives it from the .mcp.json pin, so a version bump cannot silently
serve the previous version's captures) keyed by tool name. Odd shapes come
from FAKE_PW_RESULT_FILE: a JSON file holding "result" or "error" (used for the
next tools/call), "raw_b64" (bytes emitted verbatim, "{id}" substituted), or
"list_of": [tool, tool] (two pending calls answered by ONE JSON-array line).
Flags only where a file cannot express the behaviour: FAKE_PW_ROOTS_COLLIDE,
FAKE_PW_ARGV_OUT, FAKE_PW_REQUEST_LOG, FAKE_PW_EXIT_CODE, FAKE_PW_HOLD,
FAKE_PW_UNPROMPTED, FAKE_PW_OVERSIZE, FAKE_PW_NOTIFY (a notifications/message
carrying a tree before the result), FAKE_PW_CANCEL (relayed-set notifications whose
reason, _meta and requestId carry tree text), FAKE_PW_SERVER_REQUEST (a sampling/createMessage
request carrying a tree), FAKE_PW_GRANDCHILD (the direct child exits on EOF while a
SIGTERM-ignoring grandchild holds the group). `browser_snapshot` with a `filename`
argument WRITES the raw fixture tree to that path (as the real server does).
"""
import base64, json, os, signal, subprocess, sys, time  # noqa: E401

E = os.environ
HERE = os.path.dirname(os.path.abspath(__file__))
if not E.get("FAKE_PW_FIXTURE_DIR"):
    sys.stderr.write("fake-playwright-mcp: FAKE_PW_FIXTURE_DIR is not set (derive it from the .mcp.json pin)\n")
    sys.exit(64)
FX = E["FAKE_PW_FIXTURE_DIR"]
TOOL_FILE = {"browser_navigate": "navigate", "browser_snapshot": "snapshot", "browser_find": "find",
             "browser_evaluate": "evaluate", "browser_take_screenshot": "screenshot", "browser_close": "close"}
out = sys.stdout.buffer
if E.get("FAKE_PW_ARGV_OUT"):
    open(E["FAKE_PW_ARGV_OUT"], "w").write("\n".join(sys.argv[1:]) + "\n")
if E.get("FAKE_PW_HOLD"):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    hold = subprocess.Popen(["sleep", "300"])  # models Chrome: same group, outlives EOF
if E.get("FAKE_PW_GRANDCHILD"):
    # the grandchild ignores SIGTERM, so only a group SIGKILL ends it
    grandchild = subprocess.Popen(["sh", "-c", "trap '' TERM; exec sleep 300"])


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
    if not isinstance(req, dict):
        continue
    if "method" not in req:
        if E.get("FAKE_PW_REQUEST_LOG"):
            with open(E["FAKE_PW_REQUEST_LOG"], "a") as fh:
                fh.write(json.dumps({"response_id": req.get("id"), "error": "error" in req}) + "\n")
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
        tree = fixture("snapshot")["result"]["content"][0]["text"]
        if E.get("FAKE_PW_NOTIFY"):
            emit({"jsonrpc": "2.0", "method": "notifications/message", "params": {"level": "info", "data": tree}})
        if E.get("FAKE_PW_CANCEL"):
            row = next(l for l in tree.splitlines() if "ZZQP-SENTINEL-7980" in l).strip()
            emit({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": rid, "reason": tree}})
            emit({"jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": {"_meta": {"note": tree}}})
            emit({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": row}})
        if E.get("FAKE_PW_SERVER_REQUEST"):
            emit({"jsonrpc": "2.0", "id": "srv-1", "method": "sampling/createMessage", "params": {"messages": [{"role": "user", "content": {"type": "text", "text": tree}}], "maxTokens": 1}})
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

#!/usr/bin/env python3
"""Read one fact out of a proxy-session-driver output dir (#7980). stdlib only.

    session-facts.py <out-dir> <id-json> <field>

Fields (printed on stdout):
  found      1 if a RESPONSE (result/error) with that id was captured, else 0
  count      how many responses carried that id
  jsonrpc_error  1 if the first response for that id is a JSON-RPC `error` object, else 0
  description:<tool>  the description of <tool> in the tools/list result answering that id
  isError    true/false/none
  text       all text blocks of the result joined by "\\n"
  sentinel   occurrences of ZZQP-SENTINEL-7980 in the raw stdout line of that response
  benign     occurrences of ZZQP-BENIGN-7980 in the raw stdout line of that response
  trailer    1 if the LAST content block is the proxy trailer text, else 0
  rawline    the raw stdout line bytes of that response, base64
  lines      number of stdout lines in the whole session
  alljson    1 if every stdout line parses as a JSON object (or list), else 0
  stderr_count:<needle>   number of stderr lines containing <needle>
  expected_line <fixture.json>  base64 of the stub's serialisation of that fixture's result under <id>
"""
import base64
import json
import sys

TRAILER = "[Soleur: redacted in flight by playwright-mcp-redact-proxy]"


def main(argv):
    out, rid_json, field = argv[0], argv[1], argv[2]
    rid = json.loads(rid_json)
    raw = open(f"{out}/stdout.bin", "rb").read()
    lines = raw.split(b"\n")
    if lines and lines[-1] == b"":
        lines = lines[:-1]
    hits = []
    for l in lines:
        try:
            o = json.loads(l.decode("utf-8", "replace"))
        except ValueError:
            continue
        if isinstance(o, dict) and ("result" in o or "error" in o) and o.get("id") == rid and type(o.get("id")) is type(rid):
            hits.append((l, o))
    if field == "found":
        print(1 if hits else 0); return 0
    if field == "count":
        print(len(hits)); return 0
    if field.startswith("description:"):
        tool = field.split(":", 1)[1]
        for _l, o in hits:
            res = o.get("result")
            tools = res.get("tools") if isinstance(res, dict) else None
            for t in tools if isinstance(tools, list) else []:
                if isinstance(t, dict) and t.get("name") == tool:
                    sys.stdout.write(str(t.get("description", ""))); return 0
        return 0
    if field == "jsonrpc_error":
        print(1 if hits and "error" in hits[0][1] else 0); return 0
    if field == "lines":
        print(len(lines)); return 0
    if field == "alljson":
        ok = True
        for l in lines:
            try:
                o = json.loads(l.decode("utf-8", "replace"))
                if not isinstance(o, (dict, list)):
                    ok = False
            except ValueError:
                ok = False
        print(1 if ok else 0); return 0
    if field.startswith("stderr_count:"):
        needle = field.split(":", 1)[1]
        err = open(f"{out}/stderr.txt", "rb").read().decode("utf-8", "replace").splitlines()
        print(sum(1 for e in err if needle in e)); return 0
    if field == "expected_line":
        fx = json.load(open(argv[3]))
        line = json.dumps({"jsonrpc": "2.0", "id": rid, "result": fx["result"]}, separators=(",", ":")).encode()
        print(base64.b64encode(line).decode()); return 0
    if not hits:
        print("" if field in ("text", "rawline") else "none"); return 0
    l, o = hits[0]
    if field == "rawline":
        print(base64.b64encode(l).decode()); return 0
    if field == "sentinel":
        print(l.count(b"ZZQP-SENTINEL-7980")); return 0
    if field == "benign":
        print(l.count(b"ZZQP-BENIGN-7980")); return 0
    res = o.get("result")
    if field == "isError":
        print("none" if not isinstance(res, dict) else ("true" if res.get("isError") else "false")); return 0
    content = res.get("content") if isinstance(res, dict) else None
    blocks = content if isinstance(content, list) else []
    if field == "trailer":
        print(1 if blocks and isinstance(blocks[-1], dict) and blocks[-1].get("text") == TRAILER else 0); return 0
    if field == "text":
        sys.stdout.write("\n".join(b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text")); return 0
    sys.stderr.write(f"unknown field {field}\n"); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

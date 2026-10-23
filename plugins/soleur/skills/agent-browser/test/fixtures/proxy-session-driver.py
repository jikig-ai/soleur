#!/usr/bin/env python3
"""One proxy session for the suite (#7980). stdlib only.

    proxy-session-driver.py --out <dir> --proxy <proxy.py> --server <argv...>
        [--proxy-arg <arg>]... [--env K=V]... [--send <json-line>]... [--end eof|sigterm|sigkill|killchild|none] [--timeout S] [--expect-death]

Launches `python3 <proxy.py> <proxy-arg...> -- <server argv...>` in a NEW SESSION (so the
proxy's own pid is the group we assert on for a SIGKILLed proxy), writes each
--send line, reads until every sent request id has a reply or the timeout
lapses, then ends the session per --end and waits. With --expect-death the proxy is
expected to die at startup: the reply-wait phase is skipped (a stalled startup must
not burn a deadline window waiting for a reply that never comes) and the post---end
wait is bounded by EXPECT_DEATH_TIMEOUT_S, so a slow-but-correct death records its real
exit code instead of "TIMEOUT". Under --expect-death, --timeout still applies to the
reply drain and the group_after poll but is inert for the death wait. Writes into <out>:
  stdout.bin   every byte the proxy wrote          responses.json  parsed objects
  stderr.txt   proxy + server stderr               rc              proxy exit code
  child_pgid   the pgid the proxy logged (or "")
  group_after  member count of child_pgid after --end (polled 0.2 s up to --timeout)
Exit 0 always (the suite reads the files); usage error exits 2.
"""
from __future__ import annotations

import contextlib
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time
from pathlib import Path


EXPECT_DEATH_TIMEOUT_S = 30


def parse(argv):
    o = {"env": {}, "send": [], "end": "eof", "timeout": 8.0, "out": None, "proxy": None, "proxy_args": [], "server": [], "expect_death": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out": o["out"] = argv[i + 1]; i += 2
        elif a == "--proxy": o["proxy"] = argv[i + 1]; i += 2
        elif a == "--proxy-arg": o["proxy_args"].append(argv[i + 1]); i += 2
        elif a == "--env": k, v = argv[i + 1].split("=", 1); o["env"][k] = v; i += 2
        elif a == "--send": o["send"].append(argv[i + 1]); i += 2
        elif a == "--end": o["end"] = argv[i + 1]; i += 2
        elif a == "--timeout": o["timeout"] = float(argv[i + 1]); i += 2
        elif a == "--expect-death": o["expect_death"] = True; i += 1
        elif a == "--server": o["server"] = argv[i + 1:]; break
        else: sys.stderr.write(__doc__); sys.exit(2)
    if not (o["out"] and o["proxy"] and o["server"]): sys.stderr.write(__doc__); sys.exit(2)
    return o


def group_members(pgid):
    if not pgid: return -1
    r = subprocess.run(["pgrep", "-g", str(pgid)], capture_output=True, text=True)
    return len([l for l in r.stdout.split() if l.strip()])


def main():
    o = parse(sys.argv[1:])
    os.makedirs(o["out"], exist_ok=True)
    env = dict(os.environ); env.update(o["env"])
    err_path = os.path.join(o["out"], "stderr.txt")
    with open(err_path, "wb") as err:
        p = subprocess.Popen([sys.executable, o["proxy"]] + o["proxy_args"] + ["--"] + o["server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=err, env=env, bufsize=0, start_new_session=True)
        sel = selectors.DefaultSelector(); sel.register(p.stdout, selectors.EVENT_READ)
        buf = bytearray(); raw = bytearray(); objs = []
        want = set()
        for line in o["send"]:
            with contextlib.suppress(ValueError):
                m = json.loads(line)
                if isinstance(m, dict) and "id" in m and "method" in m: want.add(json.dumps(m["id"]))
            try:
                p.stdin.write(line.encode() + b"\n"); p.stdin.flush()
            except (BrokenPipeError, OSError):
                break
        deadline = time.monotonic() + o["timeout"]
        got = set()

        def pump(block):
            nonlocal buf
            events = sel.select(timeout=max(0.0, deadline - time.monotonic()) if block else 0)
            if not events: return False
            data = os.read(p.stdout.fileno(), 65536)
            if not data: sel.unregister(p.stdout); return None
            buf += data; raw.extend(data)
            while b"\n" in buf:
                line, _, rest = bytes(buf).partition(b"\n"); buf = bytearray(rest)
                try:
                    obj = json.loads(line.decode("utf-8", "replace")); objs.append(obj)
                    if isinstance(obj, dict) and ("result" in obj or "error" in obj): got.add(json.dumps(obj.get("id")))
                    if isinstance(obj, dict) and "method" in obj and "id" in obj:  # server request: answer roots
                        with contextlib.suppress(OSError):
                            p.stdin.write((json.dumps({"jsonrpc": "2.0", "id": obj["id"], "result": {"roots": []}}) + "\n").encode()); p.stdin.flush()
                except ValueError:
                    objs.append({"__unparsable__": line.decode("utf-8", "replace")})
            return True

        while not o["expect_death"] and want - got and time.monotonic() < deadline and p.stdout in [k.fileobj for k in sel.get_map().values()]:
            if pump(True) is None: break
        while sel.get_map() and pump(False): pass
        err.flush()
        child_pgid = ""
        m = re.search(rb"child pgid (\d+)", Path(err_path).read_bytes())
        if m: child_pgid = m.group(1).decode()
        if o["end"] == "eof":
            with contextlib.suppress(OSError):
                p.stdin.close()
        elif o["end"] == "sigterm":
            os.kill(p.pid, signal.SIGTERM)
        elif o["end"] == "killchild":  # SIGTERM the CHILD's group; the proxy must clamp the exit code
            if child_pgid:
                os.killpg(int(child_pgid), signal.SIGTERM)
        elif o["end"] == "sigkill":
            os.kill(p.pid, signal.SIGKILL)
        # drain anything the proxy still says, then wait for it. An expect-death
        # session is bounded by the death budget, not --timeout: a slow-but-correct
        # startup death must record its real rc, never the deadline's TIMEOUT.
        t_end = time.monotonic() + (EXPECT_DEATH_TIMEOUT_S if o["expect_death"] else o["timeout"])
        while time.monotonic() < t_end:
            if p.poll() is not None: break
            with contextlib.suppress(Exception):
                while sel.get_map() and pump(False): pass
            time.sleep(0.05)
        if p.poll() is None:
            p.kill(); rc = "TIMEOUT"
        else:
            rc = p.returncode
        while sel.get_map() and pump(False): pass
        # poll the child's group until empty or timeout
        n = group_members(child_pgid) if child_pgid else -1
        t2 = time.monotonic() + o["timeout"]
        while child_pgid and n > 0 and time.monotonic() < t2:
            time.sleep(0.2); n = group_members(child_pgid)
        Path(o["out"], "stdout.bin").write_bytes(bytes(raw))
        Path(o["out"], "responses.json").write_text(json.dumps(objs, indent=1, ensure_ascii=False))
        for name, val in (("rc", rc), ("child_pgid", child_pgid), ("group_after", n)):
            Path(o["out"], name).write_text(str(val) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

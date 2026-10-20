#!/usr/bin/env python3
"""Known-NEGATIVE relay for the proxy suite (#7980, QG5): spawn the server,
pump bytes both ways, rewrite nothing. Every redaction/withhold/refuse row must
be RED against this file and every must-PASS row GREEN; it is the pre-fix
artefact, never shipped."""
import os, selectors, subprocess, sys  # noqa: E401

child = subprocess.Popen(sys.argv[sys.argv.index("--") + 1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0, start_new_session=True)
sys.stderr.write(f"fake-passthrough-proxy: child pgid {os.getpgid(child.pid)}\n"); sys.stderr.flush()
sel = selectors.DefaultSelector()
sel.register(sys.stdin.buffer, selectors.EVENT_READ, "in")
sel.register(child.stdout, selectors.EVENT_READ, "out")
while sel.get_map():
    for key, _ in sel.select():
        data = os.read(key.fileobj.fileno(), 65536)
        if key.data == "in":
            if not data:
                sel.unregister(key.fileobj); child.stdin.close(); continue
            child.stdin.write(data); child.stdin.flush()
        else:
            if not data:
                sel.unregister(key.fileobj); continue
            sys.stdout.buffer.write(data); sys.stdout.buffer.flush()
sys.exit(child.wait())

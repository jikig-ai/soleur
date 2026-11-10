# Egress injector spike (#12517): summarise iron-proxy's JSON audit lines from stdin, one line per request, with
# no header or body values: method, host, path, action, status, and the first 120 characters of any error.
# Usage: ... | python3 -I lib/iron-audit.py [last N, default 6]
import json
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 6
out = []
for line in sys.stdin:
    try:
        j = json.loads(line)
    except ValueError:
        continue
    a = j.get("audit") or {}
    if a:
        err = str(j.get("error", ""))[:120]
        out.append(" ".join(str(x) for x in (a.get("method"), a.get("host"), a.get("path"), a.get("action"), a.get("status_code"), err)))
print(" | ".join(out[-n:]))

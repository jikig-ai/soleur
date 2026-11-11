# Egress injector spike (#12517): summarise iron-proxy's JSON audit lines from stdin, one line per request, with
# no header or body values: method, host, path, action, status, and the first 120 characters of any error.
# Usage: ... | python3 -I lib/iron-audit.py [last N, default 6]
import json
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 6
out = []
skipped = 0
for line in sys.stdin:
    try:
        j = json.loads(line)
    except ValueError:
        # iron-proxy's log stream mixes plain-text lines with the JSON audit lines, and a `tail -c` window cuts its first
        # line mid-record; count them and say so on stderr. Both arms.sh callers discard stderr (2>/dev/null), so the
        # count is for a person running this by hand; the scored output on stdout is unchanged.
        skipped += 1
        j = {}
    a = (j.get("audit") if isinstance(j, dict) else None) or {}
    if a:
        err = str(j.get("error", ""))[:120]
        out.append(" ".join(str(x) for x in (a.get("method"), a.get("host"), a.get("path"), a.get("action"), a.get("status_code"), err)))
print(" | ".join(out[-n:]))
if skipped:
    print(f"iron-audit: {skipped} non-JSON line(s) skipped", file=sys.stderr)

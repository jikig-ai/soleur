"""Dormant fixed-host helper. Never run under source/offline-test authorization."""
import json
from pathlib import Path
import socket
import sys

HOST = 'auth.docker.io'


def _encoded(value):
    return json.dumps(value, ensure_ascii=True, separators=(',', ':'), sort_keys=True).encode('ascii')


def probe(host, resolve):
    """One call through an explicit resolver seam; answers stay only in memory."""
    if type(host) is not str or host != HOST:
        return _encoded({'version': 1, 'outcome': 'local_refusal'}), 3
    failed = False
    try:
        rows = resolve(HOST, 443, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
    except Exception:
        failed = True
    if failed:
        return _encoded({'version': 1, 'outcome': 'resolution_refusal'}), 4
    try:
        if type(rows) is not list or not 0 < len(rows) <= 16:
            raise ValueError()
        result = []
        for row in rows:
            if type(row) is not tuple or len(row) != 5:
                raise ValueError()
            family, kind, protocol, _canonical, address = row
            if kind != socket.SOCK_STREAM or protocol != socket.IPPROTO_TCP or type(address) is not tuple:
                raise ValueError()
            if family == socket.AF_INET and len(address) == 2:
                result.append([int(family), address[0], address[1], 0, 0])
            elif family == socket.AF_INET6 and len(address) == 4:
                result.append([int(family), *address])
            else:
                raise ValueError()
        raw = _encoded({'version': 1, 'outcome': 'answers', 'rows': result})
        if len(raw) > 4096:
            raise ValueError()
        return raw, 0
    except Exception:
        return _encoded({'version': 1, 'outcome': 'answer_refusal'}), 5


def main():
    # Local source path is fixed, not a caller-controlled import path or cwd.
    sys.path.insert(0, str(Path(__file__).absolute().parent))
    from resolver_supervisor import arm_parent_death
    try:
        if len(sys.argv) != 3 or sys.argv[1] != HOST:
            return 3
        arm_parent_death(int(sys.argv[2]))
        raw, code = probe(HOST, socket.getaddrinfo)
        sys.stdout.buffer.write(raw)
        return code
    except Exception:
        return 3


if __name__ == '__main__':
    sys.exit(main())

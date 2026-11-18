"""Fresh-interpreter, secret-free resolver helper; not an acquisition entry point."""
import json
import os
from pathlib import Path
import socket
import sys

HOSTS = ('auth.docker.io', 'registry-1.docker.io', 'production.cloudfront.docker.com')


def main():
    try:
        if (len(sys.argv) != 3 or sys.argv[1] not in HOSTS or
                not sys.argv[2].isascii() or not sys.argv[2].isdecimal() or
                len(sys.argv[2]) > 10 or not 1 < int(sys.argv[2]) <= 2147483647):
            return 1
        # Fixed sibling import works with -I -S; no caller import path is used.
        sys.path.insert(0, str(Path(__file__).absolute().parent))
        from resolver_supervisor import arm_parent_death
        parent = int(sys.argv[2])
        arm_parent_death(parent)
        # Share the coordinator's timeout group/session; parent-death handling
        # also covers an individual coordinator loss before outer cancellation.
        if os.getpgid(parent) != os.getpgrp() or os.getsid(parent) != os.getsid(0):
            return 1
        rows = socket.getaddrinfo(sys.argv[1], 443, type=socket.SOCK_STREAM,
                                  proto=socket.IPPROTO_TCP)
        if not rows or len(rows) > 16:
            return 1
        result = []
        for family, kind, protocol, _, address in rows:
            if kind != socket.SOCK_STREAM or protocol != socket.IPPROTO_TCP:
                return 1
            if family == socket.AF_INET and len(address) == 2:
                result.append([int(family), address[0], address[1], 0, 0])
            elif family == socket.AF_INET6 and len(address) == 4:
                result.append([int(family), address[0], address[1], address[2], address[3]])
            else:
                return 1
        raw = json.dumps(result, ensure_ascii=True, separators=(',', ':')).encode('ascii')
        if len(raw) > 4096:
            return 1
        sys.stdout.buffer.write(raw)
        return 0
    except Exception:
        return 1


if __name__ == '__main__':
    sys.exit(main())

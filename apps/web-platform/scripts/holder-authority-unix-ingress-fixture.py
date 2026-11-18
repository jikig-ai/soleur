"""Offline Linux ingress experiment; this cannot authorize collection or deletion.

The caller supplies an already-open directory descriptor and expected peer UID.
They are untrusted configuration for this experiment, not identity provenance.
Mode 0700 limits traversal to its owner; this experiment cannot demonstrate
cross-UID access under that mode. Same-UID processes, privileged/root actors,
untrusted ancestors, directory replacement, host loss, and provider IAM are not
isolated or qualified. The socket path is deliberately never unlinked; a stale
entry prevents restart. A security reviewer reproduced a same-UID process
replacing the bound pathname before the post-bind stat: that stat can inspect
the substitute while the listening descriptor still references the original.
This fixture cannot establish pathname identity or protect clients against that
substitution. Never use it in production or as an authority or vault fence.
"""
import os
import socket
import stat
import struct
import sys
import time

NAME = 'authority.sock'
HEALTH = b'{"state":"health_only","capture_authorized":false,"cleanup_authorized":false,"deletion_verified":false}'


def _remaining(deadline):
    left = deadline - time.monotonic()
    if left <= 0:
        raise TimeoutError('deadline')
    return left


def _recv_exact(client, length, deadline):
    parts = bytearray()
    while len(parts) < length:
        client.settimeout(_remaining(deadline))
        part = client.recv(length - len(parts))
        if not part:
            raise ValueError('truncated')
        parts.extend(part)
    return bytes(parts)


def serve_once(directory_fd, allowed_uid, seconds):
    if (not isinstance(directory_fd, int) or not isinstance(allowed_uid, int) or
            not 0 <= allowed_uid <= 0xffffffff or not 0 < seconds <= 5):
        raise ValueError('configuration')
    info = os.fstat(directory_fd)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('directory')
    try:
        os.stat(NAME, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        raise ValueError('existing path')
    deadline = time.monotonic() + seconds
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM | socket.SOCK_CLOEXEC)
    try:
        old_mask = os.umask(0o077)
        try:
            server.bind(f'/proc/self/fd/{directory_fd}/{NAME}')
        finally:
            os.umask(old_mask)
        created = os.stat(NAME, dir_fd=directory_fd, follow_symlinks=False)
        if not stat.S_ISSOCK(created.st_mode) or created.st_uid != os.geteuid() or stat.S_IMODE(created.st_mode) != 0o700:
            raise ValueError('socket')
        server.listen(1)
        server.settimeout(_remaining(deadline))
        client, _ = server.accept()
        with client:
            # The kernel's peer credentials are checked before any read.
            _, uid, _ = struct.unpack('iII', client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('iII')))
            if uid != allowed_uid:
                return
            try:
                size = struct.unpack('!I', _recv_exact(client, 4, deadline))[0]
                if size != 6:
                    return
                if _recv_exact(client, size, deadline) != b'health':
                    return
                client.settimeout(_remaining(deadline))
                # A half-close is required to reject trailing or second frames.
                if client.recv(1) != b'':
                    return
                client.settimeout(_remaining(deadline))
                client.sendall(HEALTH)
            except (OSError, TimeoutError, ValueError):
                return
    finally:
        server.close()


if __name__ == '__main__':
    try:
        if len(sys.argv) != 4:
            raise ValueError('configuration')
        serve_once(int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]))
    except (OSError, ValueError, OverflowError):
        sys.exit(1)

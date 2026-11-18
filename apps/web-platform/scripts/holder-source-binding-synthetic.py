"""Offline experiment only; this does not authorize or sandbox a collector.

This helper executes caller-supplied code. Use only reviewed synthetic fixtures
in disposable tests. It does not bind a launcher, runtime, dependency closure,
host, approved manifest, credentials, network or receipt-retention service.
"""
import hashlib
import os
import re
import stat
import subprocess

MAX_BYTES = 1024 * 1024


def run_synthetic(path, expected_digest, node_path):
    if (not isinstance(expected_digest, str) or not re.fullmatch(r'[a-f0-9]{64}', expected_digest)
            or not isinstance(node_path, str) or not os.path.isabs(node_path)):
        return 'refused'
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_BYTES:
                return 'refused'
            chunks = []
            remaining = MAX_BYTES + 1
            while remaining:
                chunk = os.read(fd, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            source = b''.join(chunks)
            if len(source) != info.st_size or hashlib.sha256(source).hexdigest() != expected_digest:
                return 'refused'
        finally:
            os.close(fd)
        completed = subprocess.run([node_path, '--input-type=module'], input=source,
                                   env={}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=5, check=False)
        return 'synthetic_pass' if completed.returncode == 0 else 'refused'
    except (OSError, TypeError, ValueError, subprocess.SubprocessError):
        return 'refused'

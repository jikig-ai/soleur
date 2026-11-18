"""Synthetic local socket tests; no live authority or production data."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).with_name('holder-authority-unix-ingress-fixture.py')
ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent'}


class IngressTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='synthetic-ingress-')
        self.path = Path(self.tmp.name)
        self.dirfd = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.child = None

    def tearDown(self):
        if self.child and self.child.poll() is None:
            self.child.kill()
            self.child.wait(timeout=5)
        os.close(self.dirfd)
        self.tmp.cleanup()

    def start(self, uid=None, timeout='3'):
        self.child = subprocess.Popen([sys.executable, str(SCRIPT), str(self.dirfd),
            str(os.geteuid() if uid is None else uid), timeout], pass_fds=(self.dirfd,),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=ENV)

    def reset_disposable_directory(self):
        self.assertIsNotNone(self.child)
        self.assertIsNotNone(self.child.poll())
        os.close(self.dirfd)
        self.tmp.cleanup()
        self.tmp = tempfile.TemporaryDirectory(prefix='synthetic-ingress-')
        self.path = Path(self.tmp.name)
        self.dirfd = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)

    def connect(self):
        until = time.monotonic() + 3
        while time.monotonic() < until:
            if self.child.poll() is not None:
                self.fail('fixture exited before socket was ready')
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(2)
            try:
                s.connect(str(self.path / 'authority.sock'))
                return s
            except (FileNotFoundError, ConnectionRefusedError):
                s.close()
                time.sleep(.01)
        self.fail('fixture did not become ready')

    def reply(self, data, fragments=False):
        with self.connect() as client:
            try:
                if fragments:
                    for byte in data:
                        client.sendall(bytes([byte]))
                else:
                    client.sendall(data)
                client.shutdown(socket.SHUT_WR)
                parts = []
                while chunk := client.recv(4096):
                    parts.append(chunk)
                return b''.join(parts)
            except (BrokenPipeError, ConnectionResetError):
                return b''

    def test_health_is_fixed_and_non_authorizing_even_when_fragmented(self):
        self.start()
        payload = b'health'
        data = self.reply(struct.pack('!I', len(payload)) + payload, fragments=True)
        self.assertEqual(json.loads(data), {'state':'health_only', 'capture_authorized':False,
            'cleanup_authorized':False, 'deletion_verified':False})
        self.assertEqual(self.child.wait(timeout=5), 0)
        self.assertTrue((self.path / 'authority.sock').is_socket())
        self.start()
        self.assertNotEqual(self.child.wait(timeout=5), 0)
        self.assertTrue((self.path / 'authority.sock').is_socket())

    def test_wrong_kernel_uid_is_refused(self):
        self.start(uid=os.geteuid()+1)
        self.assertEqual(self.reply(struct.pack('!I', 6) + b'health'), b'')
        self.assertEqual(self.child.wait(timeout=5), 0)

    def test_wrong_uid_is_rejected_without_sending_or_closing_input(self):
        self.start(uid=os.geteuid()+1, timeout='5')
        with self.connect() as client:
            self.assertEqual(self.child.wait(timeout=3), 0)
            self.assertEqual(client.recv(1), b'')

    def test_replaced_entry_is_not_removed_during_cleanup(self):
        self.start()
        with self.connect() as client:
            entry = self.path / 'authority.sock'
            entry.rename(self.path / 'original.sock')
            entry.write_text('replacement', encoding='utf8')
            client.sendall(struct.pack('!I', 6) + b'health')
            client.shutdown(socket.SHUT_WR)
            self.assertTrue(client.recv(4096))
        self.assertEqual(self.child.wait(timeout=5), 0)
        self.assertEqual(entry.read_text(), 'replacement')

    def test_malformed_oversize_truncated_and_trailing_frames_are_refused(self):
        for frame in (struct.pack('!I', 20000), struct.pack('!I', 6)+b'hea',
                      struct.pack('!I', 6)+b'healthx', struct.pack('!I', 4)+b'evil'):
            with self.subTest(frame=frame):
                self.start()
                self.assertEqual(self.reply(frame), b'')
                self.assertEqual(self.child.wait(timeout=5), 0)
                self.reset_disposable_directory()

    def test_stalled_client_cannot_hold_server_indefinitely(self):
        self.start(timeout='0.2')
        with self.connect() as client:
            client.sendall(b'\x00')
            self.assertEqual(self.child.wait(timeout=3), 0)
        self.assertTrue((self.path / 'authority.sock').is_socket())

    def test_existing_path_is_never_removed(self):
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                entry = self.path / 'authority.sock'
                if symlink:
                    entry.symlink_to('unrelated')
                else:
                    entry.write_text('keep', encoding='utf8')
                self.start()
                self.assertNotEqual(self.child.wait(timeout=5), 0)
                self.assertTrue(entry.is_symlink() if symlink else entry.read_text() == 'keep')
                entry.unlink()

    def test_nonprivate_directory_is_refused(self):
        os.chmod(self.path, 0o755)
        self.start()
        self.assertNotEqual(self.child.wait(timeout=5), 0)
        self.assertFalse((self.path / 'authority.sock').exists())


if __name__ == '__main__':
    unittest.main()

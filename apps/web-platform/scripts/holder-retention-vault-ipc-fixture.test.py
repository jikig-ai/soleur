"""Synthetic child-process interface tests; no credentials or provider calls."""
import importlib.util
import fcntl
import json
import os
import pathlib
import select
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location('vault_fixture', ROOT / 'holder-retention-vault-posix.py')
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)
SERVICE = ROOT / 'holder-retention-vault-ipc-fixture.py'
OP = 'synthetic-operation'
GEN = 'synthetic-generation'


class VaultIpcTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vault-ipc-fixture-')
        self.addCleanup(self.tmp.cleanup)
        self.path = pathlib.Path(self.tmp.name) / 'vault'
        self.path.mkdir(mode=0o700)
        vault.SyntheticPosixVault.initialize(self.path, OP, GEN)
        self.children = []
        self.addCleanup(self.stop_children)

    def stop_children(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=5)
            for pipe in (child.stdin, child.stdout, child.stderr):
                pipe.close()

    def start(self):
        child = subprocess.Popen([sys.executable, str(SERVICE), str(self.path)], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(child)
        return child

    def send(self, child, command, **fields):
        request = {'operation_id': OP, 'generation': GEN, 'action': command, **fields}
        child.stdin.write((json.dumps(request, separators=(',', ':')) + '\n').encode())
        child.stdin.flush()

    def response(self, child):
        readable, _, _ = select.select([child.stdout], [], [], 5)
        self.assertTrue(readable, 'fixture child failed to respond')
        raw = child.stdout.readline(512)
        self.assertNotIn(b'private', raw)
        response = json.loads(raw)
        self.assertIs(response['authorizes_cleanup'], False)
        self.assertIs(response['authorizes_capture'], False)
        self.assertIs(response['deletion_verified'], False)
        return response

    def test_wrong_generation_extra_body_and_unknown_actions_are_refused(self):
        child = self.start()
        for command, changes in [('write_fixture', {'generation': 'other'}),
                                 ('write_fixture', {'operation_id': 'other'}),
                                 ('write_fixture', {'body': 'private'}), ('delete', {})]:
            self.send(child, command, **changes)
            self.assertEqual(self.response(child), {'result': 'refused', 'authorizes_cleanup': False,
                                                   'authorizes_capture': False, 'deletion_verified': False})
        self.send(child, 'status')
        self.assertEqual(self.response(child), {'result': 'open', 'authorizes_cleanup': False,
                                               'authorizes_capture': False, 'deletion_verified': False})
        self.assertFalse((self.path / 'fixture').exists())

    def test_two_processes_serialize_fixed_entry_creation(self):
        one, two = self.start(), self.start()
        self.send(one, 'write_fixture')
        self.send(two, 'write_fixture')
        results = sorted((self.response(one)['result'], self.response(two)['result']))
        self.assertEqual(results, ['applied', 'refused'])
        self.assertEqual((self.path / 'fixture').read_bytes(), b'synthetic-vault-fixture\n')
        self.send(one, 'seal')
        self.assertEqual(self.response(one)['result'], 'applied')
        self.send(two, 'write_fixture')
        self.assertEqual(self.response(two)['result'], 'refused')

    def test_process_request_waits_for_owned_operation_lock(self):
        child = self.start()
        self.send(child, 'status')
        self.assertEqual(self.response(child)['result'], 'open')
        lock = os.open(self.path / 'lock', os.O_RDWR)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.send(child, 'write_fixture')
            info = os.fstat(lock)
            device_inode = f'{os.major(info.st_dev):02x}:{os.minor(info.st_dev):02x}:{info.st_ino}'
            deadline = time.monotonic() + 3
            waiting = False
            while time.monotonic() < deadline:
                readable, _, _ = select.select([child.stdout], [], [], 0.01)
                self.assertEqual(readable, [], 'request bypassed the operation lock')
                locks = pathlib.Path('/proc/locks').read_text().splitlines()
                waiting = any(len(fields := line.split()) >= 7 and fields[1:5] == ['->', 'FLOCK', 'ADVISORY', 'WRITE']
                              and fields[5] == str(child.pid) and fields[6] == device_inode for line in locks)
                if waiting:
                    break
            self.assertTrue(waiting, 'kernel did not report the child waiting for the fixture lock')
            self.assertFalse((self.path / 'fixture').exists(), 'fixture was created while the lock was held')
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            os.close(lock)
        self.assertEqual(self.response(child)['result'], 'applied')
        self.assertEqual((self.path / 'fixture').read_bytes(), b'synthetic-vault-fixture\n')

    def test_tombstone_survives_child_kill_and_restart(self):
        child = self.start()
        for action in ['write_fixture', 'seal', 'tombstone']:
            self.send(child, action)
            self.assertEqual(self.response(child)['result'], 'applied')
        child.kill()
        child.wait(timeout=5)
        restarted = self.start()
        self.send(restarted, 'status')
        self.assertEqual(self.response(restarted), {'result': 'tombstoned', 'authorizes_cleanup': False,
                                                   'authorizes_capture': False, 'deletion_verified': False})
        self.send(restarted, 'write_fixture')
        self.assertEqual(self.response(restarted)['result'], 'refused')

    def test_overlong_or_duplicate_json_never_echoes_and_cannot_write(self):
        child = self.start()
        child.stdin.write(b'{"action":"private","action":"private"}\n')
        child.stdin.flush()
        self.assertEqual(self.response(child)['result'], 'refused')
        child.stdin.write(b'x' * 513 + b'\n')
        child.stdin.flush()
        self.assertEqual(self.response(child)['result'], 'refused')
        self.assertEqual(child.wait(timeout=5), 0)
        self.assertFalse((self.path / 'fixture').exists())
        self.assertEqual(child.stderr.read(), b'')


if __name__ == '__main__':
    unittest.main()

"""Kill only child fixture processes in fresh temporary directories.

No receipt, provider access, independent scheduler, delete authority, or
host-loss claim is involved. The vault writes only its fixed synthetic bytes.
"""
import importlib.util
import multiprocessing
import os
import pathlib
import signal
import tempfile
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name('holder-retention-vault-posix.py')
spec = importlib.util.spec_from_file_location('vault_posix_interruption', MODULE_PATH)
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)


def fixture_writer(root, checkpoint, reached, release):
    with vault.SyntheticPosixVault(root, 'synthetic-operation', 'synthetic-generation') as v:
        if checkpoint == 'before_state_save':
            original = v._save
            def pause_save(state):
                reached.set()
                release.wait(10)
                original(state)
            v._save = pause_save
        elif checkpoint == 'before_state_rename':
            original = os.rename
            def pause_rename(*args, **kwargs):
                reached.set()
                release.wait(10)
                return original(*args, **kwargs)
            os.rename = pause_rename
        v.write_fixture()
        if checkpoint == 'after_commit':
            reached.set()
            release.wait(10)


class VaultInterruptionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-vault-interrupt-')
        self.addCleanup(self.temp.cleanup)
        base = pathlib.Path(self.temp.name)
        self.root = base / 'vault'
        self.root.mkdir(mode=0o700)
        self.sentinel = base / 'unrelated-sentinel'
        self.sentinel.write_bytes(b'synthetic-unrelated-sentinel\n')
        vault.SyntheticPosixVault.initialize(self.root, 'synthetic-operation', 'synthetic-generation')

    def interrupt(self, checkpoint):
        ctx = multiprocessing.get_context('fork')
        reached, release = ctx.Event(), ctx.Event()
        child = ctx.Process(target=fixture_writer, args=(self.root, checkpoint, reached, release))
        child.start()
        try:
            self.assertTrue(reached.wait(5), 'child did not reach checkpoint')
            self.assertTrue(child.is_alive(), 'child exited before interruption')
            child.kill()
            child.join(5)
            self.assertEqual(child.exitcode, -signal.SIGKILL)
        finally:
            if child.is_alive():
                child.kill()
                child.join(5)
        self.assertEqual(self.sentinel.read_bytes(), b'synthetic-unrelated-sentinel\n')
        self.assertEqual((self.root / 'fixture').read_bytes(), b'synthetic-vault-fixture\n')

    def open(self):
        return vault.SyntheticPosixVault(self.root, 'synthetic-operation', 'synthetic-generation')

    def test_kill_after_fixture_sync_before_state_refuses_reuse(self):
        self.interrupt('before_state_save')
        with self.open() as v:
            with self.assertRaises(vault.Refused):
                v.status()
            with self.assertRaises(vault.Refused):
                v.write_fixture()

    def test_kill_after_state_temp_sync_before_rename_refuses_reuse(self):
        self.interrupt('before_state_rename')
        self.assertTrue((self.root / 'state-next').is_file())
        with self.open() as v:
            with self.assertRaises(vault.Refused):
                v.status()
            with self.assertRaises(vault.Refused):
                v.seal()

    def test_kill_after_commit_allows_seal_without_rewrite(self):
        self.interrupt('after_commit')
        with self.open() as v:
            self.assertEqual(v.status(), 'open')
            with self.assertRaises(vault.Refused):
                v.write_fixture()
            v.seal()
            v.tombstone()
        with self.open() as v:
            self.assertEqual(v.status(), 'tombstoned')
            with self.assertRaises(vault.Refused):
                v.write_fixture()
        self.assertEqual(self.sentinel.read_bytes(), b'synthetic-unrelated-sentinel\n')


if __name__ == '__main__':
    unittest.main()

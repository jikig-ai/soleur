import importlib.util
import fcntl
import multiprocessing
import os
import pathlib
import tempfile
import threading
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name('holder-retention-vault-posix.py')
spec = importlib.util.spec_from_file_location('vault_posix', MODULE_PATH)
vault_posix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault_posix)


def race(root, action, gate, result):
    with vault_posix.SyntheticPosixVault(root, 'operation-a', 'generation-a') as vault:
        gate.wait(5)
        try:
            getattr(vault, action)()
            result.put((action, 'ok'))
        except vault_posix.Refused:
            result.put((action, 'refused'))


def check_lock_wait(root, started, completed):
    with vault_posix.SyntheticPosixVault(root, 'operation-a', 'generation-a') as vault:
        started.set()
        vault.write_fixture()
        completed.set()


class PosixVaultTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vault-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = self.temp.name
        vault_posix.SyntheticPosixVault.initialize(self.root, 'operation-a', 'generation-a')

    def open(self, op='operation-a', generation='generation-a'):
        return vault_posix.SyntheticPosixVault(self.root, op, generation)

    def test_reopen_and_tombstone_are_durable(self):
        with self.open() as v:
            v.write_fixture()
            v.seal()
            v.tombstone()
        with self.open() as v:
            self.assertEqual(v.status(), 'tombstoned')
            with self.assertRaises(vault_posix.Refused):
                v.write_fixture()
            with self.assertRaises(vault_posix.Refused):
                v.seal()
        self.assertEqual(pathlib.Path(self.root, 'fixture').read_bytes(), b'synthetic-vault-fixture\n')

    def test_wrong_identity_and_early_tombstone_refused(self):
        with self.open('other', 'generation-a') as v:
            with self.assertRaises(vault_posix.Refused):
                v.write_fixture()
        with self.open('operation-a', 'other') as v:
            with self.assertRaises(vault_posix.Refused):
                v.seal()
        with self.open() as v:
            with self.assertRaises(vault_posix.Refused):
                v.tombstone()

    def test_preexisting_entry_and_symlink_are_not_overwritten(self):
        target = pathlib.Path(self.root, 'outside-sentinel')
        target.write_text('sentinel')
        pathlib.Path(self.root, 'fixture').symlink_to(target)
        with self.open() as v:
            with self.assertRaises(vault_posix.Refused):
                v.write_fixture()
        self.assertEqual(target.read_text(), 'sentinel')

    def test_hardlinked_state_and_lock_are_refused(self):
        for name in ['state', 'lock']:
            link = pathlib.Path(self.root, name + '-link')
            os.link(pathlib.Path(self.root, name), link)
            with self.assertRaises(vault_posix.Refused):
                with self.open() as v:
                    v.status()
            link.unlink()

    def test_replaced_lock_or_unknown_state_fails_closed(self):
        with self.open() as v:
            os.rename(pathlib.Path(self.root, 'lock'), pathlib.Path(self.root, 'old-lock'))
            pathlib.Path(self.root, 'lock').touch(mode=0o600)
            with self.assertRaises(vault_posix.Refused):
                v.write_fixture()

    def test_competing_processes_serialize_write_and_seal(self):
        ctx = multiprocessing.get_context('fork')
        gate = ctx.Event()
        results = ctx.Queue()
        workers = [ctx.Process(target=race, args=(self.root, action, gate, results))
                   for action in ('write_fixture', 'seal')]
        for worker in workers:
            worker.start()
        gate.set()
        for worker in workers:
            worker.join(5)
            self.assertEqual(worker.exitcode, 0)
        outcomes = dict(results.get(timeout=1) for _ in workers)
        self.assertEqual(outcomes['seal'], 'ok')
        self.assertIn(outcomes['write_fixture'], ('ok', 'refused'))
        with self.open() as v:
            self.assertEqual(v.status(), 'sealed')
            with self.assertRaises(vault_posix.Refused):
                v.write_fixture()

    def test_process_waits_on_exclusive_operation_lock(self):
        ctx = multiprocessing.get_context('fork')
        started, completed = ctx.Event(), ctx.Event()
        lock = os.open(pathlib.Path(self.root, 'lock'), os.O_RDWR)
        worker = ctx.Process(target=check_lock_wait, args=(self.root, started, completed))
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            worker.start()
            self.assertTrue(started.wait(2))
            self.assertFalse(completed.wait(0.1))
            fcntl.flock(lock, fcntl.LOCK_UN)
            self.assertTrue(completed.wait(2))
            worker.join(2)
            self.assertEqual(worker.exitcode, 0)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            os.close(lock)
            if worker.is_alive():
                worker.terminate()
                worker.join(2)

    def test_interrupted_updates_and_changed_fixture_fail_closed(self):
        pathlib.Path(self.root, 'state-next').write_bytes(b'incomplete')
        with self.open() as v:
            with self.assertRaises(vault_posix.Refused):
                v.status()
        pathlib.Path(self.root, 'state-next').unlink()
        with self.open() as v:
            v.write_fixture()
        pathlib.Path(self.root, 'fixture').write_bytes(b'replaced')
        with self.open() as v:
            with self.assertRaises(vault_posix.Refused):
                v.seal()

    def test_threads_sharing_an_instance_serialize(self):
        with self.open() as v:
            entered = threading.Event()
            release = threading.Event()
            sealed = threading.Event()
            original = v._read
            calls = 0
            def pause_first_read():
                nonlocal calls
                calls += 1
                if calls == 1:
                    entered.set()
                    self.assertTrue(release.wait(2))
                return original()
            v._read = pause_first_read
            writer = threading.Thread(target=v.write_fixture)
            sealer = threading.Thread(target=lambda: (v.seal(), sealed.set()))
            writer.start()
            self.assertTrue(entered.wait(2))
            sealer.start()
            try:
                self.assertFalse(sealed.wait(0.1))
            finally:
                release.set()
                writer.join(2)
                sealer.join(2)
            self.assertTrue(sealed.is_set())
            self.assertEqual(v.status(), 'sealed')


if __name__ == '__main__':
    unittest.main()

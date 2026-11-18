import importlib.util
import pathlib
import threading
import unittest

path = pathlib.Path(__file__).with_name('holder-retention-vault-synthetic.py')
spec = importlib.util.spec_from_file_location('synthetic_vault', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SyntheticVaultTest(unittest.TestCase):
    def setUp(self):
        self.now = 10
        self.current = True
        self.vault = module.SyntheticVault('op', 'gen', 20,
                                            lambda: self.now,
                                            lambda operation, generation: self.current,
                                            lambda: True)

    def test_exact_deadline_and_revocation_refuse_writes(self):
        self.assertTrue(self.vault.write('op', 'gen'))
        self.now = 20
        self.assertFalse(self.vault.write('op', 'gen'))
        self.vault = module.SyntheticVault('op', 'gen', 30, lambda: self.now,
                                            lambda operation, generation: self.current,
                                            lambda: True)
        self.current = False
        self.assertFalse(self.vault.write('op', 'gen'))
        self.assertEqual(self.vault.write_count, 0)

    def test_wrong_operation_generation_or_failed_authority_refuse(self):
        self.assertFalse(self.vault.write('other', 'gen'))
        self.assertFalse(self.vault.write('op', 'other'))
        self.vault.authority = lambda *_: (_ for _ in ()).throw(RuntimeError('private'))
        self.assertFalse(self.vault.write('op', 'gen'))
        self.assertFalse(self.vault.seal('op', 'gen'))

    def test_seal_serializes_with_write_and_is_terminal(self):
        entered = threading.Event()
        release = threading.Event()
        results = {}
        def authority(*_):
            entered.set()
            self.assertTrue(release.wait(2))
            return True
        self.vault.authority = authority
        writer = threading.Thread(target=lambda: results.update(write=self.vault.write('op', 'gen')))
        sealer = threading.Thread(target=lambda: results.update(seal=self.vault.seal('op', 'gen')))
        writer.start()
        self.assertTrue(entered.wait(2))
        sealer.start()
        release.set()
        writer.join(2)
        sealer.join(2)
        self.assertFalse(writer.is_alive())
        self.assertFalse(sealer.is_alive())
        self.assertEqual(results, {'write': True, 'seal': True})
        self.assertFalse(self.vault.write('op', 'gen'))
        self.assertEqual(self.vault.write_count, 1)

    def test_clock_is_sampled_after_waiting_for_mutation_lock(self):
        self.vault._lock.acquire()
        results = []
        writer = threading.Thread(target=lambda: results.append(self.vault.write('op', 'gen')))
        writer.start()
        self.now = 20
        self.vault._lock.release()
        writer.join(2)
        self.assertEqual(results, [False])
        self.assertEqual(self.vault.write_count, 0)

    def test_noninteger_invalid_or_unavailable_time_fails_closed(self):
        for value in [True, -1, None, 1.5]:
            self.vault.clock = lambda: value
            self.assertFalse(self.vault.write('op', 'gen'))
        self.vault.clock = lambda: (_ for _ in ()).throw(RuntimeError('private'))
        self.assertFalse(self.vault.write('op', 'gen'))

    def test_deadline_crossed_during_authority_check_refuses_write(self):
        def slow_authority(*_):
            self.now = 20
            return True
        self.vault.authority = slow_authority
        self.assertFalse(self.vault.write('op', 'gen'))
        self.assertEqual(self.vault.write_count, 0)

    def test_backward_clock_refuses_mutations(self):
        self.assertTrue(self.vault.write('op', 'gen'))
        self.now = 9
        self.assertFalse(self.vault.write('op', 'gen'))
        self.assertFalse(self.vault.seal('op', 'gen'))

    def test_seal_refuses_without_independent_capture_stop_claim(self):
        self.vault.capture_stopped = lambda: False
        self.assertFalse(self.vault.seal('op', 'gen'))
        self.assertTrue(self.vault.write('op', 'gen'))
        self.vault.capture_stopped = lambda: True
        self.assertTrue(self.vault.seal('op', 'gen'))


if __name__ == '__main__':
    unittest.main()

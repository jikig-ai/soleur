import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location('synthetic_ledger', pathlib.Path(__file__).with_name('holder-retention-ledger-synthetic.py'))
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-ledger-')
        self.addCleanup(self.temp.cleanup)
        self.path = pathlib.Path(self.temp.name) / 'ledger.sqlite'
        ledger.initialize(self.path)

    def test_persists_across_connections_and_rejects_stale_generation(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-2', 'armed', 'capturing', 130))
        self.assertEqual(ledger.read(self.path, 'op-1'), ('gen-1', 100, 200, 'armed'))

    def test_atomic_compare_and_swap_allows_only_one_concurrent_transition(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        barrier = threading.Barrier(2)
        results = []
        def compete():
            barrier.wait()
            results.append(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        threads = [threading.Thread(target=compete) for _ in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(sorted(results), [False, True])

    def test_crashed_process_cannot_leave_an_uncommitted_transition(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        script = ("import os, sqlite3, sys; c=sqlite3.connect(sys.argv[1], isolation_level=None); "
                  "c.execute('BEGIN IMMEDIATE'); "
                  "c.execute(\"UPDATE operations SET state = 'armed' WHERE operation_id = 'op-1'\"); os._exit(0)")
        subprocess.run([sys.executable, '-B', '-c', script, str(self.path)], check=True, timeout=5)
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'unarmed')
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))

    def test_deadline_is_terminal_and_never_certifies_deletion(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 200))
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'expired')
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'expired', 'verified_deleted', 201))

    def test_refuses_invalid_inputs_and_unapproved_transitions(self):
        with self.assertRaises(ValueError): ledger.create(self.path, 'private/path', 'gen-1', 100, 200)
        with self.assertRaises(ValueError): ledger.create(self.path, 'op-1', 'gen-1', 200, 200)
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'capturing', 120))
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'unarmed')

    def test_arming_precedes_capture_and_capture_cannot_start_early(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 99))
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 100))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'capturing', 'sealed', 99))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', [], 'armed', 100))

    def test_transition_time_cannot_move_back_after_capture(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 150))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'capturing', 'sealed', 120))
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'capturing')

    def test_explicit_due_sweep_marks_only_expired_captures(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        ledger.create(self.path, 'op-2', 'gen-1', 100, 300)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 100))
        self.assertEqual(ledger.mark_due(self.path, 199), 0)
        self.assertEqual(ledger.mark_due(self.path, 200), 1)
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'late')
        self.assertEqual(ledger.read(self.path, 'op-2')[-1], 'unarmed')
        self.assertEqual(ledger.mark_due(self.path, 200), 0)

    def test_due_sweep_expires_an_armed_operation_and_refuses_stale_capture(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertEqual(ledger.mark_due(self.path, 200), 1)
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'expired')
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 150))

    def test_deadline_classifies_armed_and_captured_states_separately(self):
        ledger.create(self.path, 'op-1', 'gen-1', 100, 200)
        ledger.create(self.path, 'op-2', 'gen-1', 100, 200)
        ledger.create(self.path, 'op-3', 'gen-1', 100, 200)
        self.assertTrue(ledger.transition(self.path, 'op-1', 'gen-1', 'unarmed', 'armed', 90))
        self.assertTrue(ledger.transition(self.path, 'op-2', 'gen-1', 'unarmed', 'armed', 90))
        self.assertTrue(ledger.transition(self.path, 'op-2', 'gen-1', 'armed', 'capturing', 100))
        self.assertFalse(ledger.transition(self.path, 'op-1', 'gen-1', 'armed', 'capturing', 200))
        self.assertFalse(ledger.transition(self.path, 'op-2', 'gen-1', 'capturing', 'sealed', 200))
        self.assertEqual(ledger.mark_due(self.path, 200), 1)
        self.assertEqual(ledger.read(self.path, 'op-1')[-1], 'expired')
        self.assertEqual(ledger.read(self.path, 'op-2')[-1], 'late')
        self.assertEqual(ledger.read(self.path, 'op-3')[-1], 'expired')


if __name__ == '__main__':
    unittest.main()

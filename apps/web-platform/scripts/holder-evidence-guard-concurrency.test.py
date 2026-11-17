"""Synthetic SQLite lock-order experiment; this is not a live authority."""
import json
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).with_name('holder-evidence-guard-fixture.py')
SYNTHETIC_ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent'}
HOLDER = r'''
import sqlite3, sys
db = sqlite3.connect(sys.argv[1], timeout=5)
db.execute('BEGIN IMMEDIATE')
if sys.argv[2] == 'write':
    db.execute("INSERT INTO writes SELECT 1 WHERE EXISTS (SELECT 1 FROM guard WHERE id=1 AND state='active' AND epoch=1)")
else:
    db.execute("UPDATE guard SET state='quarantined', epoch=epoch+1 WHERE id=1 AND state='active'")
print('locked', flush=True)
if sys.stdin.readline().strip() == 'commit':
    db.commit()
else:
    db.rollback()
db.close()
'''
WAITER = r'''
import runpy, sqlite3, sys
script, path, operation = sys.argv[1:]
probe = sqlite3.connect(path, timeout=0)
try:
    probe.execute('BEGIN IMMEDIATE')
except sqlite3.OperationalError as error:
    if error.sqlite_errorcode != sqlite3.SQLITE_BUSY:
        raise
else:
    raise RuntimeError('expected synthetic lock contention')
finally:
    probe.close()
sys.argv = [script, path, operation]
print('busy', flush=True)
runpy.run_path(script, run_name='__main__')
'''


class SyntheticGuardContention(unittest.TestCase):
    def helper(self, path, operation):
        result = subprocess.run([sys.executable, str(HELPER), str(path), operation],
                                capture_output=True, text=True, timeout=8, check=True, env=SYNTHETIC_ENV)
        return json.loads(result.stdout)

    def test_committed_lock_order_and_crash_rollback(self):
        for held, release, competitor, expected_state, expected_writes in (
            ('write', 'commit', 'quarantine', 'quarantined', 1),
            ('quarantine', 'commit', 'write', 'rejected', 0),
            ('write', 'crash', 'quarantine', 'quarantined', 0),
        ):
            with self.subTest(held=held, release=release), tempfile.TemporaryDirectory(prefix='synthetic-collector-guard-') as tmp:
                path = Path(tmp) / 'fixture.sqlite'
                self.assertEqual(self.helper(path, 'initialize')['state'], 'active')
                owner = subprocess.Popen([sys.executable, '-c', HOLDER, str(path), held],
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                         env=SYNTHETIC_ENV)
                waiter = None
                try:
                    with selectors.DefaultSelector() as selector:
                        selector.register(owner.stdout, selectors.EVENT_READ)
                        self.assertTrue(selector.select(5), 'holder did not signal its lock')
                    self.assertEqual(owner.stdout.readline().strip(), 'locked')
                    waiter = subprocess.Popen([sys.executable, '-c', WAITER, str(HELPER), str(path), competitor],
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=SYNTHETIC_ENV)
                    with selectors.DefaultSelector() as selector:
                        selector.register(waiter.stdout, selectors.EVENT_READ)
                        self.assertTrue(selector.select(5), 'competitor did not report lock contention')
                    self.assertEqual(waiter.stdout.readline().strip(), 'busy')
                    with self.assertRaises(subprocess.TimeoutExpired):
                        waiter.wait(timeout=0.2)
                    if release == 'crash':
                        owner.kill()
                        owner.communicate(timeout=5)
                    else:
                        owner.communicate(input='commit\n', timeout=5)
                        self.assertEqual(owner.returncode, 0)
                    output, error = waiter.communicate(timeout=8)
                    self.assertEqual(waiter.returncode, 0, error)
                    result = json.loads(output)
                    self.assertEqual(result['state'], expected_state)
                    self.assertEqual(result['backend_stop'], 'unknown')
                    self.assertFalse(result['writer_clearance'])
                    self.assertEqual(self.helper(path, 'inspect')['writes'], expected_writes)
                finally:
                    for child in (owner, waiter):
                        if child:
                            if child.poll() is None:
                                child.kill()
                            child.wait(timeout=5)
                            for stream in (child.stdin, child.stdout, child.stderr):
                                if stream and not stream.closed:
                                    stream.close()


if __name__ == '__main__':
    unittest.main()

"""Run synthetic-only claim experiments in a disposable PostgreSQL fixture."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import unittest
from holder_evidence_test_postgres import temporary_postgres

NAME = f'holder_evidence_test_{os.getpid()}'
assert re.fullmatch(r'holder_evidence_test_[0-9]+', NAME)
ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent', 'PGCONNECT_TIMEOUT': '5'}


def control(query, db):
    result = subprocess.run(db.psql_command('postgres', 'postgres') +
                            ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'],
                            input=query, text=True, capture_output=True, env=ENV, timeout=20)
    if result.returncode:
        raise RuntimeError('synthetic database control failed: ' + result.stderr.replace(db.password, '[redacted]')[-500:])
    return result.stdout.strip()


class ClaimPrototypeTest(unittest.TestCase):
    def test_concurrent_claims(self):
        with temporary_postgres() as db:
            self.assertEqual(control(f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');", db), 'f')
            created = False
            try:
                control(f'CREATE DATABASE "{NAME}" TEMPLATE template0;', db)
                created = True
                node = shutil.which('node')
                self.assertIsNotNone(node)
                env = {**ENV, 'SYNTHETIC_DB': NAME, 'SYNTHETIC_CONTAINER_ID': db.container_id,
                       'SYNTHETIC_CONTAINER_IMAGE': db.image, 'SYNTHETIC_CONTAINER_MARKER': db.marker,
                       'SYNTHETIC_PASSWORD': db.password}
                result = subprocess.run([node, str(Path(__file__).with_name('codex-claim-prototype-local.test.mjs'))],
                                        env=env, text=True, capture_output=True, timeout=40)
                self.assertEqual(result.returncode, 0, result.stderr[-2000:])
                self.assertEqual(result.stdout.strip(), 'synthetic claim prototype passed')
            finally:
                if created:
                    control(f'DROP DATABASE "{NAME}" WITH (FORCE);', db)
                    self.assertEqual(control(f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');", db), 'f')


if __name__ == '__main__':
    unittest.main()

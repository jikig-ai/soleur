"""Exercise the dormant runner in one uniquely owned synthetic local DB."""
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
    command = db.psql_command('postgres', 'postgres') + ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']
    result = subprocess.run(command, input=query, text=True, capture_output=True, env=ENV, timeout=20)
    if result.returncode:
        raise RuntimeError('synthetic database control failed')
    return result.stdout.strip()


class RunnerTest(unittest.TestCase):
    def test_readonly_runner(self):
        with temporary_postgres() as db:
            self.assertEqual(control(f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');", db), 'f')
            created = False
            try:
                control(f'CREATE DATABASE "{NAME}" TEMPLATE template0;', db)
                created = True
                node = shutil.which('node')
                self.assertIsNotNone(node)
                script = Path(__file__).with_name('holder-evidence-db-runner-local.test.mjs')
                env = {**ENV, 'SYNTHETIC_DB': NAME, 'SYNTHETIC_CONTAINER_ID': db.container_id,
                       'SYNTHETIC_CONTAINER_IMAGE': db.image, 'SYNTHETIC_CONTAINER_MARKER': db.marker,
                       'SYNTHETIC_PASSWORD': db.password}
                # The integration fixture now includes a naturally completing
                # delayed query and several separate guard processes.
                result = subprocess.run([node, str(script)], env=env, text=True, capture_output=True, timeout=90)
                location = re.search(r'holder-evidence-db-runner-local\.test\.mjs:(\d+):\d+', result.stderr)
                line = location.group(1) if location else 'unknown'
                self.assertEqual(result.returncode, 0, f'synthetic runner returned failure at fixture line {line}')
                self.assertEqual(result.stdout.strip(), 'synthetic read-only boundary passed')
            finally:
                if created:
                    # NAME is uniquely generated and the entire server is a
                    # verified disposable fixture. Failed interruption probes
                    # can leave its synthetic backend alive during teardown.
                    control(f'DROP DATABASE "{NAME}" WITH (FORCE);', db)
                    self.assertEqual(control(f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');", db), 'f')


if __name__ == '__main__':
    unittest.main()

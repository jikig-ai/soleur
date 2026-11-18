"""Run the preflight against synthetic files and a non-network psql shim."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('preflight-schema-vs-ledger.sh')
PSQL = '''#!/bin/sh
case "$*" in
  *"SELECT filename FROM public._schema_migrations"*)
    case "$SYNTHETIC_MODE" in
      ledger_failure) printf 'synthetic-private-error\\n' >&2; exit 1 ;;
      partial_failure) printf '001_fixture.sql\\n'; printf 'synthetic-private-error\\n' >&2; exit 1 ;;
      ledger_hang) sleep 5; printf '001_fixture.sql\\n'; exit 0 ;;
      empty) exit 0 ;;
      *) printf '001_fixture.sql\\n'; exit 0 ;;
    esac ;;
  *"SELECT to_regclass("*)
    case "$SYNTHETIC_MODE" in
      probe_failure) printf 'synthetic-private-error\\n' >&2; exit 1 ;;
      probe_partial_failure) printf 't\\n'; exit 1 ;;
      probe_invalid) printf 'unexpected\\n' ;;
      probe_hang) sleep 5; printf 't\\n' ;;
      missing) printf 'f\\n' ;;
      *) printf 't\\n' ;;
    esac ;;
  *) exit 2 ;;
esac
'''


class PreflightTest(unittest.TestCase):
    def run_preflight(self, mode, timeout='1', errexit=False):
        with tempfile.TemporaryDirectory(prefix='synthetic-preflight-') as tmp:
            root = Path(tmp)
            scripts = root / 'scripts'
            migrations = root / 'supabase' / 'migrations'
            bin_dir = root / 'bin'
            for directory in (scripts, migrations, bin_dir):
                directory.mkdir(parents=True)
            shutil.copyfile(SCRIPT, scripts / SCRIPT.name)
            sql = 'SELECT 1;\n' if mode == 'no_table' else 'CREATE TABLE public.synthetic_table (id integer);\n'
            (migrations / '001_fixture.sql').write_text(sql)
            psql = bin_dir / 'psql'
            psql.write_text(PSQL)
            psql.chmod(0o700)
            grep = bin_dir / 'grep'
            grep.write_text('''#!/bin/sh
if [ "$SYNTHETIC_MODE" = grep_failure ]; then printf 'synthetic-private-grep-error\\n' >&2; exit 2; fi
exec /usr/bin/grep "$@"
''')
            grep.chmod(0o700)
            env = {'PATH': f'{bin_dir}:/usr/bin:/bin', 'HOME': '/nonexistent',
                   'DATABASE_URL': 'synthetic-target', 'SYNTHETIC_MODE': mode,
                   'PREFLIGHT_SQL_TIMEOUT_SECONDS': timeout}
            shell_args = ['bash', '-e'] if errexit else ['bash']
            return subprocess.run([*shell_args, str(scripts / SCRIPT.name)], env=env,
                                  text=True, capture_output=True, timeout=10)

    def test_failed_ledger_read_never_passes(self):
        for mode in ('ledger_failure', 'partial_failure'):
            with self.subTest(mode=mode):
                result = self.run_preflight(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('consistency check passed', result.stdout)
                self.assertNotIn('synthetic-private-error', result.stdout + result.stderr)

    def test_probe_failure_and_missing_table_fail(self):
        for mode in ('probe_failure', 'probe_partial_failure', 'probe_invalid', 'missing'):
            with self.subTest(mode=mode):
                result = self.run_preflight(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('consistency check passed', result.stdout)
                if mode != 'missing':
                    self.assertIn('preflight is unverified', result.stdout)
                    self.assertNotIn('is missing', result.stdout)
                    self.assertNotIn('synthetic-private-error', result.stdout + result.stderr)

    def test_synthetic_present_table_and_empty_ledger(self):
        for mode in ('present', 'empty', 'no_table'):
            with self.subTest(mode=mode):
                result = self.run_preflight(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('consistency check passed', result.stdout)

    def test_grep_error_is_not_a_no_match(self):
        result = self.run_preflight('grep_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('consistency check passed', result.stdout)
        self.assertNotIn('synthetic-private-grep-error', result.stdout + result.stderr)

    def test_no_match_is_valid_with_inherited_errexit(self):
        result = self.run_preflight('no_table', errexit=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('consistency check passed', result.stdout)

    def test_hung_database_reads_fail_closed(self):
        for mode in ('ledger_hang', 'probe_hang'):
            with self.subTest(mode=mode):
                result = self.run_preflight(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('consistency check passed', result.stdout)

    def test_invalid_timeouts_fail_closed(self):
        for timeout in ('0', '31', '1s', '-1', '1.5'):
            with self.subTest(timeout=timeout):
                result = self.run_preflight('ledger_hang', timeout)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('consistency check passed', result.stdout)


if __name__ == '__main__':
    unittest.main()

"""Execute runner with fake Git/psql; emitted SQL only, no database/network."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / 'apps/web-platform/scripts'

class MigrationLedger(unittest.TestCase):
    def capture(self, bodies, fail=False, producer_failure=None, partial_output=False, fail_barrier=False,
                hash_output='1' * 40, hash_exit=0, trace_mode=None,
                credential_name='DATABASE_URL', credential_value='postgres://synthetic.invalid/never-contacted'):
        with tempfile.TemporaryDirectory(prefix='codex9051-ledger-') as name:
            root = Path(name)
            for path in ('scripts/sql', 'supabase/migrations', 'bin'):
                (root/path).mkdir(parents=True)
            shutil.copyfile(SCRIPTS/'run-migrations.sh', root/'scripts/run-migrations.sh')
            shutil.copyfile(SCRIPTS/'sql/codex-auth-mode-pre-migration.sql', root/'scripts/sql/codex-auth-mode-pre-migration.sql')
            (root/'scripts/postgrest-reload-schema.sh').write_text('#!/usr/bin/env bash\nexit 0\n')
            for filename, body in bodies.items():
                (root/'supabase/migrations'/filename).write_text(body)
            (root/'bin/git').write_text('''#!/usr/bin/env bash
case "$1" in
fetch) exit 0 ;;
ls-tree) printf '100644 blob 1111111111111111111111111111111111111111 fixture.sql\\n' ;;
hash-object) printf '%s\\n' "$HASH_OUTPUT"; exit "$HASH_EXIT_CODE" ;;
*) exit 64 ;;
esac
''')
            (root/'bin/psql').write_text('''#!/usr/bin/python3
import json, os, sys
args = sys.argv[1:]
if '-c' in args:
    text=args[args.index('-c')+1]
    if 'count(*)' in text: print('0')
    elif 'to_regclass' in text: print('t')
else:
    text=sys.stdin.read()
with open(os.environ['CAPTURE'], 'a') as handle:
    handle.write(json.dumps({'argv':args,'sql':text})+'\\n')
if '-f' in args and os.environ['FAIL_APPLY']=='1': sys.exit(1)
if '-c' in args and os.environ['FAIL_BARRIER']=='1' and 'REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment' in text: sys.exit(1)
''')
            for path in ('git', 'psql'):
                (root/'bin'/path).chmod(0o755)
            if producer_failure:
                command, target = producer_failure
                shim = root/'bin'/command
                shim.write_text('''#!/usr/bin/python3
import os, sys
if any(arg.endswith(os.environ['FAIL_PRODUCER_TARGET']) for arg in sys.argv[1:]):
    if os.environ['PARTIAL_OUTPUT']=='1': print("SELECT 'partial synthetic body';")
    sys.exit(42)
os.execv('/usr/bin/COMMAND', ['COMMAND', *sys.argv[1:]])
'''.replace('COMMAND', command))
                shim.chmod(0o755)
            env = {'PATH': str(root/'bin') + ':/usr/bin:/bin', 'HOME': str(root/'absent'),
                   credential_name: credential_value,
                   'CAPTURE': str(root/'capture.jsonl'), 'FAIL_APPLY': '1' if fail else '0',
                   'FAIL_PRODUCER_TARGET': producer_failure[1] if producer_failure else '',
                   'PARTIAL_OUTPUT': '1' if partial_output else '0',
                   'FAIL_BARRIER': '1' if fail_barrier else '0',
                   'HASH_OUTPUT': hash_output, 'HASH_EXIT_CODE': str(hash_exit)}
            argv = ['bash']
            if trace_mode == 'flag':
                argv.append('-x')
            elif trace_mode == 'environment':
                env['SHELLOPTS'] = 'xtrace'
            else:
                self.assertIsNone(trace_mode, 'unknown trace fixture mode')
            result = subprocess.run([*argv, str(root/'scripts/run-migrations.sh'), '--bootstrap=skip'],
                                    cwd=root, env=env, capture_output=True, text=True, timeout=15)
            capture_file = root/'capture.jsonl'
            captures = [json.loads(line) for line in capture_file.read_text().splitlines()] if capture_file.exists() else []
            return result, [item for item in captures if '-f' in item['argv']], captures

    def test_failed_or_malformed_blob_hash_refuses_before_apply_or_ledger_insert(self):
        cases = [
            ('failed-empty', '', 1),
            ('failed-with-valid-looking-output', '1' * 40, 1),
            ('empty', '', 0),
            ('short', '1' * 39, 0),
            ('long', '1' * 41, 0),
            ('uppercase', 'A' * 40, 0),
            ('non-hex', 'g' * 40, 0),
            ('leading-space', ' ' + '1' * 40, 0),
            ('trailing-space', '1' * 40 + ' ', 0),
            ('multiple-lines', '1' * 40 + '\n' + '2' * 40, 0),
        ]
        for name, output, exit_code in cases:
            with self.subTest(name=name):
                result, applies, calls = self.capture({'001_synthetic.sql': 'SELECT 1;\n'},
                    hash_output=output, hash_exit=exit_code)
                self.assertNotEqual(result.returncode, 0, 'untrusted Git blob identity must refuse')
                self.assertIn('Could not obtain a valid Git blob hash', result.stdout)
                self.assertEqual(applies, [], 'hash refusal must precede every migration apply')
                self.assertFalse(any('INSERT INTO public._schema_migrations' in call['sql'] for call in calls),
                                 'hash refusal must not insert a ledger row')

    def test_xtrace_refuses_before_credential_expansion_or_psql(self):
        for credential_name in ('DATABASE_URL', 'DATABASE_URL_POOLER'):
            canary = 'postgres://synthetic-xtrace-canary@synthetic.invalid/never-contacted'
            control, control_applies, control_calls = self.capture(
                {'001_synthetic.sql': 'SELECT 1;\n'}, credential_name=credential_name, credential_value=canary)
            self.assertEqual(control.returncode, 0)
            self.assertEqual(len(control_applies), 1)
            self.assertTrue(any(call['argv'][0] == canary for call in control_calls),
                            'positive control must pass the selected synthetic credential to fake psql')
            for trace_mode in ('flag', 'environment'):
                with self.subTest(credential_name=credential_name, trace_mode=trace_mode):
                    result, applies, calls = self.capture({'001_synthetic.sql': 'SELECT 1;\n'},
                        trace_mode=trace_mode, credential_name=credential_name, credential_value=canary)
                    self.assertEqual({
                        'refused_rc_78': result.returncode == 78,
                        'stdout_has_no_canary': canary not in result.stdout,
                        'stderr_has_no_canary': canary not in result.stderr,
                        'no_psql_calls': calls == [],
                        'no_apply': applies == [],
                    }, {
                        'refused_rc_78': True,
                        'stdout_has_no_canary': True,
                        'stderr_has_no_canary': True,
                        'no_psql_calls': True,
                        'no_apply': True,
                    })

    def test_column_decision_occurs_after_body_inside_same_transaction(self):
        result, applies, calls = self.capture({'001_synthetic.sql': 'SELECT 1;\n',
                    '054_synthetic.sql': 'ALTER TABLE public._schema_migrations ADD COLUMN content_sha text;\n',
                    '055_synthetic.sql': 'SELECT 55;\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(applies), 3)
        for item in applies:
            self.assertIn('--single-transaction', item['argv'])
            self.assertEqual(item['argv'][-2:], ['-f', '-'])
            sql = item['sql']
            self.assertIn("attname = 'content_sha'", sql)
            self.assertIn('NOT attisdropped', sql)
            self.assertLess(sql.index(';'), sql.index('FROM pg_attribute'))
            self.assertIn('ELSE', sql)
            self.assertIn('INSERT INTO public._schema_migrations (filename) VALUES', sql)
            self.assertIn('INSERT INTO public._schema_migrations (filename, content_sha) VALUES', sql)
            self.assertNotIn('ALTER TABLE', sql[sql.index('DO $migration_ledger$'):])
        self.assertFalse(any('content_sha' in item['sql'] for item in calls if '-c' in item['argv']))
        self.assertNotIn('INSERT INTO public._schema_migrations', calls[0]['sql'])

    def test_failed_atomic_apply_stops_before_next_migration(self):
        result, applies, _ = self.capture({'001_synthetic.sql': 'SELECT 1;\n',
                                          '002_synthetic.sql': 'SELECT 2;\n'}, fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(applies), 1)
        self.assertIn('Migration failed: 001_synthetic.sql', result.stdout)
        self.assertIn('--single-transaction', applies[0]['argv'])

    def test_codex_guard_body_then_ledger_order_and_no_outer_commit(self):
        result, applies, _ = self.capture({'167_codex_auth_mode_rebind.sql': 'BEGIN;\nSELECT 145;\nCOMMIT;\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        sql = applies[0]['sql']
        self.assertLess(sql.index('LOCK TABLE public.workspace_engine_settings'), sql.index('SELECT 145;'))
        self.assertLess(sql.index('SELECT 145;'), sql.index('DO $migration_ledger$'))
        self.assertFalse(any(line.strip() in ('BEGIN;', 'COMMIT;', 'ROLLBACK;') for line in sql.splitlines()))

    def test_every_failed_sql_producer_refuses_before_apply_even_after_partial_output(self):
        # Cover every file-producing assembly site: injected guard, wrapped
        # migration via sed, and unwrapped migration via cat. Include both
        # acknowledgment migrations whose grants must never outlive a body.
        cases = [
            ('cat', 'codex-auth-mode-pre-migration.sql', '167_codex_auth_mode_rebind.sql', True),
            ('sed', '167_codex_auth_mode_rebind.sql', '167_codex_auth_mode_rebind.sql', True),
            ('sed', '171_codex_history_transfer_ack.sql', '171_codex_history_transfer_ack.sql', True),
            ('sed', '172_codex_history_ack_owner_scope.sql', '172_codex_history_ack_owner_scope.sql', True),
            ('cat', '172_codex_history_ack_owner_scope.sql', '172_codex_history_ack_owner_scope.sql', False),
            ('cat', '001_synthetic.sql', '001_synthetic.sql', False),
        ]
        for command, target, filename, wrapped in cases:
            body = 'SELECT 1;\n'
            if wrapped:
                body = 'BEGIN;\n' + body + 'COMMIT;\n'
            control, control_applies, _ = self.capture({filename: body})
            self.assertEqual(control.returncode, 0, control.stderr)
            self.assertEqual(len(control_applies), 1, 'each producer fixture must reach one successful apply')
            for partial in (False, True):
                with self.subTest(command=command, target=target, partial=partial):
                    result, applies, calls = self.capture({filename: body},
                        producer_failure=(command, target), partial_output=partial)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('Could not assemble migration SQL', result.stdout)
                    self.assertEqual(applies, [], 'an incomplete SQL unit must never reach psql')
                    if filename == '172_codex_history_ack_owner_scope.sql':
                        barriers = [call for call in calls if '-c' in call['argv'] and 'REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment' in call['sql']]
                        self.assertEqual(len(barriers), 1, 'the legacy grant barrier must commit before fallible assembly')
                        self.assertIn('REVOKE ALL ON FUNCTION public.codex_history_transfer_acknowledged', barriers[0]['sql'])

    def test_failed_legacy_grant_barrier_refuses_before_assembly_or_apply(self):
        result, applies, calls = self.capture(
            {'172_codex_history_ack_owner_scope.sql': 'SELECT 170;\n'}, fail_barrier=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Could not close Codex acknowledgment RPC grants before migration 172', result.stdout)
        self.assertEqual(applies, [], 'failed revoke barrier must prevent every migration apply')
        barriers = [call for call in calls if '-c' in call['argv'] and 'REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment' in call['sql']]
        self.assertEqual(len(barriers), 1)
        self.assertEqual(calls[-1], barriers[0], 'runner must stop immediately after the failed barrier')

    def test_existing_schema_probe_assertions_with_networkless_git(self):
        # Existing suite hardcodes inner PATH via env -i. Preserve its test
        # assertions in a temporary copy and plant Git alongside each fake
        # psql; intercept fetch, delegate ONLY local read/hash operations.
        with tempfile.TemporaryDirectory(prefix='codex9051-schema-probe-') as name:
            root=Path(name)
            shim=root/'git'
            shim.write_text('''#!/usr/bin/env bash
case "$1" in
fetch) exit 0 ;;
ls-tree|hash-object) exec /usr/bin/git "$@" ;;
*) exit 64 ;;
esac
''')
            shim.chmod(0o755)
            for file in ('run-migrations.sh', 'run-migrations-schema-probe.test.sh'):
                shutil.copyfile(SCRIPTS/file,root/file)
            probe=(root/'run-migrations-schema-probe.test.sh').read_text()
            for variable in ('tmp','tmp3'):
                anchor='chmod +x "$'+variable+'/bin/psql"'
                self.assertEqual(probe.count(anchor),1)
                probe=probe.replace(anchor,anchor+'\ncp "$OFFLINE_GIT" "$'+variable+'/bin/git"')
            (root/'run-migrations-schema-probe.test.sh').write_text(probe)
            result=subprocess.run(['bash',str(root/'run-migrations-schema-probe.test.sh')],
                cwd=REPO,env={'PATH':'/usr/bin:/bin','HOME':str(root/'absent'),
                              'TMPDIR':str(root),'OFFLINE_GIT':str(shim)},
                text=True,capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('9 passed, 0 failed',result.stdout)

if __name__ == '__main__':
    unittest.main()

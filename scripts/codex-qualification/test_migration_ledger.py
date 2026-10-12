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
    def capture(self, bodies, fail=False):
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
hash-object) printf '1111111111111111111111111111111111111111\\n' ;;
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
''')
            for path in ('git', 'psql'):
                (root/'bin'/path).chmod(0o755)
            env = {'PATH': str(root/'bin') + ':/usr/bin:/bin', 'HOME': str(root/'absent'),
                   'DATABASE_URL': 'postgres://synthetic.invalid/never-contacted',
                   'CAPTURE': str(root/'capture.jsonl'), 'FAIL_APPLY': '1' if fail else '0'}
            result = subprocess.run(['bash', str(root/'scripts/run-migrations.sh'), '--bootstrap=skip'],
                                    cwd=root, env=env, capture_output=True, text=True, timeout=15)
            captures = [json.loads(line) for line in (root/'capture.jsonl').read_text().splitlines()]
            return result, [item for item in captures if '-f' in item['argv']], captures

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
        result, applies, _ = self.capture({'145_codex_auth_mode_rebind.sql': 'BEGIN;\nSELECT 145;\nCOMMIT;\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        sql = applies[0]['sql']
        self.assertLess(sql.index('LOCK TABLE public.workspace_engine_settings'), sql.index('SELECT 145;'))
        self.assertLess(sql.index('SELECT 145;'), sql.index('DO $migration_ledger$'))
        self.assertFalse(any(line.strip() in ('BEGIN;', 'COMMIT;', 'ROLLBACK;') for line in sql.splitlines()))

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

"""Offline source/recipe assertions; never invoke SQL, Docker or recovery."""
import base64
from pathlib import Path
import shutil
import tempfile
import unittest
from prepare import Refused, git, sha
from rehearsal import ledger_sql, recipe, runner_blockers

REPO = Path(__file__).resolve().parents[2]

class Rehearsal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Isolated Git fixture allows testing the uncommitted canonical runner
        # correction without relaxing source_manifest's clean-source refusal.
        # It binds all current migration bytes, but is NOT production evidence:
        # other runtime inputs are deliberately limited to recipe dependencies.
        cls.tmp = tempfile.TemporaryDirectory(prefix='codex9051-recipe-source-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.repo = Path(cls.tmp.name)
        paths = ['apps/web-platform/Dockerfile', 'apps/web-platform/scripts/run-migrations.sh',
                 'apps/web-platform/scripts/sql/codex-auth-mode-pre-migration.sql',
                 'scripts/codex-qualification/prepare.py']
        paths += [str(p.relative_to(REPO)) for p in (REPO/'apps/web-platform/supabase/migrations').glob('*.sql')]
        paths += [str(p.relative_to(REPO)) for p in (REPO/'scripts/codex-qualification').glob('*.py')]
        paths += [str(p.relative_to(REPO)) for p in (REPO/'scripts/codex-qualification/scenarios').glob('*.sql')]
        for path in paths:
            target=cls.repo/path
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(REPO/path,target)
        git(cls.repo,'init','-q')
        git(cls.repo,'add','.')
        git(cls.repo,'-c','user.name=fixture','-c','user.email=fixture@example.test','commit','-qm','synthetic recipe fixture')
        cls.source = git(cls.repo,'rev-parse','HEAD').decode().strip()
        cls.result = recipe(cls.repo,cls.source)

    def test_every_forward_body_is_exact_source_not_schema_substitution(self):
        files = self.result['forward_migrations']
        expected = git(self.repo, 'ls-tree', '-r', '--name-only', self.source, '--',
                       'apps/web-platform/supabase/migrations').decode().splitlines()
        self.assertEqual([f['path'] for f in files],
                         [p for p in expected if p.endswith('.sql') and not p.endswith('.down.sql')])
        for item in files:
            body = base64.b64decode(item['body_base64'], validate=True)
            self.assertEqual(body, git(self.repo, 'cat-file', 'blob', item['blob']))
            self.assertEqual(sha(body), item['sha256'])

    def test_ledger_comparison_derives_names_and_blob_hashes_without_premark(self):
        files = [{'path': 'migrations/001_fixture.sql', 'blob': 'a'*40, 'body_base64': ''},
                 {'path': 'migrations/054_ledger.sql', 'blob': 'b'*40,
                  'body_base64': base64.b64encode(b'ADD COLUMN IF NOT EXISTS content_sha text').decode()}]
        sql = ledger_sql(files)
        self.assertIn('001_fixture.sql', sql)
        self.assertIn('a'*40, sql)
        self.assertIn('FULL JOIN public._schema_migrations', sql)
        self.assertNotIn('INSERT INTO public._schema_migrations', sql)
        self.assertIn("e.filename < '054_ledger.sql' THEN NULL ELSE e.blob END", sql)
        with self.assertRaises(Refused):
            ledger_sql(files + [{'path': "migrations/a'bad.sql", 'blob': 'a'*40, 'body_base64': ''}])

    def test_fresh_schema_fix_is_recognized_but_inherited_runner_stays_blocked(self):
        old = b"filename TEXT PRIMARY KEY,\napplied_at TIMESTAMPTZ NOT NULL DEFAULT now()\ngit hash-object \"$migration_file\"\nINSERT INTO public._schema_migrations (filename, content_sha)"
        self.assertEqual(runner_blockers(old, self.result['forward_migrations']), ['fresh-ledger-content-sha-column'])
        self.assertEqual(runner_blockers((REPO/'apps/web-platform/scripts/run-migrations.sh').read_bytes(),self.result['forward_migrations']), [])
        self.assertFalse(self.result['execute_available'])
        self.assertEqual(self.result['runner']['argv'], ['bash', 'apps/web-platform/scripts/run-migrations.sh', '--bootstrap=skip'])
        self.assertEqual(runner_blockers(b'other runner', []), ['runner-shape-review-required'])

    def test_runtime_receipts_are_required_and_operations_zero(self):
        self.assertEqual(set(self.result['operations'].values()), {0})
        self.assertIn('immutable-image-and-local-auth-receipt', self.result['required_before_execution'])
        self.assertIn('exact-current-source-approval', self.result['required_before_execution'])
        self.assertFalse(self.result['independent_review_complete'])

    def test_dirty_runtime_refusal_survives_recipe_preparation(self):
        file=self.repo/'apps/web-platform/Dockerfile'
        original=file.read_bytes()
        try:
            file.write_bytes(original+b'\n# unapproved runtime change\n')
            with self.assertRaisesRegex(Refused,'Runtime source contains uncommitted changes'):
                recipe(self.repo,self.source)
        finally:
            file.write_bytes(original)

    def test_schema_census_and_all_rows_not_fixed_table_subset(self):
        sql = self.result['scenarios']['00_support.sql']['sql']
        self.assertIn("n.nspname IN ('public','auth','storage')", sql)
        self.assertIn('to_jsonb(t)', sql)
        self.assertIn('pg_attribute', sql)
        self.assertIn('jsonb_agg(row_value ORDER BY row_value::text)', sql)
        self.assertNotIn('LIMIT ', sql)

    def test_race_requires_observed_blocking_and_no_sleep_success(self):
        observe = self.result['scenarios']['42_race_observe.sql']['sql']
        self.assertIn('pg_blocking_pids', observe)
        self.assertIn("wait_event_type = 'Lock'", observe)
        self.assertNotIn('pg_sleep', observe)
        self.assertEqual(self.result['race']['release'], 'controller commits holder only after observer passes')

if __name__ == '__main__':
    unittest.main()

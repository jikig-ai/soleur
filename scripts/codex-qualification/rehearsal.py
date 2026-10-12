"""Offline full-schema recipe. Serializes source bytes; has no execute entrypoint."""
import argparse
import base64
import json
from pathlib import Path
import re
from prepare import canonical, git, preparation, require, sha

RUNNER = 'apps/web-platform/scripts/run-migrations.sh'
GUARD = 'apps/web-platform/scripts/sql/codex-auth-mode-pre-migration.sql'
SCENARIOS = ('00_support.sql', '10_seed.sql', '20_before_replacement.sql',
             '21_after_replacement.sql', '30_scope_and_ack.sql', '40_race_holder.sql',
             '41_race_waiter.sql', '42_race_observe.sql', '43_race_assert.sql', '50_erasure.sql')

def ledger_sql(migrations):
    """Read-only census: compare filename set AND original apply-time blob hashes."""
    creators = [Path(item['path']).name for item in migrations
                if re.search(rb'ADD COLUMN IF NOT EXISTS content_sha text',
                             base64.b64decode(item['body_base64']))]
    require(len(creators) == 1, 'Ledger hash column creation requires review')
    boundary = creators[0]
    values = []
    for item in migrations:
        filename = Path(item['path']).name
        require(re.fullmatch(r'[a-zA-Z0-9._-]+\.sql', filename), 'Unsafe migration filename')
        require(re.fullmatch(r'[0-9a-f]{40}', item['blob']), 'Missing Git blob identity')
        values.append("('%s','%s')" % (filename, item['blob']))
    require(values, 'Forward migration census empty')
    return ("\\set ON_ERROR_STOP on\nDO $census$ BEGIN\n"
            " IF EXISTS (WITH expected(filename, blob) AS (VALUES " + ','.join(values) + ")\n"
            " SELECT 1 FROM expected e FULL JOIN public._schema_migrations m USING(filename)\n"
            " WHERE e.filename IS NULL OR m.filename IS NULL OR m.content_sha IS DISTINCT FROM\n"
            " CASE WHEN e.filename < '" + boundary + "' THEN NULL ELSE e.blob END)\n"
            " THEN RAISE EXCEPTION 'source-bound migration ledger differs'; END IF;\n"
            "END $census$;\n")

def runner_blockers(runner, migrations):
    # This is evidence of the current-source blocker, not a general shell parser.
    # Any changed shape requires review before this recipe can claim clearance.
    text = runner.decode()
    anchors = ["filename TEXT PRIMARY KEY,", "applied_at TIMESTAMPTZ NOT NULL DEFAULT now()",
               'git hash-object "$migration_file"',
               "INSERT INTO public._schema_migrations (filename, content_sha)"]
    if not all(anchor in text for anchor in anchors):
        return ['runner-shape-review-required']
    creators = [item for item in migrations
                if re.search(rb'ADD COLUMN IF NOT EXISTS content_sha text',
                             base64.b64decode(item['body_base64']))]
    if len(creators) != 1:
        return ['content-sha-creation-review-required']
    fixed = ["printf '\\nDO $migration_ledger$\\nBEGIN\\n'",
             "FROM pg_attribute WHERE attrelid = 'public._schema_migrations'::regclass AND attname = 'content_sha' AND NOT attisdropped",
             "INSERT INTO public._schema_migrations (filename) VALUES ('%s');"]
    if all(anchor in text for anchor in fixed):
        return []
    if migrations and migrations[0]['path'] < creators[0]['path']:
        return ['fresh-ledger-content-sha-column']
    return ['runner-shape-review-required']

def recipe(repo, source):
    contract = preparation(repo, source)
    migrations = []
    for item in contract['forward_migrations']:
        body = git(repo, 'cat-file', 'blob', item['blob'])
        migrations.append(dict(item, body_base64=base64.b64encode(body).decode()))
    runner = git(repo, 'show', source + ':' + RUNNER)
    guard = git(repo, 'show', source + ':' + GUARD)
    scenarios = {}
    tree = git(repo, 'ls-tree', '-r', '-z', source, '--', 'scripts/codex-qualification/scenarios')
    for item in tree.split(b'\0'):
        if not item:
            continue
        header, path = item.split(b'\t', 1)
        mode, kind, blob = header.decode().split()
        require(mode in ('100644', '100755') and kind == 'blob', 'Committed regular scenario file required')
        content = git(repo, 'cat-file', 'blob', blob)
        scenarios[Path(path.decode()).name] = {'sha256': sha(content), 'sql': content.decode()}
    require(set(scenarios) == set(SCENARIOS), 'Complete reviewed scenario filename census required')
    scenarios['01_source_ledger.sql'] = {'sql': ledger_sql(migrations)}
    scenarios['01_source_ledger.sql']['sha256'] = sha(scenarios['01_source_ledger.sql']['sql'].encode())
    components = {name: sha(git(repo, 'show', source + ':scripts/codex-qualification/' + name))
                  for name in ('rehearsal.py', 'test_rehearsal.py', 'test_migration_ledger.py')}
    components.update({
                  **{name: item['sha256'] for name, item in scenarios.items()}}
                     )
    identity = dict(contract['identity'], rehearsal_components_sha256=sha(canonical(components)))
    blockers = runner_blockers(runner, migrations)
    return {'status': 'offline-recipe-runtime-and-independent-review-pending',
            'source_sha': source, 'identity': identity, 'recipe_sha256': sha(canonical(identity)),
            'forward_migrations': migrations, 'scenarios': scenarios,
            'runner': {'path': RUNNER, 'sha256': sha(runner),
                       'argv': ['bash', RUNNER, '--bootstrap=skip'],
                       'canonical_source_bytes': True, 'fresh_ledger_fix': 'post-body-column-admission-in-atomic-transaction',
                       'production_guard_sha256': sha(guard),
                       'pre_marked_migrations': [], 'schema_substitutions': []},
            'blockers': blockers,
            'race': {'holder': '40_race_holder.sql', 'waiter': '41_race_waiter.sql',
                     'observe': '42_race_observe.sql', 'assert': '43_race_assert.sql',
                     'release': 'controller commits holder only after observer passes',
                     'deadline_seconds': 30, 'order': 'owner: workspace/settings -> run -> checkpoint; checkpoint: run lock -> attempt generation read -> checkpoint',
                     'failure_cleanup': 'rollback both owned sessions; retain failure; close sessions'},
            'steps': ['canonical current-source full forward apply on fresh owned Supabase',
                      '00_support.sql', '01_source_ledger.sql', '10_seed.sql', '20_before_replacement.sql',
                      'snapshot workspace and storage file byte manifests under owned volume controller',
                      'replace only application container with approved immutable image; retain database/auth/storage/volumes',
                      '21_after_replacement.sql', '30_scope_and_ack.sql',
                      '40/41 concurrent sessions; observe 42; commit holder; wait and assert 43',
                      '50_erasure.sql', '01_source_ledger.sql'],
            'required_before_execution': ['exact-current-source-approval', 'reviewed-canonical-fresh-ledger-fix',
                                          'independent-full-schema-review', 'owned-docker-internal-network-controller',
                                          'TLS-namespace-bridge-no-external-route', 'per-role-command-env-admission',
                                          'immutable-image-and-local-auth-receipt',
                                          'owned-synthetic-storage-and-workspace-file-fixtures-and-byte-manifests',
                                          'runtime-schema-census-and-session-race-controller'],
            'execute_available': False, 'independent_review_complete': False,
            'operations': {'database': 0, 'docker': 0, 'build': 0, 'provider': 0, 'credentials': 0}}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--preview', action='store_true', required=True)
    args = parser.parse_args()
    require(not git(args.repo, 'status', '--porcelain', '--',
                    'scripts/codex-qualification', 'scripts/lib/codex-qualification.test.sh').strip(),
            'Preparation components changed; commit before source-bound preview')
    result = recipe(args.repo, args.source_sha)
    # Full bytes are accessible through recipe() for offline assembly/review.
    # The CLI prints recipe metadata, hashes/counts and blockers; it never
    # dispatches an operational command or treats the described argv as approval.
    print(json.dumps({key: value for key, value in result.items()
                      if key not in ('forward_migrations', 'scenarios')} |
                     {'forward_migration_count': len(result['forward_migrations']),
                      'scenario_sha256': {name: item['sha256'] for name, item in result['scenarios'].items()}}, indent=2))

if __name__ == '__main__':
    main()

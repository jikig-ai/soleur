"""Offline candidate export fixtures: isolated Git and synthesized input bytes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import candidate
from candidate import Refused, candidate_spec, assemble
import prepare


DOCKERFILE = '''FROM node:fixture AS builder
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
RUN npm run build
RUN bash scripts/assert-dev-signin-eliminated.sh
RUN npm run build:server
RUN ./node_modules/.bin/esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs
COPY _plugin-vendored /opt/soleur/plugin
USER soleur
CMD ["node", "dist/server/index.cjs"]
'''


class Candidate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex9051-candidate-fixture-')
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.destination = self.root / 'candidate'
        self.env = {**prepare.ENV, 'GIT_AUTHOR_NAME': 'Synthetic Fixture',
                    'GIT_COMMITTER_NAME': 'Synthetic Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.com',
                    'GIT_COMMITTER_EMAIL': 'fixture@example.com'}
        self.git('init', '--quiet')
        self.inputs = {
            'apps/web-platform/Dockerfile': (DOCKERFILE.encode(), 0o644),
            'apps/web-platform/.dockerignore': (b'.env*\nnode_modules\n', 0o644),
            'apps/web-platform/package.json': (b'{"name":"synthetic"}\n', 0o644),
            'apps/web-platform/lib/runtime.bin': (b'\0\xffsynthetic-runtime\n', 0o644),
            'apps/web-platform/scripts/run.sh': (b'#!/bin/sh\nexit 0\n', 0o755),
            'apps/web-platform/supabase/migrations/001_fixture.sql': (b'-- synthetic full migration one\n', 0o644),
            'apps/web-platform/supabase/migrations/002_fixture.sql': (b'-- synthetic full migration two\n', 0o644),
            'plugins/soleur/agents/fixture.md': (b'# Synthetic agent\n', 0o644),
            'plugins/soleur/scripts/fixture.sh': (b'#!/bin/sh\nexit 0\n', 0o755),
        }
        for relative, (data, mode) in self.inputs.items():
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(mode)
        (self.repo / 'plugins/soleur/fixture.md').symlink_to('agents/fixture.md')
        (self.repo / 'apps/web-platform/scripts/alias.sh').symlink_to('run.sh')
        components = self.repo / 'scripts/codex-qualification'
        components.mkdir(parents=True)
        for module in (candidate, prepare):
            (components / Path(module.__file__).name).write_bytes(Path(module.__file__).read_bytes())
        self.commit()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        result = subprocess.run(['git', '-C', str(self.repo), *args], env=self.env,
                                check=True, capture_output=True, timeout=15)
        return result.stdout.decode().strip()

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '--quiet', '-m', 'Synthesized candidate fixture')
        self.source = self.git('rev-parse', 'HEAD')

    def test_exact_bytes_modes_vendor_and_identity_correspondence(self):
        spec = candidate_spec(self.repo, self.source, self.destination)
        result = assemble(self.repo, self.source, self.destination)
        self.assertEqual(result['identity'], spec['identity'])
        self.assertEqual(result['runtime_input_count'], len(self.inputs) + 2)
        self.assertEqual(result['forward_migration_count'], 2)
        for relative, (data, mode) in self.inputs.items():
            exported = self.destination / 'runtime' / relative
            self.assertEqual(exported.read_bytes(), data)
            self.assertEqual(exported.stat().st_mode & 0o777, mode)
            if relative.startswith('plugins/soleur/'):
                vendor = self.destination / 'runtime/apps/web-platform/_plugin-vendored' / relative.removeprefix('plugins/soleur/')
                self.assertEqual(vendor.read_bytes(), data)
                self.assertEqual(vendor.stat().st_mode & 0o777, mode)
        self.assertEqual(os.readlink(self.destination / 'runtime/plugins/soleur/fixture.md'), 'agents/fixture.md')
        self.assertEqual(os.readlink(self.destination / 'runtime/apps/web-platform/_plugin-vendored/fixture.md'), 'agents/fixture.md')
        self.assertEqual(os.readlink(self.destination / 'runtime/apps/web-platform/scripts/alias.sh'), 'run.sh')
        self.assertEqual((self.destination / 'production.Dockerfile').read_bytes(), DOCKERFILE.encode())
        self.assertEqual((self.destination / 'controlled.Dockerfile').read_bytes(), prepare.controlled_dockerfile(DOCKERFILE).encode())
        self.assertEqual((self.destination / 'runtime/apps/web-platform/.dockerignore').read_bytes(), b'.env*\nnode_modules\n')
        receipt = json.loads((self.destination / 'candidate-contract.json').read_text())
        self.assertEqual(receipt['identity'], spec['identity'])
        self.assertFalse(receipt['execute_authorized'])
        self.assertIsNone(receipt['image_id'])
        self.assertEqual(set(receipt['operations'].values()), {0})

    def assembled_auxiliary(self):
        spec = candidate_spec(self.repo, self.source, self.destination)
        assemble(self.repo, self.source, self.destination)
        auxiliary = [
            {'path': 'candidate-contract.json', 'content': prepare.canonical(
                {**candidate.metadata(spec), 'export_manifest': spec['export_manifest']}) + b'\n',
             'permissions': 0o644},
            {'path': 'build-recipe.json', 'content': prepare.canonical(spec['build_recipe']) + b'\n',
             'permissions': 0o644},
            {'path': 'docker-config/config.json', 'content': b'{}\n', 'permissions': 0o600},
        ]
        descriptor = os.open(self.destination, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.addCleanup(os.close, descriptor)
        return spec, auxiliary, descriptor

    def test_assembled_auxiliary_inventory_requires_exact_metadata_bytes_modes_and_types(self):
        spec, auxiliary, descriptor = self.assembled_auxiliary()
        candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)
        # Default verification continues to reject every extra leaf.
        with self.assertRaises(Refused):
            candidate.verify_exports(descriptor, spec['export_manifest'])
        for row in auxiliary:
            file = self.destination / row['path']
            original = file.read_bytes()
            file.write_bytes(original + b'changed')
            with self.subTest(path=row['path']), self.assertRaises(Refused):
                candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)
            file.write_bytes(original)
        config = self.destination / 'docker-config/config.json'
        config.chmod(0o644)
        with self.assertRaises(Refused):
            candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)
        config.chmod(0o600)
        recipe = self.destination / 'build-recipe.json'
        contents = recipe.read_bytes()
        recipe.unlink()
        recipe.symlink_to('candidate-contract.json')
        with self.assertRaises(Refused):
            candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)
        recipe.unlink()
        recipe.write_bytes(contents)
        recipe.chmod(0o644)
        extra = self.destination / 'unexpected.txt'
        extra.write_bytes(b'synthetic extra')
        with self.assertRaises(Refused):
            candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)
        extra.unlink()
        candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=auxiliary)

    def test_auxiliary_inventory_rejects_duplicates_collisions_and_unsupported_modes(self):
        spec, auxiliary, descriptor = self.assembled_auxiliary()
        for invalid in [auxiliary + [auxiliary[0]],
                        [{**auxiliary[0], 'path': spec['export_manifest'][0]['path']}],
                        [{**auxiliary[0], 'permissions': 0o777}],
                        [{**auxiliary[0], 'permissions': True}],
                        [{**auxiliary[0], 'path': '../escape'}],
                        [{**auxiliary[0], 'content': 'text'}]]:
            with self.subTest(invalid=repr(invalid)[:100]), self.assertRaises(Refused):
                candidate.verify_exports(descriptor, spec['export_manifest'], auxiliary=invalid)

    def test_public_build_args_clean_environment_and_metadata_preview(self):
        spec = candidate_spec(self.repo, self.source, self.destination)
        config = prepare.synthetic_browser_config()
        self.assertFalse(self.destination.exists())
        recipe = spec['build_recipe']
        self.assertEqual(recipe['build_args']['NEXT_PUBLIC_SUPABASE_URL'], config['url'])
        self.assertEqual(recipe['build_args']['NEXT_PUBLIC_SUPABASE_ANON_KEY'], config['anon_key'])
        self.assertEqual(prepare.sha(config['anon_key'].encode()), spec['browser']['anon_key_sha256'])
        self.assertEqual(set(recipe['build_args']), {'NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'BUILD_SHA', 'BUILD_VERSION'})
        self.assertEqual(recipe['environment']['DOCKER_CONFIG'], str(self.destination / 'docker-config'))
        self.assertEqual(recipe['environment']['HOME'], str(self.destination / 'builder-home'))
        self.assertTrue(recipe['replace_environment'])
        self.assertFalse(recipe['execute_authorized'])
        self.assertNotIn(config['signing_material'], json.dumps(spec))
        preview = candidate.metadata(spec)
        self.assertNotIn(config['anon_key'], json.dumps(preview))
        self.assertNotIn('build_recipe', preview)
        assemble(self.repo, self.source, self.destination)
        self.assertEqual(json.loads((self.destination / 'docker-config/config.json').read_text()), {})
        self.assertEqual((self.destination / 'docker-config/config.json').stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads((self.destination / 'build-recipe.json').read_text()), recipe)

    def test_source_and_component_changes_are_refused_before_writes(self):
        with self.assertRaises(Refused):
            assemble(self.repo, 'a' * 40, self.destination)
        (self.repo / 'apps/web-platform/package.json').write_text('changed runtime')
        with self.assertRaises(Refused):
            assemble(self.repo, self.source, self.destination)
        self.assertFalse(self.destination.exists())
        (self.repo / 'apps/web-platform/package.json').write_bytes(self.inputs['apps/web-platform/package.json'][0])
        (self.repo / 'scripts/codex-qualification/candidate.py').write_text('unreviewed component')
        with self.assertRaises(Refused):
            assemble(self.repo, self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_existing_absolute_relative_and_symlink_destinations_refuse(self):
        self.destination.mkdir()
        sentinel = self.destination / 'sentinel'
        sentinel.write_bytes(b'preserve-existing')
        for path in (self.destination, Path('relative-path'), Path('/etc/codex9051-candidate'),
                     Path('/tmp'), self.root / '..' / 'escape'):
            with self.subTest(path=path), self.assertRaises(Refused):
                assemble(self.repo, self.source, path)
        self.assertEqual(sentinel.read_bytes(), b'preserve-existing')
        alias = self.root / 'alias'
        alias.symlink_to(self.destination, target_is_directory=True)
        with self.assertRaises(Refused):
            assemble(self.repo, self.source, alias / 'new')
        self.assertFalse((self.destination / 'new').exists())

    def test_credential_shaped_sources_and_symlink_escape_refuse(self):
        for relative in ('apps/web-platform/.env.local', 'plugins/soleur/synthetic.key', 'plugins/soleur/synthetic.pem'):
            path = self.repo / relative
            path.write_bytes(b'synthetic-only-do-not-export')
            self.commit()
            with self.subTest(relative=relative), self.assertRaises(Refused):
                assemble(self.repo, self.source, self.destination)
            self.assertFalse(self.destination.exists())
            path.unlink()
            self.commit()
        link = self.repo / 'plugins/soleur/unsafe-link'
        for target in ('/etc/passwd', '../../apps/web-platform/package.json', '../../outside'):
            link.symlink_to(target)
            self.commit()
            with self.subTest(target=target), self.assertRaises(Refused):
                assemble(self.repo, self.source, self.destination)
            self.assertFalse(self.destination.exists())
            link.unlink()
            self.commit()

    def test_corrupt_export_mutant_is_detected(self):
        original = candidate.write_blob
        def corrupt(directory, relative, content, mode):
            if relative == 'runtime/apps/web-platform/lib/runtime.bin':
                content = b'corrupt-mutant'
            return original(directory, relative, content, mode)
        with patch('candidate.write_blob', side_effect=corrupt), self.assertRaises(Refused):
            assemble(self.repo, self.source, self.destination)
        self.assertFalse((self.destination / 'candidate-contract.json').exists())

    def test_corrupt_export_oracle_detects_deleted_verification(self):
        result = unittest.TestResult()
        with patch('candidate.verify_exports', return_value=None):
            unittest.FunctionTestCase(self.test_corrupt_export_mutant_is_detected).run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.failures), 1)
        self.assertIn('Refused not raised', result.failures[0][1])

    def test_vendor_root_collision_refuses_before_creating_task(self):
        (self.repo / 'apps/web-platform/_plugin-vendored').write_bytes(b'collision')
        self.commit()
        with self.assertRaises(Refused):
            assemble(self.repo, self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_owned_worktree_soleur_task_is_an_admitted_destination(self):
        (self.repo / '.soleur').mkdir()
        destination = self.repo / '.soleur/candidate-fixture'
        result = assemble(self.repo, self.source, destination)
        self.assertEqual(result['destination'], str(destination))
        self.assertTrue((destination / 'candidate-contract.json').is_file())
        with self.assertRaises(Refused):
            candidate_spec(self.repo, self.source, self.repo / 'source-output')

    def test_offline_cli_has_only_preview_or_assembly_and_prints_no_token(self):
        command = [sys.executable, '-E', '-B', '-W', 'error',
                   str(self.repo / 'scripts/codex-qualification/candidate.py'),
                   '--repo', str(self.repo), '--source-sha', self.source, '--directory', str(self.destination)]
        environment = {**prepare.ENV, 'DOCKER_HOST': 'tcp://foreign.invalid:2375',
                       'SENTRY_AUTH_TOKEN': 'synthetic-provider-token-do-not-use'}
        preview = subprocess.run([*command, '--preview'], env=environment, check=True,
                                 capture_output=True, text=True, timeout=15)
        self.assertFalse(self.destination.exists())
        self.assertEqual(json.loads(preview.stdout)['identity']['source_sha'], self.source)
        self.assertNotIn(prepare.synthetic_browser_config()['anon_key'], preview.stdout)
        self.assertNotIn(environment['SENTRY_AUTH_TOKEN'], preview.stdout)
        refused = subprocess.run([*command, '--preview', '--build'], env=environment,
                                 capture_output=True, text=True, timeout=15)
        self.assertEqual(refused.returncode, 2)
        self.assertFalse(self.destination.exists())
        assembled = subprocess.run([*command, '--assemble'], env=environment, check=True,
                                   capture_output=True, text=True, timeout=15)
        self.assertEqual(json.loads(assembled.stdout)['identity']['source_sha'], self.source)
        self.assertNotIn(prepare.synthetic_browser_config()['anon_key'], assembled.stdout)


if __name__ == '__main__':
    unittest.main()

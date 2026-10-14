"""Pure operational-contract tests; Git fixtures contain synthesized bytes only."""
import copy
import json
from pathlib import Path
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import candidate
import prepare
import test_candidate
import operational


class Operational(unittest.TestCase):
    def setUp(self):
        class FixtureClock:
            @classmethod
            def now(cls, _zone):
                return datetime(2026, 10, 13, tzinfo=timezone.utc)
        self.clock_patch = patch('candidate.datetime', FixtureClock)
        self.clock_patch.start()
        self.addCleanup(self.clock_patch.stop)
        self.fixture = test_candidate.Candidate()
        self.fixture.setUp()
        self.repo = self.fixture.repo
        self.destination = self.fixture.destination
        self.component = self.repo / 'scripts/codex-qualification/operational.py'
        self.component.write_bytes(Path(operational.__file__).read_bytes())
        for name in ('role_profiles.py', 'api_policy.py', 'namespace.py', 'local_tls.py',
                     'rehearsal.py', 'retained_files.py', 'session_controller.py', 'controller_inputs.py',
                     'controller_adapters.py', 'test_controller_adapters.py',
                     'controller_transports.py', 'test_controller_transports.py'):
            (self.component.parent / name).write_bytes((Path(__file__).parent / name).read_bytes())
        for name in ('40_race_holder.sql', '41_race_waiter.sql', '42_race_observe.sql', '43_race_assert.sql'):
            path = self.component.parent / 'scenarios' / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(('SELECT 1; -- synthesized ' + name + '\n').encode())
        self.fixture.commit()
        self.source = self.fixture.source
        self.contract = operational.prepare_operational(self.repo, self.source, self.destination)
        self.now = 1791849600  # Synthesized observation clock, not a live receipt.
        self.image = {'Id': 'sha256:' + 'a' * 64,
                      'Config': {'Entrypoint': ['docker-entrypoint.sh'], 'Cmd': ['node', 'dist/server/index.cjs'],
                                 'Env': [], 'User': 'soleur', 'WorkingDir': '/app',
                                 'Healthcheck': None, 'ExposedPorts': {}, 'Volumes': {}, 'OnBuild': None}}

    def tearDown(self):
        self.fixture.tearDown()

    def receipt(self, kind):
        facts = {
            'build': {'builder_binary_sha256': 'b' * 64, 'daemon_id': 'fixture-daemon',
                      'export_manifest_sha256': self.contract['builder']['export_manifest_sha256'],
                      'build_recipe_sha256': self.contract['builder']['build_recipe_sha256'],
                      'controlled_dockerfile_sha256': self.contract['identity']['controlled_dockerfile_sha256']},
            'image': {'Config': copy.deepcopy(self.image['Config']),
                      'config_sha256': prepare.sha(prepare.canonical(self.image['Config']))},
            'filesystem': {'manifest_sha256': 'c' * 64, 'inventory_sha256': 'd' * 64,
                           'scope': 'complete-production-image-filesystem'},
            'namespace': {'manifest_sha256': 'e' * 64, 'task_ca_sha256': 'f' * 64,
                          'hostname': self.contract['browser']['hostname']},
            'auth': {'namespace_manifest_sha256': 'e' * 64, 'task_ca_sha256': 'f' * 64,
                     'hostname': self.contract['browser']['hostname'],
                     'browser_contract_sha256': self.contract['identity']['browser_contract_sha256'],
                     'anon_key_sha256': self.contract['browser']['anon_key_sha256'],
                     'mode': 'owned-local-synthetic', 'provider_credentials': False,
                     'renderer_authenticated': True, 'browser_authenticated': True},
        }
        return {'kind': kind, 'identity': copy.deepcopy(self.contract['identity']),
                'pairing_sha256': self.contract['pairing_sha256'],
                'operational_sha256': self.contract['operational_sha256'],
                'image_id': self.image['Id'], 'observed_at': self.now - 10, 'expires_at': self.now + 100,
                'issuer': {'name': 'synthesized-observer', 'key_id': 'fixture-key'},
                'provenance': {'observer_id': 'fixture-observer', 'tool_sha256': '1' * 64,
                               'artifact_sha256': '2' * 64}, 'facts': facts[kind]}

    def validate(self, kind, receipt):
        return operational.validate_evidence(self.contract, kind, receipt, now=self.now,
                                             expected_image=self.image,
                                             expected_namespace={'manifest_sha256': 'e' * 64,
                                                                 'task_ca_sha256': 'f' * 64})

    def test_preparation_writes_nothing_and_preserves_pending_roles(self):
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.contract['execute_authorized'])
        self.assertEqual(set(self.contract['operations'].values()), {0})
        self.assertEqual(set(self.contract['roles']),
                         {'db', 'kong', 'auth', 'inbucket', 'rest', 'storage', 'renderer',
                          'browser', 'tls', 'resolver', 'migration'})
        for role in self.contract['roles'].values():
            self.assertIsNone(role['image_id'])
            self.assertIsNone(role['image_config'])
            self.assertIsNone(role['profile'])
            self.assertIsNone(role['recipe'])
            self.assertFalse(role['admissible'])
        self.assertEqual(len(self.contract['roles']['renderer']['container_name_templates']), 2)
        self.assertEqual(len(self.contract['roles']['migration']['container_name_templates']), 8)
        self.assertEqual(len(self.contract['session_prerequisites']['scenario_sha256']), 4)
        self.assertEqual(self.contract['retained_prerequisites']['owner_and_quiescence_proof'], 'pending')
        dumped = json.dumps(self.contract)
        self.assertNotIn(prepare.synthetic_browser_config()['anon_key'], dumped)
        self.assertNotIn(prepare.synthetic_browser_config()['signing_material'], dumped)
        self.assertNotIn('fixture_roles', dumped)

    def test_builder_binds_exact_source_recipe_and_unresolved_dependencies(self):
        spec = candidate.candidate_spec(self.repo, self.source, self.destination)
        builder = self.contract['builder']
        self.assertEqual(builder['build_recipe_sha256'], spec['build_recipe_sha256'])
        self.assertEqual(builder['export_manifest_sha256'], spec['export_manifest_sha256'])
        self.assertEqual(builder['argv_sha256'], prepare.sha(prepare.canonical(spec['build_recipe']['argv'])))
        self.assertIsNone(builder['binary_sha256'])
        self.assertIsNone(builder['daemon_identity'])
        self.assertEqual(set(builder['dependency_routes']), {'npm', 'apt', 'github-cli', 'playwright'})
        self.assertTrue(all(value == 'pending' for value in builder['dependency_routes'].values()))
        self.assertEqual(self.contract['budget'], {'memory_bytes': 8 * 1024**3,
                                                 'work_seconds': 1800, 'cleanup_seconds': 300})
        self.assertEqual([phase['phase'] for phase in self.contract['namespace_order']],
                         ['registered-network-and-services', 'observed-kong', 'observed-tls-and-resolver',
                          'renderer-and-browser'])

    def test_current_source_and_operational_bytes_must_be_committed(self):
        with self.assertRaises(prepare.Refused):
            operational.prepare_operational(self.repo, 'f' * 40, self.destination)
        self.component.write_bytes(b'uncommitted operational source')
        with self.assertRaises(prepare.Refused):
            operational.prepare_operational(self.repo, self.source, self.destination)
        self.fixture.commit()
        with self.assertRaises(prepare.Refused):
            operational.prepare_operational(self.repo, self.fixture.source, self.destination)

    def test_absent_or_incomplete_receipts_never_admit(self):
        for kind in ('build', 'image', 'filesystem', 'namespace', 'auth'):
            for receipt in (None, {}, {'passed': True}, {'status': 'passed'}):
                with self.subTest(kind=kind, receipt=receipt), self.assertRaises(prepare.Refused):
                    self.validate(kind, receipt)
            receipt = self.receipt(kind)
            for field in ('identity', 'pairing_sha256', 'image_id', 'issuer', 'provenance', 'facts'):
                changed = copy.deepcopy(receipt)
                del changed[field]
                with self.subTest(kind=kind, field=field), self.assertRaises(prepare.Refused):
                    self.validate(kind, changed)

    def test_structural_validity_never_authenticates_or_authorizes(self):
        for kind in ('build', 'image', 'filesystem', 'namespace', 'auth'):
            with self.subTest(kind=kind):
                result = self.validate(kind, self.receipt(kind))
                self.assertEqual(result['status'], 'structurally_valid')
                self.assertEqual(result['issuer_verification'], 'pending')
                self.assertEqual(result['independent_review'], 'pending')
                self.assertFalse(result['execute_authorized'])
                self.assertFalse(result['authentication_established'])
                self.assertFalse(result['profile_admissible'])
        receipt = self.receipt('auth')
        receipt['execute_authorized'] = True
        with self.assertRaises(prepare.Refused):
            self.validate('auth', receipt)
        with self.assertRaises(prepare.Refused):
            operational.validate_evidence(self.contract, 'image', self.receipt('image'), now=self.now)

    def test_pairing_image_source_and_observed_config_changes_refuse(self):
        cases = [('identity', {'source_sha': '0' * 40}), ('pairing_sha256', '0' * 64),
                 ('operational_sha256', '0' * 64), ('image_id', 'sha256:' + '0' * 64)]
        for key, value in cases:
            receipt = self.receipt('image')
            receipt[key] = value
            with self.subTest(key=key), self.assertRaises(prepare.Refused):
                self.validate('image', receipt)
        receipt = self.receipt('image')
        receipt['facts']['Config']['Env'] = ['SYNTHETIC_CHANGED=1']
        receipt['facts']['config_sha256'] = prepare.sha(prepare.canonical(receipt['facts']['Config']))
        with self.assertRaises(prepare.Refused):
            self.validate('image', receipt)
        receipt = self.receipt('build')
        receipt['facts']['build_recipe_sha256'] = '0' * 64
        with self.assertRaises(prepare.Refused):
            self.validate('build', receipt)

    def test_self_consistent_but_nonproduction_image_config_refuses(self):
        for field, value in [('User', 'root'), ('Cmd', ['fixture-command']),
                             ('Entrypoint', ['fixture-entrypoint']), ('OnBuild', ['RUN fixture'])]:
            original = copy.deepcopy(self.image)
            self.image['Config'][field] = value
            receipt = self.receipt('image')
            with self.subTest(field=field), self.assertRaises(prepare.Refused):
                self.validate('image', receipt)
            self.image = original

    def test_stale_expired_future_and_boolean_times_refuse(self):
        for field, value in [('expires_at', self.now), ('observed_at', self.now + 1),
                             ('observed_at', self.now - 1801), ('observed_at', True),
                             ('expires_at', self.contract['browser']['expires_at'] + 1)]:
            receipt = self.receipt('auth')
            receipt[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(prepare.Refused):
                self.validate('auth', receipt)

    def test_auth_namespace_hostname_key_and_mode_mismatches_refuse(self):
        for field, value in [('namespace_manifest_sha256', '0' * 64), ('task_ca_sha256', '0' * 64),
                             ('hostname', 'foreign.invalid'), ('anon_key_sha256', '0' * 64),
                             ('browser_contract_sha256', '0' * 64), ('mode', 'hosted'),
                             ('provider_credentials', True), ('browser_authenticated', False),
                             ('renderer_authenticated', False)]:
            receipt = self.receipt('auth')
            receipt['facts'][field] = value
            with self.subTest(field=field), self.assertRaises(prepare.Refused):
                self.validate('auth', receipt)

    def test_missing_required_component_refuses_complete_operational_contract(self):
        for name in ('role_profiles.py', 'api_policy.py', 'namespace.py', 'local_tls.py',
                     'rehearsal.py', 'retained_files.py', 'session_controller.py', 'controller_inputs.py',
                     'controller_adapters.py', 'test_controller_adapters.py',
                     'controller_transports.py', 'test_controller_transports.py'):
            component = self.component.parent / name
            original = component.read_bytes()
            component.unlink()
            self.fixture.commit()
            with self.subTest(component=name), self.assertRaises(prepare.Refused):
                operational.prepare_operational(self.repo, self.fixture.source, self.destination)
            component.write_bytes(original)
            self.fixture.commit()

    def test_candidate_expiry_remains_enforced_with_explicit_fixture_clock(self):
        class ExpiredClock:
            @classmethod
            def now(cls, _zone):
                return datetime(2026, 10, 20, tzinfo=timezone.utc)
        with patch('candidate.datetime', ExpiredClock), self.assertRaisesRegex(prepare.Refused, 'expired'):
            operational.prepare_operational(self.repo, self.source, self.destination)

    def test_mutated_contract_or_forged_authority_refuses(self):
        self.contract['builder']['binary_sha256'] = '0' * 64
        with self.assertRaises(prepare.Refused):
            self.validate('build', self.receipt('build'))

    def test_rehashed_forged_pairing_or_role_admission_refuses(self):
        original = copy.deepcopy(self.contract)
        for mutation in ('pairing', 'profile', 'budget'):
            self.contract = copy.deepcopy(original)
            if mutation == 'pairing':
                self.contract['pairing_sha256'] = '0' * 64
            elif mutation == 'profile':
                self.contract['roles']['browser']['profile'] = {'passed': True}
            else:
                self.contract['budget']['memory_bytes'] += 1
            self.contract['operational_sha256'] = prepare.sha(prepare.canonical(
                {key: value for key, value in self.contract.items() if key != 'operational_sha256'}))
            with self.subTest(mutation=mutation), self.assertRaises(prepare.Refused):
                self.validate('image', self.receipt('image'))


if __name__ == '__main__':
    unittest.main()

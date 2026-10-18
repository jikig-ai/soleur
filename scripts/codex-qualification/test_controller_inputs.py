"""Synthetic controller-input checks; no adapter or runtime is constructed."""
import copy
from pathlib import Path
import unittest
from unittest.mock import patch

import controller_inputs as inputs
import operational
from prepare import Refused, canonical, sha


class ControllerInputs(unittest.TestCase):
    def setUp(self):
        self.contract = {'identity': {'source_sha': 'a' * 40}, 'execute_authorized': False,
                         'budget': dict(operational.BUDGET),
                         'roles': {role: dict(admissible=False, image_id=None, image_config=None,
                                             recipe=None, profile=None) for role in operational.ROLES},
                         'browser': {'expires_at': 10000},
                         'source_references': {'scripts/codex-qualification/controller_inputs.py':
                                               {'sha256': sha(Path(inputs.__file__).read_bytes())}},
                         'builder': {key: 'b' * 64 for key in ('export_manifest_sha256',
                                     'build_recipe_sha256', 'controlled_dockerfile_sha256',
                                     'argv_sha256', 'environment_sha256')}}
        self.contract['pairing_sha256'] = sha(canonical(self.contract['identity']))
        self.contract['operational_sha256'] = sha(canonical(self.contract))
        self.config = {'Entrypoint': ['synthetic-entry'], 'Cmd': ['synthetic-server'],
                       'Env': [], 'User': '1001', 'WorkingDir': '/app',
                       'Healthcheck': None, 'ExposedPorts': {}, 'Volumes': {}, 'OnBuild': None}
        self.image = {'Id': 'sha256:' + 'c' * 64, 'Config': copy.deepcopy(self.config)}
        self.profile = {'role': 'db', 'image': self.image['Id'], 'image_config': self.config,
                        'create': {key: copy.deepcopy(self.config[key]) for key in inputs.FIELDS},
                        'host': {key: {} if key in ('PortBindings', 'Sysctls') else []
                                 for key in inputs.HOST_FIELDS}, 'aliases': [], 'exec': []}
        self.profile['create']['Healthcheck'] = {'Test': ['NONE']}
        self.builder = dict(self.contract['builder'], binary_sha256='d' * 64,
                            daemon_id='synthetic-daemon', budget=dict(operational.BUDGET),
                            dependency_routes={key: 'e' * 64 for key in inputs.ROUTES})

    def profile_check(self, profile=None, image=None, again=None):
        return inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                   self.profile if profile is None else profile,
                                   reviewed_profile=self.profile,
                                   observed_image=self.image if image is None else image,
                                   reobserved_image=self.image if again is None else again)

    def test_complete_spec_stays_pending_and_content_free(self):
        result = self.profile_check()
        self.assertEqual(result['profile_sha256'], sha(canonical(self.profile)))
        self.assertFalse(result['profile_admissible'])
        self.assertFalse(result['execute_authorized'])
        self.assertEqual(result['issuer_verification'], 'pending')
        self.assertNotIn('create', result)
        self.assertEqual(self.contract['roles']['db']['profile'], None)

    def test_complete_role_and_reserved_name_census(self):
        expected = {role: ('supabase_' + role + '_synthetic-attempt',)
                    for role in ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage')}
        expected.update(renderer=('codex9051-renderer-synthetic-attempt-first',
                                  'codex9051-renderer-synthetic-attempt-replacement'),
                        migration=tuple('codex9051-job-synthetic-attempt-' + str(n) for n in range(1, 9)),
                        browser=('codex9051-browser-synthetic-attempt',),
                        tls=('codex9051-tls-synthetic-attempt',),
                        resolver=('codex9051-resolver-synthetic-attempt',))
        self.assertEqual(set(expected), set(operational.ROLES))
        for role in operational.ROLES:
            self.assertEqual(inputs.role_names('synthetic-attempt', role), expected[role])
            for name in expected[role]:
                profile = dict(self.profile, role=role)
                result = inputs.profile_spec(self.contract, 'synthetic-attempt', name, profile,
                                             reviewed_profile=profile, observed_image=self.image,
                                             reobserved_image=self.image)
                self.assertFalse(result['profile_admissible'])
        for attempt in ('', '../foreign', 'x' * 129):
            with self.subTest(attempt=attempt), self.assertRaises(Refused):
                inputs.role_names(attempt, 'db')
        with self.assertRaises(Refused):
            inputs.profile_spec(self.contract, 'foreign', 'supabase_db_synthetic-attempt', self.profile,
                                reviewed_profile=self.profile, observed_image=self.image,
                                reobserved_image=self.image)

    def test_missing_complete_config_fields_refuse_even_when_both_agree(self):
        for field in self.config:
            profile, image = copy.deepcopy(self.profile), copy.deepcopy(self.image)
            del profile['image_config'][field]
            del image['Config'][field]
            with self.subTest(field=field), self.assertRaises(Refused):
                inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                    profile, reviewed_profile=profile, observed_image=image,
                                    reobserved_image=image)

    def test_reviewed_recipe_or_image_reobservation_changes_refuse(self):
        for key, value in [('Env', ['SYNTHETIC=changed']), ('Cmd', ['other']), ('User', 'root')]:
            changed = copy.deepcopy(self.profile)
            changed['create'][key] = value
            with self.subTest(key=key), self.assertRaises(Refused):
                self.profile_check(changed)
        changed = copy.deepcopy(self.image)
        changed['Config']['Healthcheck'] = {'Test': ['CMD', 'other']}
        with self.assertRaises(Refused):
            self.profile_check(again=changed)

    def test_consistent_reviewed_root_user_refuses_at_nonroot_guard(self):
        for user in ('root', '0', '0000', 'root:1001', '0:1001'):
            profile = copy.deepcopy(self.profile)
            profile['create']['User'] = user
            with self.subTest(user=user), self.assertRaisesRegex(Refused, 'Nonroot effective role user'):
                inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                    profile, reviewed_profile=profile, observed_image=self.image,
                                    reobserved_image=self.image)

    def test_inherited_environment_must_be_represented(self):
        profile, image = copy.deepcopy(self.profile), copy.deepcopy(self.image)
        profile['image_config']['Env'] = image['Config']['Env'] = ['SYNTHETIC_INHERITED=1']
        with self.assertRaises(Refused):
            inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                profile, reviewed_profile=profile, observed_image=image,
                                reobserved_image=image)
        profile['create']['Env'] = ['SYNTHETIC_INHERITED=2']
        self.assertFalse(inputs.profile_spec(self.contract, 'synthetic-attempt',
                         'supabase_db_synthetic-attempt', profile, reviewed_profile=profile,
                         observed_image=image, reobserved_image=image)['profile_admissible'])

    def test_incomplete_host_and_command_recipes_refuse(self):
        for target, field in [('host', 'Dns'), ('create', 'Healthcheck')]:
            profile = copy.deepcopy(self.profile)
            del profile[target][field]
            with self.subTest(field=field), self.assertRaises(Refused):
                inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                    profile, reviewed_profile=profile, observed_image=self.image,
                                    reobserved_image=self.image)

    def test_builder_exact_routes_budget_and_pairing(self):
        result = inputs.builder_spec(self.contract, self.builder, reviewed=self.builder)
        self.assertFalse(result['execute_authorized'])
        for key in self.builder:
            changed = copy.deepcopy(self.builder)
            if key == 'dependency_routes':
                changed[key].pop('playwright')
            elif key == 'budget':
                changed[key]['work_seconds'] += 1
            else:
                changed[key] = 'f' * 64
            with self.subTest(key=key), self.assertRaises(Refused):
                inputs.builder_spec(self.contract, changed, reviewed=self.builder)

    def test_self_consistent_builder_cannot_broaden_budget_or_recipe(self):
        for key in ('budget', 'build_recipe_sha256', 'argv_sha256', 'dependency_routes'):
            changed = copy.deepcopy(self.builder)
            if key == 'budget':
                changed[key]['memory_bytes'] += 1
            elif key == 'dependency_routes':
                changed[key]['unreviewed'] = 'f' * 64
            else:
                changed[key] = 'f' * 64
            with self.subTest(key=key), self.assertRaises(Refused):
                inputs.builder_spec(self.contract, changed, reviewed=changed)

    def test_adapter_requirements_do_not_construct_transports(self):
        result = inputs.adapter_requirements(self.contract)
        self.assertEqual(set(result['adapters']), {'builder', 'namespace', 'session', 'retained'})
        self.assertFalse(result['execute_authorized'])
        for adapter in result['adapters'].values():
            self.assertEqual(adapter['implementation'], 'pending')
            self.assertFalse(adapter['transport_available'])

    def test_mutated_or_admitted_contract_refuses_every_entry(self):
        for mutate in (lambda c: c.update(execute_authorized=True),
                       lambda c: c['roles']['db'].update(profile={}),
                       lambda c: c.update(pairing_sha256='f' * 64)):
            original = copy.deepcopy(self.contract)
            mutate(self.contract)
            self.contract['operational_sha256'] = sha(canonical({key: value for key, value in
                                                  self.contract.items() if key != 'operational_sha256'}))
            with self.assertRaises(Refused):
                self.profile_check()
            with self.assertRaises(Refused):
                inputs.adapter_requirements(self.contract)
            self.contract = original

    def test_unbound_executing_component_refuses_even_rehashed_contract(self):
        self.contract['source_references'] = {}
        self.contract['operational_sha256'] = sha(canonical({key: value for key, value in
                                              self.contract.items() if key != 'operational_sha256'}))
        with self.assertRaises(Refused):
            self.profile_check()
        with self.assertRaises(Refused):
            inputs.builder_spec(self.contract, self.builder, reviewed=self.builder)
        with self.assertRaises(Refused):
            inputs.adapter_requirements(self.contract)

    def test_malformed_effective_environment_and_exec_refuse(self):
        for key, value in [('exec', None), ('role', []), ('create', dict(self.profile['create'], Env=None))]:
            profile = dict(self.profile, **{key: value})
            with self.subTest(key=key), self.assertRaises(Refused):
                inputs.profile_spec(self.contract, 'synthetic-attempt', 'supabase_db_synthetic-attempt',
                                    profile, reviewed_profile=profile, observed_image=self.image,
                                    reobserved_image=self.image)

    def retained(self, phase, start):
        binding = {'attempt': 'synthetic-attempt', 'source_sha': self.contract['identity']['source_sha'],
                   'pairing_sha256': self.contract['pairing_sha256'], 'resource_kind': 'workspace',
                   'resource_id': '1' * 64, 'root_device': 1, 'root_inode': 2,
                   'quiescence_id': ('2' if phase == 'before' else '3') * 64}
        manifest = {'binding': binding, 'entries': [], 'fixture_census_sha256': sha(canonical([])),
                    'manifest_sha256': sha(canonical([])), 'total_bytes': 0, 'root_mode': 0o700,
                    'ownership_verified': False, 'quiescence_verified': False,
                    'issuer_authenticated': False, 'execute_authorized': False}
        observation = {'binding': copy.deepcopy(binding), 'phase': phase,
                       'owner_id': 'synthetic-owner', 'database_id': 'synthetic-db',
                       'writers': [{'container_id': '4' * 64, 'process_pid': 10, 'process_birth': 'birth-1'}],
                       'quiescent_writers': [{'container_id': '4' * 64, 'process_pid': 10, 'process_birth': 'birth-1'}],
                       'quiescence_start': start, 'collection_start': start + 1,
                       'collection_end': start + 2, 'quiescence_end': start + 3,
                       'observed_at': start + 3, 'expires_at': start + 100,
                       'observer_id': 'synthetic-observer', 'artifact_sha256': '5' * 64}
        return manifest, observation

    def retention_check(self, before=None, after=None, prior=None, current=None, writers=None):
        first, old = self.retained('before', 100)
        second, new = self.retained('after', 110)
        return inputs.retention_spec(self.contract, first if before is None else before,
                                     second if after is None else after,
                                     old if prior is None else prior, new if current is None else current,
                                     expected_owner='synthetic-owner', expected_database='synthetic-db',
                                     expected_resource={key: value for key, value in first['binding'].items()
                                                        if key != 'quiescence_id'},
                                     expected_writers=old['writers'] if writers is None else writers, now=120)

    def test_retention_observations_keep_ownership_and_quiescence_unverified(self):
        result = self.retention_check()
        self.assertFalse(result['ownership_verified'])
        self.assertFalse(result['quiescence_verified'])
        self.assertFalse(result['execute_authorized'])

    def test_collection_must_fit_quiescence_and_phase_order(self):
        for key, value in [('quiescence_start', 102), ('collection_end', 104),
                           ('collection_start', 103), ('phase', 'after'), ('expires_at', 120),
                           ('observed_at', 121), ('collection_start', True)]:
            _, old = self.retained('before', 100)
            old[key] = value
            with self.subTest(key=key), self.assertRaises(Refused):
                self.retention_check(prior=old)
        _, new = self.retained('after', 99)
        with self.assertRaises(Refused):
            self.retention_check(current=new)

    def test_owner_root_database_source_and_writer_census_cannot_drift(self):
        for key, value in [('owner_id', 'foreign'), ('database_id', 'foreign'),
                           ('writers', []), ('quiescent_writers', []),
                           ('artifact_sha256', 'short')]:
            _, old = self.retained('before', 100)
            old[key] = value
            with self.subTest(key=key), self.assertRaises(Refused):
                self.retention_check(prior=old)
        for key in ('root_inode', 'resource_id', 'source_sha', 'attempt', 'pairing_sha256', 'quiescence_id'):
            _, old = self.retained('before', 100)
            old['binding'][key] = 'foreign'
            with self.subTest(key=key), self.assertRaises(Refused):
                self.retention_check(prior=old)

    def test_duplicate_or_reused_process_birth_writers_refuse(self):
        _, old = self.retained('before', 100)
        old['writers'] *= 2
        old['quiescent_writers'] *= 2
        with self.assertRaises(Refused):
            self.retention_check(prior=old)
        _, old = self.retained('before', 100)
        old['quiescent_writers'][0]['process_birth'] = 'reused'
        with self.assertRaises(Refused):
            self.retention_check(prior=old)

    def test_consistent_duplicate_pid_with_conflicting_births_refuses(self):
        _, prior = self.retained('before', 100)
        _, current = self.retained('after', 110)
        writers = prior['writers'] + [dict(prior['writers'][0], process_birth='birth-2')]
        for observation in (prior, current):
            observation['writers'] = copy.deepcopy(writers)
            observation['quiescent_writers'] = copy.deepcopy(writers)
        with self.assertRaisesRegex(Refused, 'Duplicate writer'):
            self.retention_check(prior=prior, current=current, writers=writers)

    def test_every_specification_preserves_common_pending_authority(self):
        results = (self.profile_check(), inputs.builder_spec(self.contract, self.builder, reviewed=self.builder),
                   inputs.adapter_requirements(self.contract), self.retention_check())
        for number, result in enumerate(results):
            with self.subTest(entry=number):
                for field in ('execute_authorized', 'profile_admissible', 'authentication_established'):
                    self.assertIs(result[field], False)
                for field in ('issuer_verification', 'independent_review'):
                    self.assertEqual(result[field], 'pending')

    def test_matching_foreign_resource_and_root_still_refuse(self):
        before, prior = self.retained('before', 100)
        after, current = self.retained('after', 110)
        for value in (before, after, prior, current):
            value['binding']['resource_id'] = '7' * 64
            value['binding']['root_inode'] = 77
        with self.assertRaises(Refused):
            self.retention_check(before=before, after=after, prior=prior, current=current)

    def test_retention_integrity_guard_discriminates_matching_forged_manifests(self):
        before, _ = self.retained('before', 100)
        before['manifest_sha256'] = '6' * 64
        with self.assertRaises(Refused):
            self.retention_check(before=before)
        result = unittest.TestResult()
        with patch('retained_files.checked_manifest', side_effect=lambda value: value['entries']):
            unittest.FunctionTestCase(self.test_retention_integrity_guard_discriminates_matching_forged_manifests_inner).run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.failures), 1)

    def test_retention_integrity_guard_discriminates_matching_forged_manifests_inner(self):
        before, _ = self.retained('before', 100)
        before['manifest_sha256'] = '6' * 64
        with self.assertRaises(Refused):
            self.retention_check(before=before)


if __name__ == '__main__':
    unittest.main()

"""Behavioral adapter tests over synthesized files and injected transports only."""
import copy
import os
from pathlib import Path
import tempfile
import unittest
import shutil
import traceback
from unittest.mock import patch
from dataclasses import replace
from urllib.parse import parse_qs, urlsplit, urlencode

import candidate
import controller_inputs as inputs
import operational
import controller_adapters as adapters
from prepare import Refused, browser_contract, canonical, sha
from session_controller import SessionIdentity, SCENARIOS, bind_scenarios
from api_policy import Refused as PolicyRefused
from namespace import Refused as NamespaceRefused


class Clock:
    def __init__(self, now=100):
        self.now = now

    def __call__(self):
        return self.now


def contract():
    value = {'identity': {'source_sha': 'a' * 40}, 'execute_authorized': False,
             'budget': dict(operational.BUDGET),
             'roles': {role: dict(admissible=False, image_id=None, image_config=None,
                                 recipe=None, profile=None) for role in operational.ROLES},
             'browser': {'expires_at': 10000, 'hostname': browser_contract()['url'].removeprefix('https://')},
             'source_references': {}}
    for name in ('controller_inputs.py', 'controller_adapters.py'):
        value['source_references']['scripts/codex-qualification/' + name] = {
            'sha256': sha((Path(__file__).parent / name).read_bytes())}
    value['pairing_sha256'] = sha(canonical(value['identity']))
    return seal(value)


def seal(value):
    value['operational_sha256'] = sha(canonical({k: v for k, v in value.items()
                                               if k != 'operational_sha256'}))
    return value


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.contract = contract()

    def pending(self, result):
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertIs(result[field], False, field)
        self.assertEqual(result['issuer_verification'], 'pending')
        self.assertEqual(result['independent_review'], 'pending')
        self.assertEqual(result['runtime_evidence'], 'pending-injected-observations-only')


class BuilderTests(AdapterTests):
    def setUp(self):
        super().setUp()
        self.temp = tempfile.TemporaryDirectory(prefix='codex9051-adapter-builder-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'runtime').mkdir()
        (self.root / 'runtime/source.txt').write_bytes(b'synthetic source')
        (self.root / 'runtime/source.txt').chmod(0o644)
        rows = [{'path': 'runtime/source.txt', 'mode': '100644', 'sha256': sha(b'synthetic source'),
                 'bytes': len(b'synthetic source')}]
        recipe = {'execute_authorized': False, 'argv': ['/synthetic/docker', 'build', str(self.root)],
                  'replace_environment': True, 'environment': {'HOME': '/synthetic', 'PATH': '/synthetic'},
                  'credential_forwarding': False, 'working_directory': str(self.root)}
        self.contract['identity']['controlled_dockerfile_sha256'] = 'b' * 64
        self.contract['pairing_sha256'] = sha(canonical(self.contract['identity']))
        self.spec = {'identity': copy.deepcopy(self.contract['identity']),
                     'pairing_sha256': self.contract['pairing_sha256'], 'export_manifest': rows,
                     'export_manifest_sha256': sha(canonical(rows)), 'build_recipe': recipe,
                     'build_recipe_sha256': sha(canonical(recipe))}
        self.contract['builder'] = {
            'export_manifest_sha256': self.spec['export_manifest_sha256'],
            'build_recipe_sha256': self.spec['build_recipe_sha256'],
            'controlled_dockerfile_sha256': 'b' * 64, 'argv_sha256': sha(canonical(recipe['argv'])),
            'environment_sha256': sha(canonical(recipe['environment']))}
        seal(self.contract)
        self.observation = {**self.contract['builder'], 'binary_sha256': 'c' * 64,
                            'daemon_id': 'synthetic-daemon', 'budget': dict(operational.BUDGET),
                            'dependency_routes': {name: 'd' * 64 for name in inputs.ROUTES}}
        (self.root / 'docker-config').mkdir()
        (self.root / 'docker-config/config.json').write_bytes(b'{}\n')
        (self.root / 'docker-config/config.json').chmod(0o600)
        for name, contents in [('build-recipe.json', canonical(recipe) + b'\n'),
                               ('candidate-contract.json', canonical({**candidate.metadata(self.spec),
                                'export_manifest': rows}) + b'\n')]:
            (self.root / name).write_bytes(contents)
            (self.root / name).chmod(0o644)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.addCleanup(os.close, self.fd)
        class Transport:
            def __init__(inner):
                inner.calls = []
                inner.response = {'image_id': 'sha256:' + 'e' * 64, 'exit_code': 0,
                                  'log_sha256': 'f' * 64, 'log_bytes': 25}
                inner.error = False
                inner.late = False

            def build(inner, recipe, *, timeout):
                inner.calls.append((copy.deepcopy(recipe), timeout))
                recipe['argv'].append('transport mutation')
                if inner.error:
                    raise OSError('ambiguous synthetic failure')
                if inner.late:
                    self.clock.now += operational.BUDGET['work_seconds']
                return copy.deepcopy(inner.response)
        self.transport = Transport()

    def adapter(self):
        return adapters.BuilderAdapter(self.contract, self.spec, self.observation,
                                       reviewed=copy.deepcopy(self.observation),
                                       transport=self.transport, clock=self.clock)

    def test_constructor_is_inert_and_exact_recipe_is_defensively_copied(self):
        adapter = self.adapter()
        self.assertEqual(self.transport.calls, [])
        self.spec['build_recipe']['argv'].append('caller mutation')
        result = adapter.build(self.fd)
        self.pending(result)
        self.assertEqual(len(self.transport.calls), 1)
        self.assertNotIn('caller mutation', self.transport.calls[0][0]['argv'])
        with self.assertRaises(Refused):
            adapter.build(self.fd)
        self.assertEqual(len(self.transport.calls), 1)

    def test_bad_export_blocks_transport(self):
        adapter = self.adapter()
        (self.root / 'runtime/source.txt').write_bytes(b'changed source')
        with self.assertRaises(Refused):
            adapter.build(self.fd)
        self.assertEqual(self.transport.calls, [])

    def test_identical_export_in_different_root_cannot_bind_recipe_directory(self):
        with tempfile.TemporaryDirectory(prefix='codex9051-other-export-fixture-') as directory:
            other = Path(directory) / 'export'
            shutil.copytree(self.root, other)
            descriptor = os.open(other, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                with self.assertRaisesRegex(Refused, 'Export descriptor and recipe directory differ'):
                    self.adapter().build(descriptor)
                self.assertEqual(self.transport.calls, [])
            finally:
                os.close(descriptor)

    def test_bad_recipe_and_review_refuse_before_transport(self):
        self.spec['build_recipe']['replace_environment'] = False
        with self.assertRaisesRegex(Refused, 'Exact replaced builder environment'):
            self.adapter()
        self.assertEqual(self.transport.calls, [])

    def test_backward_expired_and_nonfinite_clocks_block_transport(self):
        for instant, reason in ((99, 'Finite monotonic clock'), (2000, 'Adapter deadline expired'),
                                (float('inf'), 'Finite monotonic clock'),
                                (float('nan'), 'Finite monotonic clock'), (True, 'Finite monotonic clock')):
            with self.subTest(instant=instant):
                self.clock.now = 100
                adapter = self.adapter()
                self.clock.now = instant
                with self.assertRaisesRegex(Refused, reason):
                    adapter.build(self.fd)
                self.assertEqual(self.transport.calls, [])

    def test_ambiguous_or_late_outcomes_are_terminal(self):
        for field in ('error', 'late'):
            with self.subTest(field=field):
                self.clock.now = 100
                self.transport.calls.clear()
                setattr(self.transport, field, True)
                adapter = self.adapter()
                with self.assertRaises(Refused):
                    adapter.build(self.fd)
                with self.assertRaises(Refused):
                    adapter.build(self.fd)
                self.assertEqual(len(self.transport.calls), 1)
                setattr(self.transport, field, False)

    def test_failed_malformed_and_overlarge_receipts_never_establish_success(self):
        for field, value in [('exit_code', 1), ('exit_code', False), ('image_id', 'tag'),
                             ('log_sha256', 'unknown'), ('log_bytes', 16 * 1024**2 + 1)]:
            with self.subTest(field=field, value=value):
                self.transport.calls.clear()
                original = copy.deepcopy(self.transport.response)
                self.transport.response[field] = value
                adapter = self.adapter()
                reason = 'SHA-256 digest required' if field == 'log_sha256' else 'Successful bounded immutable-image'
                with self.assertRaisesRegex(Refused, reason):
                    adapter.build(self.fd)
                self.assertEqual(adapter.snapshot()['state'], 'failed')
                self.pending(adapter.snapshot())
                self.transport.response = original

    def test_resealed_stale_adapter_source_refuses_with_no_transport(self):
        self.contract['source_references']['scripts/codex-qualification/controller_adapters.py']['sha256'] = '0' * 64
        seal(self.contract)
        with self.assertRaisesRegex(Refused, 'Executing adapter component differs from source reference'):
            self.adapter()
        self.assertEqual(self.transport.calls, [])

    def test_transport_refusal_content_is_absent_from_error_snapshot_and_chain(self):
        sentinel = 'SYNTHETIC_RAW_TRANSPORT_CONTENT'
        for exception_type in (Refused, PolicyRefused, NamespaceRefused):
            with self.subTest(exception_type=exception_type):
                adapter = self.adapter()
                def refused_build(recipe, *, timeout):
                    raise exception_type(sentinel)
                self.transport.build = refused_build
                try:
                    adapter.build(self.fd)
                except Refused as error:
                    self.assertNotIn(sentinel, str(error))
                    self.assertNotIn(sentinel, repr(adapter.snapshot()))
                    self.assertNotIn(sentinel, ''.join(traceback.format_exception(error)))
                else:
                    self.fail('Transport failure was accepted')

    def test_injected_clock_content_is_absent_from_constructor_error(self):
        sentinel = 'SYNTHETIC_RAW_CLOCK_CONTENT'
        def refused_clock():
            raise Refused(sentinel)
        try:
            adapters.BuilderAdapter(self.contract, self.spec, self.observation,
                reviewed=self.observation, transport=self.transport, clock=refused_clock)
        except Refused as error:
            self.assertNotIn(sentinel, str(error))
            self.assertNotIn(sentinel, ''.join(traceback.format_exception(error)))
        else:
            self.fail('Clock failure was accepted')


class NamespaceTests(AdapterTests):
    def setUp(self):
        super().setUp()
        self.image = 'sha256:' + 'd' * 64
        self.network_id = 'e' * 64
        self.profiles = {}
        config = {'Entrypoint': ['synthetic-entry'], 'Cmd': ['synthetic-server'], 'Env': [],
                  'User': '1001', 'WorkingDir': '/app', 'Healthcheck': None,
                  'ExposedPorts': {}, 'Volumes': {}, 'OnBuild': None}
        for role in operational.ROLES:
            for name in inputs.role_names('fixture', role):
                self.profiles[name] = {'role': role, 'image': self.image,
                    'image_config': copy.deepcopy(config),
                    'create': {key: copy.deepcopy(config[key]) for key in inputs.FIELDS},
                    'host': {key: {} if key in ('PortBindings', 'Sysctls') else []
                             for key in inputs.HOST_FIELDS}, 'aliases': [], 'exec': []}
                self.profiles[name]['create']['Healthcheck'] = {'Test': ['NONE']}
        self.profiles['supabase_db_fixture']['host']['Binds'] = ['supabase_db_fixture:/var/lib/postgresql/data:rw']
        self.profiles['supabase_storage_fixture']['host']['Binds'] = ['supabase_storage_fixture:/var/lib/storage:rw']
        for role in ('tls', 'resolver'):
            self.profiles['codex9051-' + role + '-fixture']['host']['Sysctls'] = {
                'net.ipv4.ip_unprivileged_port_start': '0'}
        for name, profile in self.profiles.items():
            if profile['role'] in ('renderer', 'browser'):
                profile['host'].update(Binds=['/tmp/synthetic-adapter/tls:/qualification/tls:ro'],
                                       Dns=['172.28.5.17'], DnsSearch=['.'], DnsOptions=['ndots:0'])
        modeled_profiles = copy.deepcopy(self.profiles)
        labels = {'com.supabase.cli.project': 'fixture', 'soleur.recovery.attempt': 'fixture'}
        def expected_create(name):
            profile = modeled_profiles[name]
            role = profile['role']
            memory = 1024**3 if role == 'db' else 2 * 1024**3 if role == 'renderer' else 512 * 1024**2
            host = {**copy.deepcopy(profile['host']), 'ExtraHosts': [],
                    'LogConfig': {'Type': 'json-file', 'Config': {'max-size': '10m', 'max-file': '1'}},
                    'NetworkMode': self.network_id, 'Memory': memory, 'MemorySwap': memory,
                    'CpuPeriod': 100000, 'CpuQuota': 200000 if role == 'renderer' else 100000,
                    'PidsLimit': 256, 'RestartPolicy': {'Name': 'no'}, 'SecurityOpt': ['no-new-privileges:true']}
            return {'Image': self.image, 'Labels': labels, **copy.deepcopy(profile['create']),
                    'HostConfig': host, 'NetworkingConfig': {'EndpointsConfig': {self.network_id: {'Aliases': []}}}}
        self.expected_create = expected_create
        class Transport:
            def __init__(inner):
                inner.calls = []
                inner.volumes = {}
                inner.containers = {}
                inner.network = {'Id': self.network_id, 'Name': 'fixture-internal', 'Driver': 'bridge',
                    'Internal': True, 'EnableIPv6': False, 'Labels': {'soleur.recovery.attempt': 'fixture'},
                    'IPAM': {'Config': [{'Subnet': '172.28.5.0/24'}]}, 'Containers': {}}
                inner.changed_image = False
                inner.foreign = False
                inner.duplicate = False
                inner.ambiguous = False
                inner.image_reads = 0

            def request(inner, method, path, payload, *, timeout):
                import json
                inner.calls.append((method, path, payload, timeout))
                route = urlsplit(path).path
                data = json.loads(payload) if payload else {}
                if route.startswith('/images/'):
                    self.assertEqual((method, path, payload), ('GET', '/images/' + self.image + '/json', b''))
                    inner.image_reads += 1
                    observed = copy.deepcopy(config)
                    if inner.changed_image and inner.image_reads > 1:
                        observed['User'] = 'root'
                    return 200, {'Id': self.image, 'Config': observed}
                if route == '/networks/create':
                    self.assertEqual((method, path), ('POST', '/networks/create'))
                    self.assertEqual(data, {'Name': 'fixture-internal', 'Labels': labels, 'Driver': 'bridge',
                        'Internal': True, 'EnableIPv6': False, 'CheckDuplicate': True,
                        'Options': {'com.docker.network.bridge.host_binding_ipv4': '127.0.0.1'}})
                    return 201, {'Id': self.network_id, 'Warning': ''}
                if route.startswith('/networks/') and method == 'GET':
                    self.assertEqual((path, payload), ('/networks/' + self.network_id, b''))
                    return 200, copy.deepcopy(inner.network)
                if route == '/volumes':
                    query = urlencode({'filters': json.dumps({'label': ['soleur.recovery.attempt=fixture']})})
                    self.assertEqual((method, path, payload), ('GET', '/volumes?' + query, b''))
                    return 200, {'Volumes': copy.deepcopy(list(inner.volumes.values())), 'Warnings': None}
                if route == '/volumes/create':
                    self.assertEqual((method, path), ('POST', '/volumes/create'))
                    self.assertIn(data.get('Name'), ('supabase_db_fixture', 'supabase_storage_fixture'))
                    self.assertEqual(data, {'Name': data['Name'], 'Labels': labels, 'Driver': 'local'})
                    receipt = {'Name': data['Name'], 'Driver': 'local', 'Scope': 'local', 'Options': None,
                        'Labels': data['Labels'], 'CreatedAt': 'synthetic-birth', 'Mountpoint': '/synthetic/' + data['Name']}
                    inner.volumes[data['Name']] = copy.deepcopy(receipt)
                    return 201, receipt
                if route == '/containers/create':
                    if inner.ambiguous:
                        raise OSError('synthetic ambiguous create')
                    name = parse_qs(urlsplit(path).query)['name'][0]
                    self.assertEqual((method, path), ('POST', '/containers/create?name=' + name))
                    self.assertEqual(data, expected_create(name))
                    identifier = next(iter(inner.containers)) if inner.duplicate else format(len(inner.containers) + 1, '064x')
                    ip = '172.28.5.' + str(10 + len(inner.containers))
                    inner.containers[identifier] = {'Id': identifier, 'Name': '/' + name,
                        'Image': self.image, 'Config': {key: copy.deepcopy(data[key])
                                                       for key in inputs.FIELDS | {'Labels'}},
                        'HostConfig': copy.deepcopy(data['HostConfig']),
                        'State': {'Running': False}, 'NetworkSettings': {'Networks': {'fixture-internal':
                            {'NetworkID': self.network_id, 'IPAddress': ip}}}}
                    inner.network['Containers'][identifier] = {'IPv4Address': ip + '/24'}
                    return 201, {'Id': identifier, 'Warnings': None}
                if route.startswith('/containers/'):
                    identifier = route.split('/')[2]
                    if method == 'GET':
                        self.assertEqual((path, payload), ('/containers/' + identifier + '/json', b''))
                        receipt = copy.deepcopy(inner.containers[identifier])
                        if inner.foreign:
                            receipt['Config']['Labels']['soleur.recovery.attempt'] = 'foreign'
                        return 200, receipt
                    if route.endswith('/start'):
                        self.assertEqual((method, path, payload), ('POST', '/containers/' + identifier + '/start', b''))
                        inner.containers[identifier]['State']['Running'] = True
                        return 204, {}
                if method == 'DELETE':
                    self.assertEqual(payload, b'')
                    if route.startswith('/containers/'):
                        identifier = route.split('/')[2]
                        self.assertEqual(path, '/containers/' + identifier + '?force=true')
                        inner.containers.pop(identifier)
                        inner.network['Containers'].pop(identifier)
                    elif route.startswith('/volumes/'):
                        name = route.removeprefix('/volumes/')
                        self.assertEqual(path, '/volumes/' + name)
                        inner.volumes.pop(name)
                    else:
                        self.assertEqual(path, '/networks/' + self.network_id)
                    return 204, {}
                raise RuntimeError('Unexpected synthetic request: ' + method + ' ' + path)
        self.transport = Transport()
        self.images = {self.image: self.image}
        self.adapter = adapters.NamespaceAdapter(self.contract, 'fixture', 'fixture-internal',
            '/tmp/synthetic-adapter', self.images, self.profiles,
            reviewed_profiles=copy.deepcopy(self.profiles), transport=self.transport, clock=self.clock)

    def resources(self):
        self.adapter.create_network()
        for name in ('supabase_db_fixture', 'supabase_storage_fixture'):
            self.adapter.create_volume(name)

    def role(self, role):
        name = inputs.role_names('fixture', role)[0]
        self.adapter.create_role(name)
        self.adapter.start_role(name)

    def test_positive_ordering_and_rewritten_network_restrictions(self):
        self.assertEqual(self.transport.calls, [])
        self.resources()
        for role in ('db', 'auth', 'inbucket', 'rest', 'storage', 'kong', 'tls', 'resolver', 'renderer', 'browser'):
            self.role(role)
        result = self.adapter.namespace()
        self.pending(result)
        import json
        body = json.loads(next(call[2] for call in self.transport.calls if call[1] == '/networks/create'))
        self.assertTrue(body['Internal'])
        self.assertEqual(body['Options'], {'com.docker.network.bridge.host_binding_ipv4': '127.0.0.1'})
        create = json.loads(next(call[2] for call in self.transport.calls if call[1].startswith('/containers/create')))
        self.assertEqual(create['HostConfig']['NetworkMode'], self.network_id)
        self.assertEqual(create['HostConfig']['SecurityOpt'], ['no-new-privileges:true'])
        self.assertEqual(create['HostConfig']['ExtraHosts'], [])
        self.assertTrue(any(call[1] == '/networks/' + self.network_id for call in self.transport.calls))
        creates = [call for call in self.transport.calls if call[1].startswith('/containers/create')]
        self.assertEqual(len(creates), 10)
        for call in creates:
            name = parse_qs(urlsplit(call[1]).query)['name'][0]
            self.assertEqual((call[0], call[1]), ('POST', '/containers/create?name=' + name))
            self.assertEqual(json.loads(call[2]), self.expected_create(name))

    def test_migration_role_rewrite_has_complete_independent_expectation(self):
        self.resources()
        self.role('db')
        self.role('migration')
        import json
        request = next(call for call in self.transport.calls if 'name=codex9051-job-' in call[1])
        self.assertEqual(json.loads(request[2]), self.expected_create('codex9051-job-fixture-1'))

    def test_premature_role_refuses_before_transport(self):
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_kong_fixture')
        self.assertEqual(self.transport.calls, [])

    def test_stopped_prerequisite_cannot_release_kong_creation(self):
        self.resources()
        for role in ('db', 'auth', 'inbucket', 'rest', 'storage'):
            self.role(role)
        self.transport.containers[next(iter(self.transport.containers))]['State']['Running'] = False
        count = sum(call[1].startswith('/containers/create') for call in self.transport.calls)
        with self.assertRaisesRegex(Refused, 'Started prerequisite no longer running'):
            self.adapter.create_role('supabase_kong_fixture')
        self.assertEqual(sum(call[1].startswith('/containers/create') for call in self.transport.calls), count)

    def test_stopped_dependency_before_start_never_dispatches_start(self):
        self.resources()
        for role in ('db', 'auth', 'inbucket', 'rest', 'storage'):
            self.role(role)
        self.adapter.create_role('supabase_kong_fixture')
        self.transport.containers[next(iter(self.transport.containers))]['State']['Running'] = False
        starts = sum(call[1].endswith('/start') for call in self.transport.calls)
        with self.assertRaisesRegex(Refused, 'Started prerequisite no longer running'):
            self.adapter.start_role('supabase_kong_fixture')
        self.assertEqual(sum(call[1].endswith('/start') for call in self.transport.calls), starts)

    def test_namespace_collection_requires_current_running_roles(self):
        self.resources()
        for role in ('db', 'auth', 'inbucket', 'rest', 'storage', 'kong', 'tls', 'resolver'):
            self.role(role)
        for container in self.transport.containers.values():
            if container['Name'] == '/supabase_kong_fixture':
                container['State']['Running'] = False
        with self.assertRaisesRegex(Refused, 'Collected namespace role no longer running'):
            self.adapter.namespace()

    def test_ambiguous_child_delete_blocks_every_dependent_parent_delete(self):
        self.resources()
        for role in ('db', 'auth', 'inbucket', 'rest', 'storage', 'kong', 'tls', 'resolver', 'renderer'):
            self.role(role)
        original = self.transport.request
        deletes = []
        def ambiguous_delete(method, path, payload, *, timeout):
            if method == 'DELETE':
                deletes.append(path)
                raise OSError('synthetic ambiguous child delete')
            return original(method, path, payload, timeout=timeout)
        self.transport.request = ambiguous_delete
        self.adapter.cleanup()
        self.adapter.cleanup()
        self.assertEqual(len(deletes), 1)
        self.assertTrue(deletes[0].startswith('/containers/'))

    def test_wrong_start_status_refuses_progress_even_when_fake_running(self):
        self.resources()
        self.adapter.create_role('supabase_db_fixture')
        original = self.transport.request
        def wrong_status(method, path, payload, *, timeout):
            response = original(method, path, payload, timeout=timeout)
            return (201, {}) if path.endswith('/start') else response
        self.transport.request = wrong_status
        with self.assertRaisesRegex(Refused, 'Exact successful start completion'):
            self.adapter.start_role('supabase_db_fixture')

    def test_wrong_delete_status_does_not_release_parent_cleanup(self):
        self.resources()
        self.role('db')
        original = self.transport.request
        deletes = []
        def wrong_status(method, path, payload, *, timeout):
            response = original(method, path, payload, timeout=timeout)
            if method == 'DELETE':
                deletes.append(path)
                return 201, {}
            return response
        self.transport.request = wrong_status
        result = self.adapter.cleanup()
        self.assertEqual(result['state'], 'failed')
        self.assertEqual(len(deletes), 1)

    def test_caller_profile_image_and_returned_observation_mutation_are_isolated(self):
        self.profiles['supabase_db_fixture']['create']['Env'].append('OPENAI_API_KEY=synthetic-unreviewed')
        self.images[self.image] = 'sha256:' + 'f' * 64
        original = self.transport.request
        observed_images = []
        def changing_previous_observation(method, path, payload, *, timeout):
            if path.startswith('/images/') and observed_images:
                observed_images[-1]['Config']['User'] = 'root'
            result = original(method, path, payload, timeout=timeout)
            if path.startswith('/images/'):
                observed_images.append(result[1])
            return result
        self.transport.request = changing_previous_observation
        self.resources()
        self.role('db')
        self.assertEqual(observed_images[0]['Config']['User'], 'root')
        import json
        request = next(call for call in self.transport.calls if call[1].startswith('/containers/create'))
        self.assertEqual(json.loads(request[2])['Env'], [])
        self.assertEqual(json.loads(request[2])['Image'], self.image)

    def test_foreign_network_member_refuses_before_volume_creation(self):
        self.adapter.create_network()
        self.transport.network['Containers']['f' * 64] = {'IPv4Address': '172.28.5.99/24'}
        with self.assertRaises(Refused):
            self.adapter.create_volume('supabase_db_fixture')
        self.assertFalse(any(call[1] == '/volumes/create' for call in self.transport.calls))

    def test_changed_config_refuses_before_create(self):
        self.resources()
        self.transport.changed_image = True
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_db_fixture')
        self.assertFalse(any(call[1].startswith('/containers/create') for call in self.transport.calls))

    def test_duplicate_identity_and_ambiguous_creation_are_terminal(self):
        self.resources()
        self.role('db')
        self.transport.duplicate = True
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_auth_fixture')
        count = len(self.transport.calls)
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_auth_fixture')
        self.assertEqual(len(self.transport.calls), count)

    def test_ambiguous_creation_is_never_retried_or_adopted_for_cleanup(self):
        self.resources()
        self.transport.ambiguous = True
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_db_fixture')
        count = sum(call[1].startswith('/containers/create') for call in self.transport.calls)
        with self.assertRaises(Refused):
            self.adapter.create_role('supabase_db_fixture')
        self.adapter.cleanup()
        self.assertEqual(sum(call[1].startswith('/containers/create') for call in self.transport.calls), count)
        self.assertFalse(any(call[0] == 'DELETE' and call[1].startswith('/containers/')
                             for call in self.transport.calls))

    def test_foreign_reobservation_blocks_start_and_cleanup_delete(self):
        self.resources()
        self.adapter.create_role('supabase_db_fixture')
        self.transport.foreign = True
        with self.assertRaises(Refused):
            self.adapter.start_role('supabase_db_fixture')
        self.adapter.cleanup()
        self.assertFalse(any(call[0] == 'DELETE' and call[1].startswith('/containers/')
                             for call in self.transport.calls))
        self.pending(self.adapter.snapshot())

    def test_cleanup_failure_is_visible_and_cleanup_expiry_has_no_calls(self):
        self.resources()
        self.role('db')
        original = self.transport.request
        def fail_delete(method, path, payload, *, timeout):
            if method == 'DELETE':
                raise OSError('synthetic deletion failure')
            return original(method, path, payload, timeout=timeout)
        self.transport.request = fail_delete
        result = self.adapter.cleanup()
        self.assertEqual(result['state'], 'failed')
        self.assertIsNotNone(result['primary_failure'])
        self.clock.now += 300
        count = len(self.transport.calls)
        self.adapter.cleanup()
        self.assertEqual(len(self.transport.calls), count)

    def test_ambiguous_delete_is_not_retried_on_repeated_cleanup(self):
        self.resources()
        self.role('db')
        original = self.transport.request
        deletes = []
        def ambiguous_delete(method, path, payload, *, timeout):
            if method == 'DELETE':
                deletes.append(path)
                raise OSError('synthetic ambiguous delete')
            return original(method, path, payload, timeout=timeout)
        self.transport.request = ambiguous_delete
        self.adapter.cleanup()
        self.adapter.cleanup()
        self.assertEqual(len(deletes), 1)


class SessionTests(AdapterTests):
    def setUp(self):
        super().setUp()
        self.bodies = {name: ('SELECT 1; -- synthetic ' + name).encode() for name in SCENARIOS}
        self.hashes = {name: sha(body) for name, body in self.bodies.items()}
        self.contract['session_prerequisites'] = {'scenario_sha256': self.hashes}
        seal(self.contract)
        self.binding = bind_scenarios('a' * 40, self.bodies, 'a' * 40, self.hashes)
        self.holder = SessionIdentity('fixture', 'fixture-db', 101, 'birth-h', 201, 'process-h', 'handle-h')
        self.waiter = SessionIdentity('fixture', 'fixture-db', 102, 'birth-w', 202, 'process-w', 'handle-w')
        class Transport:
            def __init__(inner):
                inner.calls = []
                inner.reused = False
                inner.blocked = True
                inner.cleanup_error = False
                inner.commit_error = False

            def identity(inner, handle, *, timeout):
                inner.calls.append(('identity', handle, timeout))
                return replace(handle, backend_birth='reused') if inner.reused else handle

            def start(inner, handle, sql, *, timeout):
                inner.calls.append(('start', handle, sql, timeout))
                return {'identity': handle, 'scenario_sha256': sha(sql), 'exit_code': 0}

            def observe(inner, holder, waiter, sql, *, timeout):
                inner.calls.append(('observe', holder, waiter, sql, timeout))
                return {'holder': holder, 'waiter': waiter, 'blockers': (holder,) if inner.blocked else (),
                        'holder_state': 'idle in transaction', 'waiter_event_type': 'Lock',
                        'observer_exit_code': 0 if inner.blocked else 1, 'scenario_sha256': sha(sql)}

            def commit(inner, handle, *, timeout):
                inner.calls.append(('commit', handle, timeout))
                return {'identity': handle, 'command_tag': 'COMMIT', 'exit_code': 1 if inner.commit_error else 0}

            def wait(inner, handle, *, timeout):
                inner.calls.append(('wait', handle, timeout))
                return {'identity': handle, 'exit_code': 0}

            def assertion(inner, sql, *, timeout):
                inner.calls.append(('assertion', sql, timeout))
                return {'scenario_sha256': sha(sql), 'exit_code': 0}

            def rollback(inner, handle, *, timeout):
                inner.calls.append(('rollback', handle, timeout))
                if inner.cleanup_error:
                    raise OSError('synthetic cleanup error')
                return {'identity': handle, 'exit_code': 0}

            def close(inner, handle, *, timeout):
                inner.calls.append(('close', handle, timeout))
                return {'identity': handle, 'exit_code': 0}
        self.transport = Transport()
        self.adapter = adapters.SessionAdapter(self.contract, 'fixture', 'fixture-db', self.binding,
                        {'holder': self.holder, 'waiter': self.waiter},
                        transport=self.transport, clock=self.clock)

    def test_positive_sequencing_exact_sql_and_one_commit(self):
        self.assertEqual(self.transport.calls, [])
        self.adapter.begin()
        self.assertTrue(self.adapter.observe())
        result = self.adapter.complete()
        self.pending(result)
        self.assertEqual([call[0] for call in self.transport.calls if call[0] != 'identity'],
                         ['start', 'start', 'observe', 'commit', 'wait', 'assertion'])
        self.assertEqual([call[2] for call in self.transport.calls if call[0] == 'start'],
                         [self.bodies[SCENARIOS[0]], self.bodies[SCENARIOS[1]]])
        with self.assertRaises(Refused):
            self.adapter.complete()
        self.assertEqual(sum(call[0] == 'commit' for call in self.transport.calls), 1)

    def test_each_session_transport_timeout_is_within_race_bound(self):
        self.adapter.begin()
        self.adapter.observe()
        self.adapter.complete()
        self.assertTrue(self.transport.calls)
        self.assertTrue(all(0 < call[-1] <= 30 for call in self.transport.calls))

    def test_premature_commit_and_foreign_source_call_no_transport(self):
        with self.assertRaises(Refused):
            self.adapter.complete()
        self.assertEqual(self.transport.calls, [])
        foreign = bind_scenarios('b' * 40, self.bodies, 'b' * 40, self.hashes)
        with self.assertRaises(Refused):
            adapters.SessionAdapter(self.contract, 'fixture', 'fixture-db', foreign,
                {'holder': self.holder, 'waiter': self.waiter}, transport=self.transport, clock=self.clock)

    def test_reused_backend_birth_prevents_handle_command(self):
        self.transport.reused = True
        with self.assertRaises(Refused):
            self.adapter.begin()
        self.assertEqual([call[0] for call in self.transport.calls], ['identity'])

    def test_both_complete_session_identities_are_validated_before_any_transport(self):
        for field, value in [('backend_birth', ''), ('process_birth', ''), ('session_id', ''),
                             ('backend_pid', 0), ('process_pid', True), ('backend_birth', '\u2028')]:
            with self.subTest(field=field, value=value), self.assertRaises(Refused):
                adapters.SessionAdapter(self.contract, 'fixture', 'fixture-db', self.binding,
                    {'holder': self.holder, 'waiter': replace(self.waiter, **{field: value})},
                    transport=self.transport, clock=self.clock)
            self.assertEqual(self.transport.calls, [])

    def test_pending_observations_never_commit_and_are_bounded(self):
        self.adapter.begin()
        self.transport.blocked = False
        for _ in range(254):
            self.assertFalse(self.adapter.observe())
        with self.assertRaises(Refused):
            self.adapter.observe()
        self.assertFalse(any(call[0] == 'commit' for call in self.transport.calls))

    def test_commit_failure_cleanup_preserves_error_and_closes_owned_handles(self):
        self.adapter.begin()
        self.adapter.observe()
        self.transport.commit_error = True
        with self.assertRaises(Refused):
            self.adapter.complete()
        error = self.adapter.snapshot()['primary_failure']
        self.transport.cleanup_error = True
        result = self.adapter.cleanup()
        self.assertEqual(result['primary_failure'], error)
        self.assertEqual([call[1] for call in self.transport.calls if call[0] == 'close'],
                         [self.holder, self.waiter])
        self.pending(result)

    def test_expired_cleanup_makes_no_transport_calls(self):
        self.adapter.begin()
        self.transport.reused = True
        with self.assertRaises(Refused):
            self.adapter.observe()
        count = len(self.transport.calls)
        self.clock.now += 300
        self.adapter.cleanup()
        self.assertEqual(len(self.transport.calls), count)

    def test_bad_waiter_receipt_prevents_assertion(self):
        self.adapter.begin()
        self.adapter.observe()
        def foreign_wait(handle, *, timeout):
            return {'identity': replace(handle, process_birth='reused'), 'exit_code': 0}
        self.transport.wait = foreign_wait
        with self.assertRaises(Refused):
            self.adapter.complete()
        self.assertFalse(any(call[0] == 'assertion' for call in self.transport.calls))

    def test_caller_handle_map_and_callback_identity_mutation_are_isolated(self):
        handles = {'holder': self.holder, 'waiter': self.waiter}
        self.adapter = adapters.SessionAdapter(self.contract, 'fixture', 'fixture-db', self.binding,
            handles, transport=self.transport, clock=self.clock)
        handles['waiter'] = replace(self.waiter, backend_birth='caller mutation')
        original = self.transport.start
        def changing_argument(handle, sql, *, timeout):
            receipt = copy.deepcopy(original(handle, sql, timeout=timeout))
            object.__setattr__(handle, 'process_birth', 'callback mutation')
            return receipt
        self.transport.start = changing_argument
        self.adapter.begin()
        self.adapter.observe()
        self.pending(self.adapter.complete())
        self.assertEqual(self.holder.process_birth, 'process-h')
        self.assertEqual(self.waiter.process_birth, 'process-w')

    def test_ambiguous_close_is_not_retried_on_repeated_cleanup(self):
        self.adapter.begin()
        closes = []
        def ambiguous_close(handle, *, timeout):
            closes.append(handle)
            raise OSError('synthetic ambiguous close')
        self.transport.close = ambiguous_close
        self.adapter.cleanup()
        self.adapter.cleanup()
        self.assertEqual(closes, [self.holder, self.waiter])


class RetainedTests(AdapterTests):
    def setUp(self):
        super().setUp()
        self.wall = Clock(1000)
        self.temp = tempfile.TemporaryDirectory(prefix='codex9051-adapter-retained-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'object').write_bytes(b'synthetic bytes')
        info = self.root.stat()
        self.resource = {'attempt': 'fixture', 'source_sha': 'a' * 40,
                         'pairing_sha256': self.contract['pairing_sha256'], 'resource_kind': 'storage',
                         'resource_id': 'b' * 64, 'root_device': info.st_dev, 'root_inode': info.st_ino}
        self.writers = [{'container_id': 'c' * 64, 'process_pid': 123, 'process_birth': 'writer-birth'}]
        observed_writers = copy.deepcopy(self.writers)
        class Transport:
            def __init__(inner):
                inner.calls = []
                inner.phase = 0
                inner.changed = False
                inner.foreign_fd = False
                inner.outside = False
                inner.descriptors = []

            def resource(inner, reference, *, timeout):
                inner.calls.append('resource')
                writers = copy.deepcopy(observed_writers)
                if inner.changed and inner.calls.count('resource') > 1:
                    writers[0]['process_birth'] = 'changed'
                return {'resource': copy.deepcopy(reference), 'owner_id': 'owner',
                        'database_id': 'database', 'writers': writers}

            def quiesce(inner, reference, writers, phase, *, timeout):
                inner.calls.append('quiesce')
                inner.phase += 1
                self.wall.now += 10
                inner.binding = {**reference, 'quiescence_id': str(inner.phase) * 64}
                inner.start = self.wall.now
                return {'binding': inner.binding, 'writers': copy.deepcopy(writers),
                        'quiescent_writers': copy.deepcopy(writers), 'quiescence_start': inner.start}

            def open_root(inner, reference, *, timeout):
                inner.calls.append('open_root')
                fd = os.open(self.root / 'object' if inner.foreign_fd else self.root,
                             os.O_RDONLY | os.O_NOFOLLOW)
                inner.descriptors.append(fd)
                return fd

            def finish_collection(inner, reference, writers, phase, start, end, *, timeout):
                inner.calls.append('finish_collection')
                self.wall.now += 1
                return {'binding': copy.deepcopy(inner.binding), 'phase': phase,
                        'owner_id': 'owner', 'database_id': 'database', 'writers': copy.deepcopy(writers),
                        'quiescent_writers': copy.deepcopy(writers), 'observer_id': 'synthetic-observer',
                        'artifact_sha256': 'e' * 64, 'quiescence_start': inner.start,
                        'collection_start': start + 1 if inner.outside else start,
                        'collection_end': end, 'quiescence_end': self.wall.now,
                        'observed_at': self.wall.now, 'expires_at': self.wall.now + 100}

            def release(inner, reference, writers, quiescence_id, *, timeout):
                inner.calls.append('release')
                return None
        self.transport = Transport()
        self.adapter = adapters.RetainedAdapter(self.contract, 'fixture', 'owner', 'database',
                self.resource, self.writers, transport=self.transport, clock=self.clock,
                observation_clock=self.wall)

    def test_before_after_comparison_hashes_only_and_owned_descriptors_closed(self):
        self.assertEqual(self.transport.calls, [])
        self.adapter.collect('before', ['object'])
        self.adapter.collect('after', ['object'])
        result = self.adapter.compare()
        self.pending(result)
        self.assertNotIn('synthetic bytes', repr(result))
        self.assertEqual(self.transport.calls.count('release'), 2)
        for fd in self.transport.descriptors:
            with self.assertRaises(OSError):
                os.fstat(fd)

    def test_substituted_root_and_writer_change_refuse_and_release(self):
        for field in ('foreign_fd', 'changed'):
            with self.subTest(field=field):
                self.setUp()
                setattr(self.transport, field, True)
                with self.assertRaises((Refused, OSError)):
                    self.adapter.collect('before', ['object'])
                self.assertEqual(self.transport.calls.count('release'), 1)
                for fd in self.transport.descriptors:
                    with self.assertRaises(OSError):
                        os.fstat(fd)

    def test_collection_outside_observed_window_refuses(self):
        self.transport.outside = True
        with self.assertRaises(Refused):
            self.adapter.collect('before', ['object'])
        self.assertEqual(self.transport.calls.count('release'), 1)

    def test_matching_root_quiescence_with_wrong_writer_census_still_releases(self):
        original = self.transport.quiesce
        def wrong_writers(reference, writers, phase, *, timeout):
            result = original(reference, writers, phase, timeout=timeout)
            result['quiescent_writers'][0]['process_birth'] = 'changed'
            return result
        self.transport.quiesce = wrong_writers
        with self.assertRaises(Refused):
            self.adapter.collect('before', ['object'])
        self.assertEqual(self.transport.calls.count('release'), 1)
        self.assertEqual(self.transport.calls.count('open_root'), 0)

    def test_each_collection_has_its_own_bounded_release_window(self):
        self.adapter.collect('before', ['object'])
        self.clock.now += 500
        self.adapter.collect('after', ['object'])
        self.pending(self.adapter.compare())
        self.assertEqual(self.transport.calls.count('release'), 2)

    def test_late_opened_descriptor_closes_and_known_lease_releases(self):
        original = self.transport.open_root
        def late_open(reference, *, timeout):
            descriptor = original(reference, timeout=timeout)
            self.clock.now += operational.BUDGET['work_seconds']
            return descriptor
        self.transport.open_root = late_open
        with self.assertRaises(Refused):
            self.adapter.collect('before', ['object'])
        self.assertEqual(self.transport.calls.count('release'), 1)
        with self.assertRaises(OSError):
            os.fstat(self.transport.descriptors[0])

    def test_open_root_and_observation_clock_refusals_cannot_leak_content(self):
        sentinel = 'SYNTHETIC_RAW_RETAINED_CONTENT'
        for target in ('open_root', 'observation_clock'):
            with self.subTest(target=target):
                self.setUp()
                def refused_callback(*args, **kwargs):
                    raise Refused(sentinel)
                if target == 'open_root':
                    self.transport.open_root = refused_callback
                else:
                    self.adapter._wall = refused_callback
                try:
                    self.adapter.collect('before', ['object'])
                except Refused as error:
                    self.assertNotIn(sentinel, str(error))
                    self.assertNotIn(sentinel, repr(self.adapter.snapshot()))
                    self.assertNotIn(sentinel, ''.join(traceback.format_exception(error)))
                else:
                    self.fail('Retained callback failure was accepted')
                self.assertEqual(self.transport.calls.count('release'), 1)

    def test_changed_retained_bytes_and_scoped_erasure_are_discriminated(self):
        self.adapter.collect('before', ['object'])
        (self.root / 'object').write_bytes(b'changed synthetic bytes')
        self.adapter.collect('after', ['object'])
        with self.assertRaises(Refused):
            self.adapter.compare()

    def test_exact_scoped_erasure_control(self):
        self.adapter.collect('before', ['object'])
        (self.root / 'object').unlink()
        self.adapter.collect('after', [])
        self.pending(self.adapter.compare(erased_paths=('object',)))

    def test_caller_resource_writers_and_callback_arguments_are_isolated(self):
        self.resource['root_inode'] = -1
        self.writers[0]['process_birth'] = 'caller mutation'
        original = self.transport.quiesce
        def changing_arguments(reference, writers, phase, *, timeout):
            receipt = copy.deepcopy(original(reference, writers, phase, timeout=timeout))
            reference['root_inode'] = -2
            writers[0]['process_birth'] = 'callback mutation'
            return receipt
        self.transport.quiesce = changing_arguments
        self.adapter.collect('before', ['object'])
        self.adapter.collect('after', ['object'])
        self.pending(self.adapter.compare())

    def test_nonempty_quiescence_release_response_is_not_success(self):
        original = self.transport.release
        def failed_release(reference, writers, quiescence_id, *, timeout):
            original(reference, writers, quiescence_id, timeout=timeout)
            return {'error': 'synthetic release refusal'}
        self.transport.release = failed_release
        with self.assertRaisesRegex(Refused, 'Owned quiescence release failed'):
            self.adapter.collect('before', ['object'])
        self.assertEqual(self.adapter.snapshot()['state'], 'failed')

    def test_phase_order_refuses_before_transport_and_census_is_complete(self):
        with self.assertRaises(Refused):
            self.adapter.collect('after', ['object'])
        self.assertEqual(self.transport.calls, [])


class GuardDiscriminators(unittest.TestCase):
    def test_identity_guard_removal_causes_intended_assertion_failure(self):
        result = unittest.TestResult()
        with patch.object(adapters.SessionAdapter, '_identity', return_value=None):
            SessionTests('test_reused_backend_birth_prevents_handle_command').run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.errors), 0)
        self.assertEqual(len(result.failures), 1)

    def test_export_guard_removal_causes_intended_assertion_failure(self):
        result = unittest.TestResult()
        with patch.object(candidate, 'verify_exports', return_value=None):
            BuilderTests('test_bad_export_blocks_transport').run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.errors), 0)
        self.assertEqual(len(result.failures), 1)


if __name__ == '__main__':
    unittest.main()

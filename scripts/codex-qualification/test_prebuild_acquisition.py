"""Synthetic prebuild acquisition; no daemon, sockets or account inputs."""
import copy
from argparse import Namespace
import json
import multiprocessing
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.parse import quote

import prebuild_acquisition as acquisition
from prepare import Refused, canonical, sha


ROLES = ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage')
CONFIG = {'Entrypoint': ['/fixture-entry'], 'Cmd': ['fixture-service'], 'Env': [],
          'User': 'fixture', 'WorkingDir': '/fixture', 'Healthcheck': None,
          'ExposedPorts': {}, 'Volumes': {}, 'OnBuild': None}
VERSION = {'Version': '28.0.1', 'ApiVersion': '1.48', 'MinAPIVersion': '1.24',
           'Os': 'linux', 'Arch': 'amd64', 'KernelVersion': 'fixture-kernel',
           'GitCommit': 'fixture-commit', 'GoVersion': 'go1.24', 'BuildTime': 'fixture-time'}
INFO = {'ID': 'fixture-daemon', 'ServerVersion': '28.0.1', 'OSType': 'linux',
        'Architecture': 'x86_64', 'NCPU': 4, 'MemTotal': 1024,
        'SecurityOptions': ['name=fixture-security']}


class Acquisition(unittest.TestCase):
    def setUp(self):
        self.refs = {role: 'registry.invalid/fixture/' + role + '@sha256:' + str(i + 1) * 64
                     for i, role in enumerate(ROLES)}
        self.fingerprint = {'dev': 7, 'ino': 12, 'uid': 1000}
        self.manifest = acquisition.action_manifest(
            source_sha='a' * 40, pairing_sha256='b' * 64, operational_sha256='c' * 64,
            retained_manifest_sha256='d' * 64, endpoint='/fixture/daemon.sock',
            endpoint_fingerprint=self.fingerprint, image_refs=self.refs,
            output_directory='/fixture/output', output_directory_fingerprint=self.fingerprint,
            attempt='fixture-attempt', timeout=60,
            bindings={'repo': '/fixture/repo', 'contract_path': '/fixture/contract.json',
                      'contract_sha256': 'e' * 64, 'image_inputs_path': '/fixture/inputs.json',
                      'image_inputs_sha256': '9' * 64, 'retained_manifest_path': '/fixture/retained.json',
                      'dependency_sha256': {'prebuild_acquisition.py': 'f' * 64},
                      'local_files': {}})
        self.gate = Mock(return_value=None)
        self.now = 100.0
        self.clock = lambda: self.now
        self.probe = Mock(return_value=self.fingerprint)
        self.transport = Mock(endpoint='/fixture/daemon.sock')
        self.responses = {'/version': (200, {**VERSION, 'SecretExtra': 'excluded'}),
                          '/info': (200, {**INFO, 'Name': 'excluded-host', 'DockerRootDir': '/excluded'})}
        for i, ref in enumerate(self.refs.values()):
            self.responses['/images/' + quote(ref, safe='') + '/json'] = (200, {
                'Id': 'sha256:' + 'abcdef'[i] * 64, 'RepoDigests': [ref],
                'Os': 'linux', 'Architecture': 'amd64', 'Config': copy.deepcopy(CONFIG)})
        self.transport.request.side_effect = self.respond

    def respond(self, method, path, payload, *, timeout):
        self.gate.assert_called_once_with()
        self.assertEqual((method, payload), ('GET', b''))
        return copy.deepcopy(self.responses[path])

    def collector(self, manifest=None):
        selected = self.manifest if manifest is None else manifest
        return acquisition.PrebuildAcquisition(selected, self.transport, self.gate,
            manifest_sha256=sha(canonical(self.manifest)), clock=self.clock,
            endpoint_probe=self.probe)

    def test_constructor_has_no_io_and_order_is_exact(self):
        collector = self.collector()
        self.transport.request.assert_not_called()
        self.probe.assert_not_called()
        self.gate.assert_not_called()
        result = collector.collect()
        expected = ['/version', '/info'] + ['/images/' + quote(ref, safe='') + '/json'
                                         for ref in sorted(self.refs.values())]
        self.assertEqual([call.args[1] for call in self.transport.request.call_args_list], expected)
        self.assertEqual(self.probe.call_count, 16)
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['daemon'], {'version': VERSION, 'info': INFO})
        for role, value in result['roles'].items():
            self.assertEqual(value['requested_reference'], self.refs[role])
            self.assertNotEqual(value['image_id'], 'sha256:' + self.refs[role].split(':')[-1])
            self.assertEqual(value['config_sha256'], sha(canonical(CONFIG)))
            self.assertEqual(value['daemon_id'], INFO['ID'])
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertIs(result[field], False)
        self.assertEqual(result['issuer_verification'], 'pending')
        self.assertEqual(result['independent_review'], 'pending')

    def test_duplicate_reference_is_read_once_and_shared_by_roles(self):
        self.refs['auth'] = self.refs['db']
        args = {key: self.manifest[key] for key in acquisition.INPUT_FIELDS}
        args['image_refs'] = self.refs
        self.manifest = acquisition.action_manifest(**args)
        receipt = self.collector().collect()
        self.assertEqual(self.transport.request.call_count, 7)
        self.assertEqual(receipt['roles']['db']['image_id'], receipt['roles']['auth']['image_id'])

    def test_invalid_or_mutated_manifest_never_consumes_gate(self):
        variants = []
        for mutate in (lambda m: m.update(extra=True),
                       lambda m: m.update(source_sha='9' * 40),
                       lambda m: m.update(endpoint='/another.sock'),
                       lambda m: m['actions'][0].update(path='/containers/json'),
                       lambda m: m.update(timeout=61),
                       lambda m: m['image_refs'].update(db='fixture:latest')):
            variant = copy.deepcopy(self.manifest)
            mutate(variant)
            variants.append(variant)
        for variant in variants:
            with self.subTest(variant=variant), self.assertRaises(Refused):
                self.collector(variant)
        self.gate.assert_not_called()
        self.transport.request.assert_not_called()

    def test_gate_failure_has_zero_reads_and_is_not_retryable(self):
        self.gate.side_effect = RuntimeError('sensitive gate exception')
        collector = self.collector()
        with self.assertRaisesRegex(Refused, '^Prebuild acquisition incomplete$'):
            collector.collect()
        with self.assertRaises(Refused):
            collector.collect()
        self.gate.assert_called_once()
        self.transport.request.assert_not_called()

    def test_first_failure_keeps_partial_facts_and_never_retries(self):
        first_image = sorted(path for path in self.responses if path.startswith('/images/'))[0]
        self.responses[first_image] = (404, {'message': 'sensitive absence detail'})
        collector = self.collector()
        with self.assertRaises(acquisition.AcquisitionFailure) as raised:
            collector.collect()
        self.assertEqual(str(raised.exception), 'Prebuild acquisition incomplete')
        self.assertEqual(raised.exception.receipt['daemon']['info'], INFO)
        self.assertEqual(raised.exception.receipt['roles'], {})
        self.assertEqual(self.transport.request.call_count, 3)
        with self.assertRaises(Refused):
            collector.collect()
        self.assertEqual(self.transport.request.call_count, 3)
        self.gate.assert_called_once()

    def test_shrinking_single_deadline_and_ten_second_request_cap(self):
        def delayed(*args, **kwargs):
            response = self.respond(*args, **kwargs)
            self.now += 3
            return response
        args = {key: self.manifest[key] for key in acquisition.INPUT_FIELDS}
        args['timeout'] = 25
        self.manifest = acquisition.action_manifest(**args)
        self.transport.request.side_effect = delayed
        self.collector().collect()
        self.assertEqual([call.kwargs['timeout'] for call in self.transport.request.call_args_list],
                         [10, 10, 10, 10, 10, 10, 7, 4])

    def test_expired_response_stops_before_next_request(self):
        def delayed(*args, **kwargs):
            result = self.respond(*args, **kwargs)
            self.now += 61
            return result
        self.transport.request.side_effect = delayed
        with self.assertRaises(acquisition.AcquisitionFailure):
            self.collector().collect()
        self.transport.request.assert_called_once()

    def test_endpoint_replacement_after_read_stops(self):
        self.probe.side_effect = [self.fingerprint, {**self.fingerprint, 'ino': 13}]
        with self.assertRaises(acquisition.AcquisitionFailure):
            self.collector().collect()
        self.transport.request.assert_called_once()

    def test_malformed_version_and_daemon_fields_are_not_retained(self):
        for path, field, value in (('/version', 'Os', 'windows'), ('/version', 'Arch', 'arm64'),
                                   ('/info', 'ID', ''), ('/info', 'NCPU', True),
                                   ('/info', 'SecurityOptions', ['x' * 1025])):
            saved = copy.deepcopy(self.responses[path])
            self.responses[path][1][field] = value
            self.gate.reset_mock()
            self.transport.request.reset_mock()
            with self.subTest(path=path, field=field), self.assertRaises(acquisition.AcquisitionFailure):
                self.collector().collect()
            self.responses[path] = saved

    def test_image_identity_membership_platform_and_complete_config_required(self):
        path = sorted(path for path in self.responses if path.startswith('/images/'))[0]
        original = self.responses[path]
        for field, value in (('Id', 'fixture-latest'), ('RepoDigests', []),
                             ('Architecture', 'arm64'), ('Os', 'windows'),
                             ('Config', {'Cmd': ['fixture']}),
                             ('Config', {**CONFIG, 'Env': ['X=' + 'x' * 1048576]})):
            self.responses[path] = (200, {**original[1], field: value})
            self.gate.reset_mock()
            self.transport.request.reset_mock()
            with self.subTest(field=field), self.assertRaises(acquisition.AcquisitionFailure):
                self.collector().collect()
            self.assertEqual(self.transport.request.call_count, 3)

    def test_optional_version_fields_are_omitted_and_receipt_has_measurements(self):
        minimal = {key: VERSION[key] for key in ('Version', 'ApiVersion', 'Os', 'Arch')}
        self.responses['/version'] = (200, minimal)
        result = self.collector().collect()
        self.assertEqual(result['daemon']['version'], minimal)
        self.assertEqual(result['request_count'], 8)
        self.assertEqual(result['started_at_monotonic'], 100)
        self.assertEqual(result['finished_at_monotonic'], 100)
        self.assertEqual(result['receipt_sha256'], sha(canonical(
            {key: value for key, value in result.items() if key != 'receipt_sha256'})))
        self.assertEqual(result['roles']['db']['repo_digests'], [self.refs['db']])

    def test_file_only_prepare_and_persistent_replay_after_failure(self):
        from test_controller_adapters import contract, seal
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained = root / 'retained.json'
            retained.write_bytes(canonical({'images': [
                {'source_repository': ref.split('@')[0], 'manifest_digest': ref.split('@')[1],
                 'platform': 'linux/amd64', 'image_id': 'untrusted-registry-config-digest'}
                for ref in self.refs.values()]}))
            inputs_path = root / 'inputs.json'
            inputs_path.write_bytes(canonical({'attempt': 'fixture-only', 'image_refs': self.refs,
                'local_files': {}, 'total_timeout': 30, 'retained_manifest_path': str(retained),
                'retained_manifest_sha256': sha(retained.read_bytes())}))
            current = contract()
            current['identity']['source_sha'] = 'a' * 40
            current['pairing_sha256'] = sha(canonical(current['identity']))
            seal(current)
            contract_path = root / 'contract.json'
            contract_path.write_bytes(canonical(current))
            output = root / 'output'
            args = Namespace(repo=str(root), source_sha='a' * 40, contract=str(contract_path),
                image_inputs=str(inputs_path), endpoint='/fixture/daemon.sock', directory=str(output))
            with patch.object(acquisition, '_source') as source_check, \
                    patch.object(acquisition, '_dependencies', return_value={'prebuild_acquisition.py': 'f' * 64}), \
                    patch.object(acquisition, 'socket_fingerprint', return_value=self.fingerprint), \
                    patch('controller_transports.UnixJsonTransport') as transport_factory:
                with patch.object(acquisition, '_read', wraps=acquisition._read) as reads:
                    digest = acquisition.prepare_action(args)
                for path in (retained, inputs_path, contract_path):
                    self.assertEqual(sum(call.args[0] == str(path) for call in reads.call_args_list), 1)
                transport_factory.assert_not_called()
                marker = output / acquisition.MARKER
                self.assertFalse(marker.exists())
                self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
                manifest_path = output / acquisition.MANIFEST
                self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o600)
                self.assertEqual(digest, sha(canonical(json.loads(manifest_path.read_bytes()))))
                def request(method, path, payload, *, timeout):
                    self.assertTrue(marker.is_file())
                    self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
                    self.assertEqual((method, payload), ('GET', b''))
                    if path == '/version':
                        return 200, VERSION
                    return 404, {'private': 'must not escape'}
                transport_factory.return_value.request.side_effect = request
                execute = Namespace(manifest=str(manifest_path), manifest_sha256=digest,
                    runner_sha256=sha(Path(acquisition.__file__).read_bytes()))
                with self.assertRaisesRegex(Refused, '^Prebuild acquisition incomplete$'):
                    acquisition.execute_action(execute)
                receipt_path = output / acquisition.RECEIPT
                receipt = receipt_path.read_bytes()
                self.assertNotIn(b'must not escape', receipt)
                self.assertEqual(json.loads(receipt)['daemon']['version'], VERSION)
                self.assertEqual(transport_factory.return_value.request.call_count, 2)
                with self.assertRaises(Refused):
                    acquisition.execute_action(execute)
                self.assertEqual(transport_factory.return_value.request.call_count, 2)
                self.assertEqual(receipt_path.read_bytes(), receipt)
                self.assertTrue(marker.exists())
                self.assertEqual(source_check.call_count, 3)
                child_request = root / 'forbidden-child-request'
                def replay_in_fresh_process():
                    def forbidden(*_args, **_kwargs):
                        child_request.write_text('attempted')
                        raise AssertionError('Replay reached transport')
                    transport_factory.return_value.request.side_effect = forbidden
                    with self.assertRaises(Refused):
                        acquisition.execute_action(execute)
                process = multiprocessing.get_context('fork').Process(target=replay_in_fresh_process)
                process.start()
                process.join(timeout=5)
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
                    self.fail('Synthetic replay process did not finish')
                self.assertEqual(process.exitcode, 0)
                self.assertFalse(child_request.exists())
                # A copied manifest at the same path after directory replacement
                # cannot reset the persistent marker's identity binding.
                output.rename(root / 'old-output')
                output.mkdir(mode=0o700)
                (output / acquisition.MANIFEST).write_bytes((root / 'old-output' / acquisition.MANIFEST).read_bytes())
                with self.assertRaises(Refused):
                    acquisition.execute_action(execute)
                self.assertEqual(transport_factory.return_value.request.call_count, 2)
                # A directory replaced while a response is in flight refuses
                # without issuing the next request or writing in the substitute.
                output2 = root / 'output2'
                args.directory = str(output2)
                digest2 = acquisition.prepare_action(args)
                other = root / 'substitute'
                other.mkdir()
                def replace_output(*_args, **_kwargs):
                    output2.rename(root / 'detached-output2')
                    output2.symlink_to(other, target_is_directory=True)
                    return 200, VERSION
                transport_factory.return_value.request.reset_mock()
                transport_factory.return_value.request.side_effect = replace_output
                execute2 = Namespace(manifest=str(output2 / acquisition.MANIFEST),
                    manifest_sha256=digest2, runner_sha256=execute.runner_sha256)
                with self.assertRaises(Refused):
                    acquisition.execute_action(execute2)
                transport_factory.return_value.request.assert_called_once()
                self.assertEqual(list(other.iterdir()), [])

    def test_file_helpers_refuse_symlink_ancestors_and_never_follow_leaf(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real = root / 'real'
            real.mkdir()
            (real / 'fixture.json').write_text('{}')
            (root / 'alias').symlink_to(real, target_is_directory=True)
            (root / 'leaf.json').symlink_to(real / 'fixture.json')
            for path in (root / 'alias' / 'fixture.json', root / 'leaf.json'):
                with self.subTest(path=path), self.assertRaises((OSError, Refused)):
                    acquisition._read(str(path))
            fifo = root / 'fixture.fifo'
            os.mkfifo(fifo)
            with self.assertRaises(Refused):
                acquisition._read(str(fifo))
            for payload in (b'{"number":1e999}', b'{"number":NaN}', b'{"x":1,"x":2}'):
                with self.subTest(payload=payload), self.assertRaises(Refused):
                    acquisition._decode_json(payload)

    def test_source_head_and_dirty_checks_disable_external_fsmonitor(self):
        with patch.object(acquisition, 'git', side_effect=[b'a' * 40 + b'\n', b''] ) as read_git:
            acquisition._source('/fixture/repo', 'a' * 40)
        self.assertTrue(all(call.args[1:3] == ('-c', 'core.fsmonitor=false')
                            for call in read_git.call_args_list))

    def test_manifest_mutation_during_response_stops_before_second_request(self):
        collector = self.collector()
        def mutate(*args, **kwargs):
            response = self.respond(*args, **kwargs)
            collector.manifest['source_sha'] = '8' * 40
            return response
        self.transport.request.side_effect = mutate
        with self.assertRaises(acquisition.AcquisitionFailure):
            collector.collect()
        self.transport.request.assert_called_once()

    def test_daemon_version_contradiction_refuses_before_images(self):
        self.responses['/info'][1]['ServerVersion'] = 'different-daemon-version'
        with self.assertRaises(acquisition.AcquisitionFailure):
            self.collector().collect()
        self.assertEqual(self.transport.request.call_count, 2)


if __name__ == '__main__':
    unittest.main()

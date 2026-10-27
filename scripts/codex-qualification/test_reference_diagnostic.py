"""Synthesized Mailpit lookup diagnostic; no socket or Docker executable."""
import copy
from argparse import Namespace
import json
import multiprocessing
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.parse import quote

import reference_diagnostic as diagnostic
from prepare import Refused, canonical, sha

VERSION = {'Version': 'fixture-version', 'ApiVersion': '1.48', 'Os': 'linux', 'Arch': 'amd64'}
INFO = {'ID': 'fixture-daemon', 'ServerVersion': 'fixture-version', 'OSType': 'linux',
        'Architecture': 'x86_64', 'NCPU': 4, 'MemTotal': 1024, 'SecurityOptions': []}
IMAGE = {'source_repository': 'docker.io/axllent/mailpit', 'manifest_digest': 'sha256:' + '1' * 64,
         'image_id': 'sha256:' + '2' * 64, 'platform': 'linux/amd64'}
CONFIG = {'Cmd': ['fixture-service'], 'Env': []}


class ReferenceDiagnostic(unittest.TestCase):
    def setUp(self):
        self.fingerprint = {'dev': 7, 'ino': 12, 'uid': 1000}
        self.refs = {role: 'registry.invalid/fixture/' + role + '@sha256:' + str(i + 3) * 64
                     for i, role in enumerate(('db', 'kong', 'auth', 'inbucket', 'rest', 'storage'))}
        self.refs['inbucket'] = IMAGE['source_repository'] + '@' + IMAGE['manifest_digest']
        self.context = {'source_sha': 'a' * 40, 'pairing_sha256': 'b' * 64,
            'operational_sha256': 'c' * 64, 'retained_manifest_sha256': 'd' * 64,
            'endpoint': '/fixture/daemon.sock', 'endpoint_fingerprint': self.fingerprint,
            'image_refs': self.refs, 'output_directory': '/fixture/output',
            'output_directory_fingerprint': self.fingerprint, 'attempt': 'fixture-reference', 'timeout': 60,
            'bindings': {'repo': '/fixture/repo', 'contract_path': '/fixture/contract.json',
                'contract_sha256': 'e' * 64, 'image_inputs_path': '/fixture/inputs.json',
                'image_inputs_sha256': 'f' * 64, 'retained_manifest_path': '/fixture/retained.json',
                'dependency_sha256': {'reference_diagnostic.py': '9' * 64}, 'local_files': {}}}
        self.manifest = diagnostic.action_manifest(retained_image=IMAGE, **self.context)
        self.gate = Mock()
        self.probe = Mock(return_value=self.fingerprint)
        self.output = Mock()
        self.now = 10.0
        self.transport = Mock(endpoint=self.context['endpoint'])
        self.responses = {'/version': (200, {**VERSION, 'private-extra': 'not retained'}),
                          '/info': (200, {**INFO, 'Name': 'not retained'})}
        for candidate in self.candidates():
            self.responses['/images/' + quote(candidate, safe='') + '/json'] = (404, {'private': 'not retained'})
        self.transport.request.side_effect = self.respond

    def candidates(self):
        return ['axllent/mailpit@' + IMAGE['manifest_digest'], IMAGE['manifest_digest'], IMAGE['image_id']]

    def respond(self, method, path, payload, *, timeout):
        self.gate.assert_called_once_with()
        self.assertEqual((method, payload), ('GET', b''))
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)
        return copy.deepcopy(self.responses[path])

    def collector(self, manifest=None):
        return diagnostic.ReferenceDiagnostic(self.manifest if manifest is None else manifest,
            self.transport, self.gate, manifest_sha256=sha(canonical(self.manifest)),
            clock=lambda: self.now, endpoint_probe=self.probe, output_binding=self.output)

    def image_response(self, **changes):
        return 200, {'Id': 'sha256:' + 'a' * 64, 'Os': 'linux', 'Architecture': 'amd64',
                     'Config': copy.deepcopy(CONFIG), **changes}

    def test_manifest_derives_only_three_immutable_candidates_and_constructor_has_no_io(self):
        expected = ['/version', '/info'] + ['/images/' + quote(candidate, safe='') + '/json'
                                          for candidate in self.candidates()]
        self.assertEqual([entry['path'] for entry in self.manifest['actions']], expected)
        self.assertEqual(len(set(expected)), 5)
        self.assertTrue(all(entry['method'] == 'GET' for entry in self.manifest['actions']))
        self.collector()
        self.transport.request.assert_not_called()
        self.gate.assert_not_called()
        self.probe.assert_not_called()
        self.output.assert_not_called()
        for key, value in (('source_repository', 'docker.io/other/service'),
                           ('manifest_digest', 'latest'), ('image_id', IMAGE['manifest_digest']),
                           ('platform', 'linux/arm64')):
            with self.subTest(key=key), self.assertRaises(Refused):
                diagnostic.action_manifest(retained_image={**IMAGE, key: value}, **self.context)
        for mutate in (lambda m: m['actions'][2].update(path='/images/json'),
                       lambda m: m['context'].update(source_sha='8' * 40),
                       lambda m: m.update(extra=True)):
            altered = copy.deepcopy(self.manifest)
            mutate(altered)
            with self.assertRaises(Refused):
                self.collector(altered)
        self.gate.assert_not_called()

    def test_expected_candidate_404_advances_all_five_exact_requests_without_absence_claim(self):
        receipt = self.collector().collect()
        self.assertEqual([call.args[1] for call in self.transport.request.call_args_list],
                         [action['path'] for action in self.manifest['actions']])
        self.assertEqual([action['status_code'] for action in receipt['actions']], [200, 200, 404, 404, 404])
        self.assertEqual(receipt['outcome'], 'none-approved-immutable-lookup-forms-resolved')
        self.assertEqual(receipt['status'], 'diagnostic-sequence-completed')
        self.assertEqual(receipt['observations'], {})
        self.assertNotIn('layers', canonical(receipt).decode())
        self.assertNotIn('not retained', canonical(receipt).decode())
        self.assertEqual(receipt['receipt_sha256'], sha(canonical(
            {key: value for key, value in receipt.items() if key != 'receipt_sha256'})))

    def test_success_does_not_short_circuit_or_assume_lookup_digest_is_local_id(self):
        paths = [entry['path'] for entry in self.manifest['actions'][2:]]
        self.responses[paths[0]] = self.image_response()
        self.responses[paths[1]] = self.image_response(RepoDigests=None)
        self.responses[paths[2]] = self.image_response(RepoDigests=[self.refs['inbucket'], self.candidates()[0]])
        receipt = self.collector().collect()
        self.assertEqual(self.transport.request.call_count, 5)
        self.assertEqual(len(receipt['observations']), 3)
        observations = list(receipt['observations'].values())
        self.assertEqual([value['repo_digests_state'] for value in observations], ['absent', 'null', 'present'])
        for observed in observations:
            self.assertEqual(observed['image_id'], 'sha256:' + 'a' * 64)
            self.assertNotEqual(observed['image_id'], IMAGE['image_id'])
            self.assertNotEqual(observed['image_id'], IMAGE['manifest_digest'])
            self.assertEqual(observed['config'], CONFIG)
            self.assertEqual(observed['config_sha256'], sha(canonical(CONFIG)))
            self.assertEqual(observed['reference_membership_verification'], 'pending')
        self.assertEqual(observations[-1]['exact_reference_matches'],
                         [self.refs['inbucket'], self.candidates()[0]])
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertIs(receipt[field], False)

    def test_only_candidate_404_can_advance_and_other_responses_stop_without_sensitive_content(self):
        sensitive = 'synthesized-sensitive-reference-sentinel'
        variants = [('daemon404', 0, (404, {'error': sensitive}), 'http_status'),
                    ('candidate500', 2, (500, {'error': sensitive}), 'http_status'),
                    ('malformed', 2, (200, sensitive), 'receipt_shape'),
                    ('bool-status', 2, (True, {}), 'receipt_shape'),
                    ('overflow-status', 2, (600, {}), 'receipt_shape'),
                    ('string-status', 2, ('200', {}), 'receipt_shape'),
                    ('exception', 2, RuntimeError(sensitive), 'unexpected_failure'),
                    ('wrong-id', 2, self.image_response(Id='latest'), 'immutable_id'),
                    ('wrong-platform', 2, self.image_response(Architecture='arm64'), 'platform'),
                    ('bad-config', 2, self.image_response(Config=[sensitive]), 'config_shape'),
                    ('big-config', 2, self.image_response(Config={'Env': [sensitive + 'x' * 1048576]}), 'config_size'),
                    ('bad-repodigests', 2, self.image_response(RepoDigests=sensitive), 'receipt_shape')]
        for name, position, replacement, reason in variants:
            self.setUp()
            path = self.manifest['actions'][position]['path']
            normal = self.respond
            def response(method, requested, payload, *, timeout):
                result = normal(method, requested, payload, timeout=timeout)
                if requested == path:
                    if isinstance(replacement, Exception):
                        raise replacement
                    return replacement
                return result
            self.transport.request.side_effect = response
            collector = self.collector()
            with self.subTest(name=name), self.assertRaises(diagnostic.DiagnosticFailure) as raised:
                collector.collect()
            receipt = raised.exception.receipt
            self.assertEqual(self.transport.request.call_count, position + 1)
            self.assertEqual(receipt['failure']['reason'], reason)
            expected_status = replacement[0] if type(replacement) is tuple and \
                type(replacement[0]) is int and 100 <= replacement[0] <= 599 else None
            self.assertEqual(receipt['actions'][position]['status_code'], expected_status)
            self.assertNotIn(sensitive.encode(), canonical(receipt))
            self.assertEqual(receipt['observations'], {})
            with self.assertRaises(Refused):
                collector.collect()
            self.assertEqual(self.transport.request.call_count, position + 1)

    def test_late_and_postbinding_200_status_retained_without_failed_config(self):
        for kind in ('late', 'endpoint', 'output', 'source', 'config-processing'):
            self.setUp()
            collector = self.collector()
            path = self.manifest['actions'][2]['path']
            sensitive = 'synthesized-failed-config-sentinel'
            self.responses[path] = self.image_response(Config={'Env': [sensitive]})
            normal = self.respond
            def response(method, requested, payload, *, timeout):
                result = normal(method, requested, payload, timeout=timeout)
                if requested == path:
                    if kind == 'late':
                        self.now += 61
                    elif kind == 'endpoint':
                        self.probe.return_value = {**self.fingerprint, 'ino': 999}
                    elif kind == 'output':
                        self.output.side_effect = RuntimeError(sensitive)
                    elif kind == 'source':
                        collector.manifest['context']['source_sha'] = '8' * 40
                return result
            self.transport.request.side_effect = response
            def slow_canonical(value):
                if kind == 'config-processing' and type(value) is dict and value.get('Env') == [sensitive]:
                    self.now += 61
                return canonical(value)
            with self.subTest(kind=kind), patch.object(diagnostic, 'canonical', side_effect=slow_canonical), \
                    self.assertRaises(diagnostic.DiagnosticFailure) as raised:
                collector.collect()
            receipt = raised.exception.receipt
            self.assertEqual(receipt['actions'][2]['status_code'], 200)
            self.assertEqual(receipt['observations'], {})
            self.assertNotIn(sensitive.encode(), canonical(receipt))
            self.assertEqual(self.transport.request.call_count, 3)

    def test_gate_failure_has_no_requests_and_one_deadline_shrinks(self):
        self.gate.side_effect = RuntimeError('private gate detail')
        collector = self.collector()
        with self.assertRaises(diagnostic.DiagnosticFailure):
            collector.collect()
        self.transport.request.assert_not_called()
        with self.assertRaises(Refused):
            collector.collect()
        self.setUp()
        def delayed(*args, **kwargs):
            result = self.respond(*args, **kwargs)
            self.now += 12
            return result
        self.transport.request.side_effect = delayed
        with self.assertRaises(diagnostic.DiagnosticFailure) as raised:
            self.collector().collect()
        self.assertEqual(self.transport.request.call_count, 5)
        self.assertEqual(raised.exception.receipt['actions'][4]['status_code'], 404)
        self.assertEqual(raised.exception.receipt['failure']['phase'], 'deadline')

    def test_filesystem_prepare_execute_bindings_private_outputs_and_persistent_replay(self):
        from test_controller_adapters import contract, seal
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained = root / 'retained.json'
            entries = [{'source_repository': ref.split('@')[0], 'manifest_digest': ref.split('@')[1],
                        'image_id': 'sha256:' + 'f' * 64, 'platform': 'linux/amd64'}
                       for ref in self.refs.values()]
            entries = [IMAGE if entry['source_repository'] == IMAGE['source_repository'] else entry for entry in entries]
            retained.write_bytes(canonical({'images': entries}))
            tool = root / 'fixture-executable'
            tool.write_bytes(b'synthesized executable bytes; never executed')
            inputs_path = root / 'inputs.json'
            inputs_path.write_bytes(canonical({'attempt': 'fixture-diagnostic-attempt', 'image_refs': self.refs,
                'local_files': {str(tool): sha(tool.read_bytes())}, 'total_timeout': 60,
                'retained_manifest_path': str(retained), 'retained_manifest_sha256': sha(retained.read_bytes())}))
            current = contract()
            current['identity']['source_sha'] = 'a' * 40
            current['pairing_sha256'] = sha(canonical(current['identity']))
            seal(current)
            contract_path = root / 'contract.json'
            contract_path.write_bytes(canonical(current))
            output = root / 'output'
            args = Namespace(repo=str(root), source_sha='a' * 40, contract=str(contract_path),
                image_inputs=str(inputs_path), endpoint='/fixture/daemon.sock', directory=str(output))
            with patch.object(diagnostic.base, '_source') as source_check, \
                    patch.object(diagnostic, '_dependencies', return_value={'reference_diagnostic.py': 'f' * 64}), \
                    patch.object(diagnostic.base, 'socket_fingerprint', return_value=self.fingerprint), \
                    patch('controller_transports.UnixJsonTransport') as factory:
                digest = diagnostic.prepare_action(args)
                factory.assert_not_called()
                self.assertEqual(output.stat().st_mode & 0o777, 0o700)
                manifest_path = output / diagnostic.MANIFEST
                marker = output / diagnostic.MARKER
                self.assertEqual(manifest_path.stat().st_mode & 0o777, 0o600)
                self.assertFalse(marker.exists())
                execute = Namespace(manifest=str(manifest_path), manifest_sha256=digest,
                                    runner_sha256=sha(Path(diagnostic.__file__).read_bytes()))
                # File provenance must fail before constructing a transport or spending the marker.
                tool_bytes = tool.read_bytes()
                tool.write_bytes(b'changed fixture bytes')
                with self.assertRaises(Refused):
                    diagnostic.execute_action(execute)
                factory.assert_not_called()
                self.assertFalse(marker.exists())
                tool.write_bytes(tool_bytes)
                retained_bytes = retained.read_bytes()
                retained.write_bytes(retained_bytes + b' ')
                with self.assertRaises(Refused):
                    diagnostic.execute_action(execute)
                self.assertFalse(marker.exists())
                retained.write_bytes(retained_bytes)
                def request(method, path, payload, *, timeout):
                    self.assertTrue(marker.is_file())
                    self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
                    self.assertEqual((method, payload), ('GET', b''))
                    return copy.deepcopy(self.responses[path])
                factory.return_value.request.side_effect = request
                diagnostic.execute_action(execute)
                receipt_path = output / diagnostic.RECEIPT
                receipt_bytes = receipt_path.read_bytes()
                self.assertEqual(receipt_path.stat().st_mode & 0o777, 0o600)
                self.assertEqual(json.loads(receipt_bytes)['status'], 'diagnostic-sequence-completed')
                self.assertEqual(factory.return_value.request.call_count, 5)
                with self.assertRaises(Refused):
                    diagnostic.execute_action(execute)
                self.assertEqual(factory.return_value.request.call_count, 5)
                self.assertEqual(receipt_path.read_bytes(), receipt_bytes)
                self.assertTrue(source_check.call_count >= 4)
                child_called = root / 'forbidden-child-request'
                def child_replay():
                    def forbidden(*_args, **_kwargs):
                        child_called.write_text('attempted')
                        raise RuntimeError('No child request allowed')
                    factory.return_value.request.side_effect = forbidden
                    with self.assertRaises(Refused):
                        diagnostic.execute_action(execute)
                process = multiprocessing.get_context('fork').Process(target=child_replay)
                process.start()
                process.join(timeout=5)
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
                    self.fail('Synthetic replay process did not finish')
                self.assertEqual(process.exitcode, 0)
                self.assertFalse(child_called.exists())
                # Copying the manifest into a replacement output directory cannot reset the marker.
                output.rename(root / 'old-output')
                output.mkdir(mode=0o700)
                manifest_path.write_bytes((root / 'old-output' / diagnostic.MANIFEST).read_bytes())
                with self.assertRaises(Refused):
                    diagnostic.execute_action(execute)
                self.assertEqual(factory.return_value.request.call_count, 5)
                # Stable inode with broadened permissions must also refuse after a returned status.
                args.directory = str(root / 'output2')
                digest2 = diagnostic.prepare_action(args)
                execute2 = Namespace(manifest=str(root / 'output2' / diagnostic.MANIFEST),
                    manifest_sha256=digest2, runner_sha256=execute.runner_sha256)
                def broaden_output(*_args, **_kwargs):
                    (root / 'output2').chmod(0o755)
                    return 200, VERSION
                factory.return_value.request.reset_mock()
                factory.return_value.request.side_effect = broaden_output
                with self.assertRaises(Refused):
                    diagnostic.execute_action(execute2)
                factory.return_value.request.assert_called_once()
                failure = json.loads((root / 'output2' / diagnostic.RECEIPT).read_bytes())['failure']
                self.assertEqual((failure['phase'], failure['reason'], failure['status_code']),
                                 ('post_request_binding', 'output_binding', 200))
                self.assertEqual((root / 'output2' / diagnostic.RECEIPT).stat().st_mode & 0o777, 0o600)
                # Receipt-write failure stays sanitized and leaves replay prevention spent.
                args.directory = str(root / 'output3')
                digest3 = diagnostic.prepare_action(args)
                execute3 = Namespace(manifest=str(root / 'output3' / diagnostic.MANIFEST),
                    manifest_sha256=digest3, runner_sha256=execute.runner_sha256)
                factory.return_value.request.reset_mock()
                factory.return_value.request.side_effect = RuntimeError('synthesized private transport detail')
                original_write = diagnostic.base._write_at
                def failing_receipt_write(directory, name, value):
                    if name == diagnostic.RECEIPT:
                        raise OSError('synthesized private receipt-write detail')
                    return original_write(directory, name, value)
                with patch.object(diagnostic.base, '_write_at', side_effect=failing_receipt_write):
                    for _attempt in range(2):
                        with self.assertRaisesRegex(Refused, '^Reference diagnostic incomplete$') as raised:
                            diagnostic.execute_action(execute3)
                        self.assertTrue(raised.exception.__suppress_context__)
                factory.return_value.request.assert_called_once()
                self.assertTrue((root / 'output3' / diagnostic.MARKER).is_file())
                self.assertFalse((root / 'output3' / diagnostic.RECEIPT).exists())

    def test_new_runner_dependency_must_match_retained_and_committed_bytes(self):
        raw = b'synthesized module bytes'
        contract = {'identity': {'source_sha': 'a' * 40}, 'source_references': {
            'scripts/codex-qualification/reference_diagnostic.py': {'sha256': sha(raw)}}}
        with patch.object(diagnostic.base, '_dependencies', return_value={'prebuild_acquisition.py': 'b' * 64}) as reused, \
                patch.object(diagnostic.base, '_read', return_value=raw), \
                patch.object(diagnostic.base, 'git', return_value=raw) as committed:
            measured = diagnostic._dependencies('/fixture/repo', contract)
            self.assertEqual(measured['reference_diagnostic.py'], sha(raw))
            reused.assert_called_once_with('/fixture/repo', contract)
            committed.return_value = b'changed committed fixture module'
            with self.assertRaises(Refused):
                diagnostic._dependencies('/fixture/repo', contract)


if __name__ == '__main__':
    unittest.main()

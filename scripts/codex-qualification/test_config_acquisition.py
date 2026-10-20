"""Synthesized coordinator/receipt boundaries; no real origins or retained inputs."""
import copy
from argparse import Namespace
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import config_acquisition as acquisition
from prepare import Refused, canonical, sha
import test_registry_metadata as fixtures

TOKEN = fixtures.TOKEN


BODY = canonical({'os': 'linux', 'architecture': 'amd64',
                  'rootfs': {'type': 'layers', 'diff_ids': []},
                  'config': {'Env': ['SYNTHESIZED_SECRET=do-not-retain']}})
BODY += b' ' * (2646 - len(BODY))
LOCATION = 'https://production.cloudfront.docker.com/synthetic/private?fixture=DO_NOT_RETAIN'


class ConfigAcquisition(unittest.TestCase):
    def setUp(self):
        fixtures.RegistryMetadata.setUp(self)
        self.context['image_refs']['inbucket'] = ('docker.io/axllent/mailpit@sha256:' +
                                                 acquisition.PLATFORM_SHA256)
        self.context['bindings']['dependency_sha256']['config_acquisition.py'] = '9' * 64
        self.image = {'source_repository': 'docker.io/axllent/mailpit',
                      'manifest_digest': 'sha256:' + acquisition.PLATFORM_SHA256,
                      'image_id': acquisition.CONFIG_DIGEST, 'platform': 'linux/amd64'}
        self.platform = {'path': '/fixture/platform.json',
                         'sha256': acquisition.PLATFORM_SHA256, 'bytes': 864,
                         'layer_count': 0, 'config_descriptor': acquisition.config_descriptor()}
        self.plan = acquisition.action_manifest(retained_image=self.image,
            platform_evidence=self.platform, schema_reference_closure='8' * 64, **self.context)
        self.digest = sha(canonical(self.plan))
        self.gate = Mock(return_value='7' * 64)
        self.now = 10.0
        self.output = Mock()
        self.transport = Mock()
        self.transport.request.side_effect = self.respond
        self.responses = [(200, canonical({'token': TOKEN})), (307, LOCATION), (200, BODY)]
        self.events = []

    def respond(self, role, *, location=None, bearer=None, deadline, observe):
        self.gate.assert_called_once_with()
        index = ('token', 'registry', 'destination').index(role)
        self.assertEqual(bearer, TOKEN if role == 'registry' else None)
        self.assertEqual(location, LOCATION if role == 'destination' else None)
        self.assertLessEqual(deadline, self.now + 10)
        self.assertGreater(deadline, self.now)
        for event, value in [('peer_ok', True), ('tls_ok', True), ('send', None),
                             ('http_status', self.responses[index][0])]:
            observe(event, value)
        if role == 'destination' and self.responses[index][0] == 200:
            observe('body_bytes', len(self.responses[index][1]))
        self.events.append(role)
        return self.responses[index]

    def collector(self):
        return acquisition.ConfigAcquisition(self.plan, self.transport, self.gate,
            manifest_sha256=self.digest, clock=lambda: self.now, output_binding=self.output)

    def positive_hash(self, raw):
        # The pinned real Config cannot be synthesized. Only this positive-flow
        # hash seam substitutes its digest; raw hashing refusals are tested below.
        self.assertEqual(raw, BODY)
        return acquisition.CONFIG_DIGEST[7:]

    def success(self, collector=None):
        with patch.object(acquisition, '_config_sha256', side_effect=self.positive_hash):
            return (collector or self.collector()).collect()

    def test_exact_three_requests_after_gate_and_no_capability_or_config_in_receipt(self):
        collector = self.collector()
        self.transport.request.assert_not_called()
        self.gate.assert_not_called()
        result = self.success(collector)
        self.assertEqual(self.events, ['token', 'registry', 'destination'])
        self.assertEqual(result['request_count'], 3)
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['config_checks'], {'bytes_read': 2646,
            'length_ok': True, 'digest_ok': True, 'schema_ok': True})
        self.assertEqual(result['bindings']['marker'], '7' * 64)
        self.assertTrue(all(value is False for value in result['authority'].values()))
        acquisition.checked_receipt(result, self.plan, self.digest, '7' * 64)
        for secret in (TOKEN, LOCATION, 'DO_NOT_RETAIN', 'SYNTHESIZED_SECRET', 'rootfs', 'diff_ids'):
            self.assertNotIn(secret.encode(), canonical(result))
        self.assertGreaterEqual(self.output.call_count, 7)
        with self.assertRaises(Refused):
            collector.collect()
        self.assertEqual(self.transport.request.call_count, 3)

    def test_exact_manifest_rejects_rehashed_changes_and_wrong_pins(self):
        for change in (lambda m: m.update(extra='synthetic'),
                       lambda m: m.update(total_timeout=61),
                       lambda m: m['actions'][2].update(maximum_bytes=2647),
                       lambda m: m['actions'][2]['headers'].update(Authorization='fixture'),
                       lambda m: m['platform_evidence'].update(sha256='0' * 64),
                       lambda m: m['retained_image'].update(image_id='sha256:' + '0' * 64)):
            value = copy.deepcopy(self.plan)
            change(value)
            with self.subTest(change=change), self.assertRaises(Refused):
                acquisition.checked_manifest(value, sha(canonical(value)))

    def test_gate_or_output_refusal_prevents_all_requests_and_cannot_replay(self):
        for target in ('gate', 'output'):
            self.setUp()
            getattr(self, target).side_effect = Refused('SYNTHESIZED_PRIVATE_ERROR')
            collector = self.collector()
            with self.assertRaises(Refused):
                collector.collect()
            self.transport.request.assert_not_called()
            with self.assertRaises(Refused):
                collector.collect()

    def test_output_replacement_between_requests_stops_before_next(self):
        calls = 0
        def binding():
            nonlocal calls
            calls += 1
            if calls == 4:
                raise Refused('SYNTHESIZED_OUTPUT_REPLACED')
        self.output.side_effect = binding
        with self.assertRaises(acquisition.AcquisitionFailure) as raised:
            self.collector().collect()
        self.assertLess(self.transport.request.call_count, 3)
        self.assertEqual(raised.exception.receipt['failure'], 'output')
        self.assertNotIn(b'SYNTHESIZED_OUTPUT_REPLACED', canonical(raised.exception.receipt))

    def test_real_digest_rejects_synthetic_exact_length_and_short_body(self):
        for raw, code in ((BODY, 'digest'), (b'{}', 'body')):
            self.setUp()
            self.responses[2] = (200, raw)
            with self.assertRaises(acquisition.AcquisitionFailure) as raised:
                self.collector().collect()
            result = raised.exception.receipt
            self.assertEqual(result['failure'], code)
            self.assertEqual(result['config_checks']['length_ok'], len(raw) == 2646)
            self.assertIsNot(result['config_checks']['digest_ok'], True)
            self.assertIsNone(result['config_checks']['schema_ok'])

    def test_schema_refusal_after_integrity_is_sanitized(self):
        raw = b'[]' + b' ' * 2644
        self.responses[2] = (200, raw)
        with patch.object(acquisition, '_config_sha256', return_value=acquisition.CONFIG_DIGEST[7:]):
            with self.assertRaises(acquisition.AcquisitionFailure) as raised:
                self.collector().collect()
        self.assertEqual(raised.exception.receipt['failure'], 'schema')
        self.assertIs(raised.exception.receipt['config_checks']['schema_ok'], False)

    def test_status_token_location_and_transport_refusals_never_follow_on(self):
        for index, response, count, code in (
                (0, (401, b'private'), 1, 'status'),
                (0, (200, b'{"token":"bad\\r\\nvalue"}'), 1, 'token'),
                (1, (200, b'private'), 2, 'status'),
                (1, (307, 'https://other.invalid/private'), 2, 'location'),
                (2, (307, b'private'), 3, 'status')):
            self.setUp()
            self.responses[index] = response
            with self.assertRaises(acquisition.AcquisitionFailure) as raised:
                self.collector().collect()
            self.assertEqual(self.transport.request.call_count, count)
            self.assertEqual(raised.exception.receipt['failure'], code)
            self.assertNotIn(b'private', canonical(raised.exception.receipt))

    def test_deadline_shrinks_instead_of_resetting(self):
        respond = self.respond
        def slow(*args, **kwargs):
            response = respond(*args, **kwargs)
            self.now += 35
            return response
        self.transport.request.side_effect = slow
        with self.assertRaises(acquisition.AcquisitionFailure) as raised:
            self.collector().collect()
        self.assertEqual(raised.exception.receipt['failure'], 'deadline')
        self.assertEqual(self.transport.request.call_count, 1)

    def test_gate_time_is_inside_overall_deadline_and_exception_context_is_sanitized(self):
        def slow_gate():
            self.now += 61
            return '7' * 64
        self.gate.side_effect = slow_gate
        with self.assertRaises(acquisition.AcquisitionFailure) as caught:
            self.collector().collect()
        self.assertEqual(caught.exception.receipt['failure'], 'deadline')
        self.transport.request.assert_not_called()
        self.setUp()
        self.responses[0] = (200, b'{"token":"SYNTHESIZED_PRIVATE_TOKEN')
        with self.assertRaises(acquisition.AcquisitionFailure) as caught:
            self.collector().collect()
        self.assertIsNone(caught.exception.__context__)

    def test_real_adapter_and_collector_chain_with_mocked_socket_only(self):
        import test_config_https as wires
        token = canonical({'token': TOKEN})
        sockets = [wires.FakeSocket(wires.response(headers=[('Content-Length', str(len(token))),
                    ('Content-Type', 'application/json')], body=token)),
                   wires.FakeSocket(wires.response(307, [('Location', LOCATION)], b'UNREAD_REGISTRY')),
                   wires.FakeSocket(wires.response(headers=[('Content-Length', '2646'),
                    ('Content-Type', 'application/octet-stream')], body=BODY + b'UNREAD_CONFIG'))]
        context = Mock()
        context.wrap_socket.side_effect = lambda sock, **_kwargs: sock
        with patch.object(acquisition.https, '_tls_context', return_value=context), \
                patch.object(acquisition.https, 'resolve_addresses', return_value=[[2, '8.8.8.8', 443, 0, 0]]), \
                patch.object(acquisition.https.socket, 'socket', side_effect=sockets):
            self.transport = acquisition.https.BoundedHTTPS(b'CA', sha(b'CA'), clock=lambda: self.now)
            result = self.success()
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['request_count'], 3)
        self.assertEqual(bytes(sockets[1].response), b'UNREAD_REGISTRY')
        self.assertEqual(bytes(sockets[2].response), b'UNREAD_CONFIG')
        self.assertIn(TOKEN.encode(), sockets[1].sent)
        self.assertNotIn(TOKEN.encode(), sockets[0].sent)
        self.assertNotIn(TOKEN.encode(), sockets[2].sent)
        self.assertTrue(all(sock.closed for sock in sockets))

    def test_receipt_rejects_rehashed_extra_fields_and_inconsistent_scalars(self):
        good = self.success()
        mutations = [lambda r: r.update(extra='private'),
            lambda r: r['authority'].update(qualified=True),
            lambda r: r['bindings'].update(extra='private'),
            lambda r: r['bindings'].update(ca='0' * 64),
            lambda r: r.update(request_count=True),
            lambda r: r['config_checks'].update(bytes_read=True),
            lambda r: r['config_checks'].update(schema_ok=None),
            lambda r: r['actions'][2].update(http_status=307),
            lambda r: r['actions'][2].update(peer_ok=None),
            lambda r: r.update(review='passed'),
            lambda r: r.update(status='refused', failure=None),
            lambda r: r['output_identity'].update(inode=True)]
        for change in mutations:
            bad = copy.deepcopy(good)
            change(bad)
            bad['receipt_sha256'] = sha(canonical({k: v for k, v in bad.items() if k != 'receipt_sha256'}))
            with self.subTest(change=change), self.assertRaises(Refused):
                acquisition.checked_receipt(bad, self.plan, self.digest, '7' * 64)

    def test_transport_observer_rejects_fake_events_before_more_requests(self):
        for event, value in [('extra', 'private'), ('send', 'private'),
                             ('http_status', True), ('body_bytes', 2647),
                             ('peer_ok', 'true')]:
            self.setUp()
            def bad(role, *, observe, **_kwargs):
                observe(event, value)
                return self.responses[0]
            self.transport.request.side_effect = bad
            with self.assertRaises(acquisition.AcquisitionFailure) as raised:
                self.collector().collect()
            self.assertEqual(self.transport.request.call_count, 1)
            self.assertNotIn(b'private', canonical(raised.exception.receipt))

    def test_private_output_store_replay_and_replacement_are_real_filesystem_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'out'
            output.mkdir(mode=0o700)
            info = output.stat()
            identity = {'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid}
            with acquisition.PrivateOutput(str(output), identity) as store:
                store.check()
                marker_hash = store.consume(self.digest)
                self.assertEqual(len(marker_hash), 64)
                with self.assertRaises(Refused):
                    store.consume(self.digest)
                output.chmod(0o755)
                with self.assertRaises(Refused):
                    store.check()
                output.chmod(0o700)
                original = Path(directory) / 'original'
                output.rename(original)
                output.mkdir(mode=0o700)
                with self.assertRaises(Refused):
                    store.check()

    def test_private_files_refuse_symlinks_fifos_and_public_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'out'
            output.mkdir(mode=0o700)
            info = output.stat()
            identity = {'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid}
            unsafe = output / acquisition.MANIFEST
            with acquisition.PrivateOutput(str(output), identity) as store:
                unsafe.symlink_to('/does-not-exist-synthetic')
                with self.assertRaises(OSError):
                    store.read(acquisition.MANIFEST)
                unsafe.unlink()
                os.mkfifo(unsafe)
                with self.assertRaises(Refused):
                    store.read(acquisition.MANIFEST)
                unsafe.unlink()
                unsafe.write_bytes(b'{}')
                unsafe.chmod(0o644)
                with self.assertRaises(Refused):
                    store.read(acquisition.MANIFEST)

    def test_dependency_census_checks_all_actual_local_source_and_committed_blobs(self):
        root = Path(acquisition.__file__).resolve().parents[2]
        contract = {'identity': {'source_sha': 'a' * 40}, 'source_references': {}}
        for name in acquisition.DEPENDENCIES:
            relative = 'scripts/codex-qualification/' + name
            contract['source_references'][relative] = {'sha256': sha((root / relative).read_bytes())}
        def committed(_repo, *args):
            return (root / args[-1].split(':', 1)[1]).read_bytes()
        with patch.object(acquisition.diagnostic, '_dependencies', return_value={}), \
                patch.object(acquisition.metadata.base, 'git', side_effect=committed):
            result = acquisition._dependencies(str(root), contract)
            self.assertEqual(set(result), set(acquisition.DEPENDENCIES))
            for name in acquisition.DEPENDENCIES:
                bad = copy.deepcopy(contract)
                bad['source_references']['scripts/codex-qualification/' + name]['sha256'] = '0' * 64
                with self.subTest(name=name), self.assertRaises(Refused):
                    acquisition._dependencies(str(root), bad)
        with patch.object(acquisition.diagnostic, '_dependencies', return_value={}), \
                patch.object(acquisition.metadata.base, 'git', return_value=b'wrong committed bytes'):
            with self.assertRaises(Refused):
                acquisition._dependencies(str(root), contract)

    def source_inputs(self):
        plan = copy.deepcopy(self.plan)
        raw = b'{"synthetic":"contract"}'
        runner = Path(acquisition.__file__).read_bytes()
        plan['schema_reference_closure'] = acquisition.config_schema.reference_closure_sha256()
        bindings = plan['context']['bindings']
        bindings['contract_sha256'] = sha(raw)
        bindings['dependency_sha256']['config_acquisition.py'] = sha(runner)
        context = plan['context']
        contract = {'pairing_sha256': context['pairing_sha256'],
                    'operational_sha256': context['operational_sha256']}
        inputs = {'local_files': {}, 'retained_manifest_path': bindings['retained_manifest_path'],
            'total_timeout': 60, 'attempt': context['attempt'], 'image_refs': context['image_refs'],
            'retained_manifest_sha256': context['retained_manifest_sha256']}
        source = (contract, raw, inputs, bindings['image_inputs_sha256'], self.image, fixtures.CA)
        return plan, runner, source

    def test_source_binding_predicates_refuse_each_changed_input(self):
        changes = [lambda p, s: p['runtime']['python'].__setitem__(0, 0),
            lambda p, s: p.update(schema_reference_closure='0' * 64),
            lambda p, s: p['context']['bindings'].update(contract_sha256='0' * 64),
            lambda p, s: p['context']['bindings'].update(image_inputs_sha256='0' * 64),
            lambda p, s: s[0].update(pairing_sha256='0' * 64),
            lambda p, s: s[0].update(operational_sha256='0' * 64),
            lambda p, s: s[2].update(local_files={'unexpected': '0' * 64}),
            lambda p, s: s[2].update(attempt='wrong-attempt'),
            lambda p, s: s[2].update(total_timeout=59),
            lambda p, s: s[2].update(retained_manifest_sha256='0' * 64)]
        for change in [None, *changes]:
            plan, runner, source = self.source_inputs()
            platform = {k: v for k, v in self.platform.items() if k != 'path'}
            args = Namespace(runner_sha256=sha(runner))
            if change:
                change(plan, source)
            with patch.object(acquisition.metadata, '_source_inputs', return_value=source), \
                    patch.object(acquisition, '_dependencies', return_value=self.source_inputs()[0]['context']['bindings']['dependency_sha256']), \
                    patch.object(acquisition, '_platform', return_value=platform), \
                    patch.object(acquisition.metadata.base, '_read', return_value=runner):
                if change:
                    with self.assertRaises(Refused):
                        acquisition._verify_inputs(plan, args)
                else:
                    self.assertEqual(acquisition._verify_inputs(plan, args), fixtures.CA)

    def test_actual_prepare_and_execute_functions_with_synthesized_private_files_only(self):
        with tempfile.TemporaryDirectory() as directory:
            plan, runner, source = self.source_inputs()
            root = Path(directory)
            platform_file = root / 'platform.json'
            platform_file.write_bytes(b'synthetic platform fixture')
            args = Namespace(repo='/fixture/repo', source_sha='a' * 40,
                contract='/fixture/contract.json', image_inputs='/fixture/inputs.json',
                platform_file=str(platform_file), directory=str(root / 'out'),
                ca_file='/fixture/ca.pem', ca_sha256=sha(fixtures.CA))
            projected = {k: v for k, v in self.platform.items() if k != 'path'}
            deps = plan['context']['bindings']['dependency_sha256']
            with patch.object(acquisition.metadata, '_source_inputs', return_value=source), \
                    patch.object(acquisition, '_dependencies', return_value=deps), \
                    patch.object(acquisition, '_platform', return_value=projected), \
                    patch.object(acquisition.https, 'BoundedHTTPS') as adapter:
                digest = acquisition.prepare_action(args)
                adapter.assert_not_called()
            output = Path(args.directory)
            self.assertEqual({p.name for p in output.iterdir()}, {acquisition.MANIFEST})
            manifest = json.loads((output / acquisition.MANIFEST).read_bytes())
            acquisition.checked_manifest(manifest, digest)
            self.plan, self.digest = manifest, digest
            execution = Namespace(manifest=str(output / acquisition.MANIFEST),
                                  manifest_sha256=digest, runner_sha256=sha(runner))
            original_consume = acquisition.PrivateOutput.consume
            def consumed(store, manifest_digest):
                result = original_consume(store, manifest_digest)
                self.gate()
                return result
            with patch.object(acquisition, '_verify_inputs', return_value=fixtures.CA), \
                    patch.object(acquisition.https, 'BoundedHTTPS', return_value=self.transport), \
                    patch.object(acquisition.PrivateOutput, 'consume', consumed), \
                    patch.object(acquisition.resource, 'setrlimit') as core, \
                    patch.object(acquisition, '_config_sha256', side_effect=self.positive_hash):
                acquisition.execute_action(execution, clock=lambda: self.now)
                core.assert_called_once_with(acquisition.resource.RLIMIT_CORE, (0, 0))
                count = self.transport.request.call_count
                with self.assertRaises(Refused):
                    acquisition.execute_action(execution, clock=lambda: self.now)
                self.assertEqual(self.transport.request.call_count, count)
            result = json.loads((output / acquisition.RECEIPT).read_bytes())
            self.assertEqual(result['status'], 'complete')
            self.assertEqual({p.name for p in output.iterdir()},
                             {acquisition.MANIFEST, acquisition.MARKER, acquisition.RECEIPT})
            for path in output.iterdir():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_coordinator_mutation_oracles_detect_missing_guards(self):
        source = Path(acquisition.__file__).read_text()
        mutants = [
            ("            _ensure(value['stage'] == 'complete' and value['failure'] is None and count == 3 and",
             "            _ensure(True or value['stage'] == 'complete' and value['failure'] is None and count == 3 and",
             'test_receipt_rejects_rehashed_extra_fields_and_inconsistent_scalars'),
            ("        _ensure(not self.attempted, 'replay')", '        pass',
             'test_exact_three_requests_after_gate_and_no_capability_or_config_in_receipt'),
            ("                    checks['digest_ok'] = 'sha256:' + _config_sha256(payload) == CONFIG_DIGEST",
             "                    checks['digest_ok'] = True",
             'test_real_digest_rejects_synthetic_exact_length_and_short_body'),
            ("                current.st_uid == os.getuid() and stat.S_IMODE(current.st_mode) == 0o700 and",
             "                current.st_uid == os.getuid() and True and",
             'test_private_output_store_replay_and_replacement_are_real_filesystem_checks'),
        ]
        for index, (old, new, oracle) in enumerate(mutants):
            with self.subTest(oracle=oracle), tempfile.TemporaryDirectory() as directory:
                pristine = unittest.TestResult()
                ConfigAcquisition(oracle).run(pristine)
                self.assertTrue(pristine.wasSuccessful(), 'pristine mutation oracle must pass')
                self.assertEqual(source.count(old), 1)
                path = Path(directory) / 'mutant.py'
                path.write_text(source.replace(old, new))
                spec = importlib.util.spec_from_file_location('coordinator_mutant_' + str(index), path)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                case = ConfigAcquisition(oracle)
                outcome = unittest.TestResult()
                with patch.dict(globals(), acquisition=module):
                    case.run(outcome)
                self.assertFalse(outcome.errors, 'instrument errors are not caught mutations')
                self.assertTrue(outcome.failures, 'removed guard escaped its behavioral oracle')


if __name__ == '__main__':
    unittest.main()

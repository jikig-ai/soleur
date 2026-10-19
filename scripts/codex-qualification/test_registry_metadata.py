"""Public metadata protocol with synthesized bytes and injected transports only."""
import copy
import errno
from argparse import Namespace
import json
import multiprocessing
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import registry_metadata as metadata
from prepare import Refused, canonical, sha

TOKEN = 'SYNTHESIZED_PRIVATE_ANONYMOUS_TOKEN'
CA = b'-----BEGIN CERTIFICATE-----\nSYNTHESIZED-CA-FIXTURE\n-----END CERTIFICATE-----\n'
CONFIG = canonical({'architecture': 'amd64', 'os': 'linux', 'config': {'Env': ['FIXTURE=1']}})
PLATFORM = canonical({'schemaVersion': 2, 'mediaType': 'application/vnd.oci.image.manifest.v1+json',
    'config': {'mediaType': 'application/vnd.oci.image.config.v1+json',
               'digest': 'sha256:' + sha(CONFIG), 'size': len(CONFIG)},
    'layers': [{'mediaType': 'application/vnd.oci.image.layer.v1.tar+gzip',
                'digest': 'sha256:' + '3' * 64, 'size': 1234}]})
IMAGE = {'source_repository': 'docker.io/axllent/mailpit', 'manifest_digest': 'sha256:' + sha(PLATFORM),
         'image_id': 'sha256:' + sha(CONFIG), 'platform': 'linux/amd64'}


class RegistryMetadata(unittest.TestCase):
    def setUp(self):
        self.fingerprint = {'dev': 4, 'ino': 7, 'uid': 1000}
        self.refs = {role: 'registry.invalid/fixture/' + role + '@sha256:' + str(i + 1) * 64
                     for i, role in enumerate(('db', 'kong', 'auth', 'inbucket', 'rest', 'storage'))}
        self.refs['inbucket'] = IMAGE['source_repository'] + '@' + IMAGE['manifest_digest']
        self.context = {'source_sha': 'a' * 40, 'pairing_sha256': 'b' * 64, 'operational_sha256': 'c' * 64,
            'retained_manifest_sha256': 'd' * 64, 'image_refs': self.refs, 'attempt': 'fixture-registry',
            'timeout': 60, 'output_directory': '/fixture/output', 'output_directory_fingerprint': self.fingerprint,
            'ca_file': '/fixture/ca.pem', 'ca_sha256': sha(CA),
            'bindings': {'repo': '/fixture/repo', 'contract_path': '/fixture/contract.json',
                'contract_sha256': 'e' * 64, 'image_inputs_path': '/fixture/inputs.json',
                'image_inputs_sha256': 'f' * 64, 'retained_manifest_path': '/fixture/retained.json',
                'dependency_sha256': {'registry_metadata.py': '9' * 64}, 'local_files': {}}}
        self.manifest = metadata.action_manifest(retained_image=IMAGE, **self.context)
        self.gate = Mock()
        self.output = Mock()
        self.published = {}
        self.now = 10.0
        self.transport = Mock()
        self.responses = [(200, 'application/json', canonical({'token': TOKEN, 'access_token': TOKEN})),
                          (200, 'application/vnd.oci.image.manifest.v1+json', PLATFORM),
                          (200, 'application/octet-stream', CONFIG)]
        self.transport.request.side_effect = self.respond

    def respond(self, url, headers, *, timeout, maximum_bytes):
        self.gate.assert_called_once_with()
        index = [action['url'] for action in self.manifest['actions']].index(url)
        expected_headers = dict(self.manifest['actions'][index]['headers'])
        if index:
            expected_headers['Authorization'] = 'Bearer ' + TOKEN
        self.assertEqual(headers, expected_headers)
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)
        self.assertEqual(maximum_bytes, self.manifest['actions'][index]['maximum_bytes'])
        return self.responses[index]

    def publish(self, name, raw, validate):
        validate()
        self.assertNotIn(name, self.published)
        self.published[name] = raw
        def rollback():
            if self.published.get(name) is raw:
                del self.published[name]
        rollback.accept = lambda: None
        return rollback

    def collector(self):
        return metadata.RegistryMetadata(self.manifest, self.transport, self.gate, self.publish,
            manifest_sha256=sha(canonical(self.manifest)), clock=lambda: self.now, output_binding=self.output)

    def test_exact_three_requests_bind_raw_digests_and_never_persist_token_or_local_id(self):
        collector = self.collector()
        self.transport.request.assert_not_called()
        self.gate.assert_not_called()
        receipt = collector.collect()
        self.assertEqual([call.args[0] for call in self.transport.request.call_args_list],
                         [action['url'] for action in self.manifest['actions']])
        self.assertEqual(len(set(action['url'] for action in self.manifest['actions'])), 3)
        self.assertEqual([row['status_code'] for row in receipt['actions']], [200, 200, 200])
        self.assertEqual(self.published, {metadata.PLATFORM_FILE: PLATFORM, metadata.CONFIG_FILE: CONFIG})
        self.assertNotIn(TOKEN.encode(), canonical(receipt))
        self.assertNotIn(TOKEN.encode(), canonical(self.manifest))
        self.assertNotIn('image_id', receipt)
        self.assertIs(receipt['local_image_observed'], False)
        self.assertEqual(receipt['metadata']['config']['sha256'], sha(CONFIG))
        self.assertEqual(receipt['metadata']['platform']['layer_count'], 1)
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertIs(receipt[field], False)
        self.assertEqual(receipt['receipt_sha256'], sha(canonical(
            {key: value for key, value in receipt.items() if key != 'receipt_sha256'})))

    def test_token_aliases_are_memory_only_and_mismatched_aliases_stop(self):
        for body in ({'token': TOKEN}, {'access_token': TOKEN}, {'token': TOKEN, 'access_token': 'different'},
                     {'token': TOKEN + '\r\nInjected: value'}, {'token': ''}):
            self.setUp()
            self.responses[0] = (200, 'application/json', canonical(body))
            valid = body in ({'token': TOKEN}, {'access_token': TOKEN})
            with self.subTest(keys=list(body)):
                if valid:
                    receipt = self.collector().collect()
                else:
                    with self.assertRaises(metadata.MetadataFailure) as raised:
                        self.collector().collect()
                    receipt = raised.exception.receipt
                    self.assertEqual(self.transport.request.call_count, 1)
                self.assertNotIn(TOKEN.encode(), canonical(receipt))

    def test_unexpected_status_redirect_body_media_oversize_and_digest_failures_stop(self):
        secret = 'SYNTHESIZED_PRIVATE_ERROR_OR_LOCATION'
        variants = [('challenge', 0, (401, 'application/json', secret.encode())),
                    ('redirect', 2, (307, 'text/plain', secret.encode())),
                    ('media', 1, (200, 'text/html', PLATFORM)),
                    ('oversize', 0, (200, 'application/json', b'x' * 16385)),
                    ('digest', 1, (200, 'application/vnd.oci.image.manifest.v1+json', PLATFORM + b' ')),
                    ('config-digest', 2, (200, 'application/octet-stream', CONFIG + b' '))]
        for name, position, response in variants:
            self.setUp()
            self.responses[position] = response
            collector = self.collector()
            with self.subTest(name=name), self.assertRaises(metadata.MetadataFailure) as raised:
                collector.collect()
            receipt = raised.exception.receipt
            self.assertEqual(self.transport.request.call_count, position + 1)
            self.assertEqual(receipt['actions'][position]['status_code'], response[0])
            self.assertNotIn(secret.encode(), canonical(receipt))
            self.assertNotIn(TOKEN.encode(), canonical(receipt))
            self.assertNotIn(metadata.CONFIG_FILE, self.published)
            if position == 2:
                self.assertEqual(self.published[metadata.PLATFORM_FILE], PLATFORM)
            with self.assertRaises(Refused):
                collector.collect()
            self.assertEqual(self.transport.request.call_count, position + 1)

    def test_late_config_or_output_binding_failure_is_not_published(self):
        for failure in ('deadline', 'output', 'source'):
            self.setUp()
            collector = self.collector()
            normal = self.respond
            def altered(url, *args, **kwargs):
                response = normal(url, *args, **kwargs)
                if url == self.manifest['actions'][2]['url']:
                    if failure == 'deadline':
                        self.now += 61
                    elif failure == 'output':
                        self.output.side_effect = OSError('private output detail')
                    else:
                        collector.manifest['context']['source_sha'] = '8' * 40
                return response
            self.transport.request.side_effect = altered
            with self.subTest(failure=failure), self.assertRaises(metadata.MetadataFailure) as raised:
                collector.collect()
            self.assertEqual(raised.exception.receipt['actions'][2]['status_code'], 200)
            self.assertNotIn(metadata.CONFIG_FILE, self.published)
            self.assertEqual(self.transport.request.call_count, 3)

    def test_invalid_manifest_or_gate_failure_has_no_requests(self):
        altered = copy.deepcopy(self.manifest)
        altered['actions'][1]['url'] = 'https://unapproved.invalid/payload'
        with self.assertRaises(Refused):
            metadata.RegistryMetadata(altered, self.transport, self.gate, self.publish,
                manifest_sha256=sha(canonical(self.manifest)))
        self.gate.assert_not_called()
        self.gate.side_effect = RuntimeError('private gate failure')
        collector = self.collector()
        with self.assertRaises(metadata.MetadataFailure):
            collector.collect()
        self.transport.request.assert_not_called()
        with self.assertRaises(Refused):
            collector.collect()

    def test_https_adapter_uses_pinned_ca_and_no_constructor_network_or_ambient_defaults(self):
        with patch.object(metadata.ssl, 'SSLContext') as ssl_context, \
                patch.object(metadata.http.client, 'HTTPSConnection') as connections:
            adapter = metadata.HTTPSAdapter(self.manifest, CA, manifest_sha256=sha(canonical(self.manifest)))
            connections.assert_not_called()
            ssl_context.return_value.load_verify_locations.assert_called_once_with(cadata=CA.decode('ascii'))
            response = connections.return_value.getresponse.return_value
            response.status = 200
            response.getheaders.return_value = [('Content-Length', '2'), ('Content-Type', 'application/json')]
            response.read1.side_effect = [b'{}', b'']
            action = self.manifest['actions'][0]
            returned = adapter.request(action['url'], action['headers'], timeout=10,
                                       maximum_bytes=action['maximum_bytes'])
            self.assertEqual(returned, (200, 'application/json', b'{}'))
            self.assertEqual(connections.call_args.args[:2], ('auth.docker.io', 443))
            connections.return_value.set_debuglevel.assert_called_once_with(0)
            connections.return_value.close.assert_called_once()
            before = connections.call_count
            with self.assertRaises(Refused):
                adapter.request('https://foreign.invalid/secret', {'Authorization': TOKEN}, timeout=10, maximum_bytes=1)
            self.assertEqual(connections.call_count, before)

    def test_https_adapter_never_reads_redirect_body_and_refuses_encoding_or_size(self):
        for status, pairs, chunks, reason in (
                (307, [('Location', 'https://unapproved.invalid/private')], [], None),
                (200, [('Content-Encoding', 'gzip')], [], 'body_encoding'),
                (200, [('Content-Length', '16385')], [], 'body_size'),
                (200, [('Content-Length', '1'), ('Content-Length', '1')], [], 'header_shape'),
                (200, [('Content-Type', 'application/json')], [b'x' * 16385], 'body_size')):
            with self.subTest(status=status, reason=reason), patch.object(metadata.ssl, 'SSLContext'), \
                    patch.object(metadata.http.client, 'HTTPSConnection') as connections:
                adapter = metadata.HTTPSAdapter(self.manifest, CA, manifest_sha256=sha(canonical(self.manifest)))
                response = connections.return_value.getresponse.return_value
                response.status = status
                response.getheaders.return_value = pairs
                response.read1.side_effect = chunks
                action = self.manifest['actions'][0]
                if reason is None:
                    self.assertEqual(adapter.request(action['url'], action['headers'], timeout=10,
                        maximum_bytes=action['maximum_bytes']), (307, None, b''))
                    response.getheaders.assert_not_called()
                    response.read1.assert_not_called()
                else:
                    with self.assertRaises(metadata.BoundaryFailure) as raised:
                        adapter.request(action['url'], action['headers'], timeout=10, maximum_bytes=action['maximum_bytes'])
                    self.assertEqual((raised.exception.reason, raised.exception.status), (reason, 200))
                connections.return_value.close.assert_called_once()

    def test_manifest_descriptor_and_config_platform_are_checked_after_raw_digest(self):
        for failure in ('descriptor-digest', 'descriptor-size', 'descriptor-media', 'config-platform', 'duplicate-json'):
            self.setUp()
            image, platform = copy.deepcopy(IMAGE), json.loads(PLATFORM)
            config = CONFIG
            if failure == 'config-platform':
                config = canonical({'os': 'linux', 'architecture': 'arm64'})
                image['image_id'] = 'sha256:' + sha(config)
                platform['config'].update(digest=image['image_id'], size=len(config))
            elif failure == 'descriptor-digest':
                platform['config']['digest'] = 'sha256:' + '9' * 64
            elif failure == 'descriptor-size':
                platform['config']['size'] = True
            elif failure == 'descriptor-media':
                platform['config']['mediaType'] = 'application/octet-stream'
            platform_raw = canonical(platform) if failure != 'duplicate-json' else b'{"schemaVersion":2,"schemaVersion":2}'
            image['manifest_digest'] = 'sha256:' + sha(platform_raw)
            self.context['image_refs']['inbucket'] = IMAGE['source_repository'] + '@' + image['manifest_digest']
            self.manifest = metadata.action_manifest(retained_image=image, **self.context)
            self.responses[1] = (200, 'application/vnd.oci.image.manifest.v1+json', platform_raw)
            self.responses[2] = (200, 'application/octet-stream', config)
            with self.subTest(failure=failure), self.assertRaises(metadata.MetadataFailure):
                self.collector().collect()
            self.assertNotIn(metadata.CONFIG_FILE, self.published)
            self.assertEqual(self.transport.request.call_count, 3 if failure == 'config-platform' else 2)
        self.setUp()
        self.responses[1] = (200, 'application/vnd.oci.image.manifest.v1+json', b'not-json-and-wrong-digest')
        with patch.object(metadata.base, '_decode_json', wraps=metadata.base._decode_json) as decode, \
                self.assertRaises(metadata.MetadataFailure) as raised:
            self.collector().collect()
        self.assertEqual(raised.exception.receipt['failure']['reason'], 'digest_mismatch')
        self.assertEqual(decode.call_count, 1)  # Only the prior anonymous token was parsed.

    def test_private_sink_cleans_owned_late_artifacts_without_overwriting_foreign_names(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            try:
                count = 0
                def becomes_late():
                    nonlocal count
                    count += 1
                    if count == 3:
                        raise Refused('synthetic deadline failure')
                with self.assertRaises(metadata.BoundaryFailure):
                    metadata.publish_artifact(directory, metadata.CONFIG_FILE, CONFIG, becomes_late)
                self.assertEqual(list(root.iterdir()), [])
                other = root / metadata.CONFIG_FILE
                other.write_bytes(b'foreign prior bytes')
                with self.assertRaises(metadata.BoundaryFailure):
                    metadata.publish_artifact(directory, metadata.CONFIG_FILE, CONFIG, lambda: None)
                self.assertEqual(other.read_bytes(), b'foreign prior bytes')
                self.assertFalse((root / metadata.STAGING[metadata.CONFIG_FILE]).exists())
                other.unlink()
                accepted = metadata.publish_artifact(directory, metadata.CONFIG_FILE, CONFIG, lambda: None)
                accepted.accept()
                self.assertEqual(other.read_bytes(), CONFIG)
                self.assertEqual(other.stat().st_mode & 0o777, 0o600)
                with self.assertRaises(Refused):
                    metadata.publish_artifact(directory, '../unapproved-name', CONFIG, lambda: None)
            finally:
                os.close(directory)

    def test_post_publish_collector_failure_rolls_back_only_current_owned_artifact(self):
        for target in (metadata.PLATFORM_FILE, metadata.CONFIG_FILE):
            for failure in ('deadline', 'source', 'output', 'foreign-replacement'):
                self.setUp()
                with self.subTest(target=target, failure=failure), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    root.chmod(0o700)
                    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
                    try:
                        collector = self.collector()
                        def publish_then_change_binding(name, raw, validate):
                            rollback = metadata.publish_artifact(directory, name, raw, validate)
                            if name == target:
                                if failure == 'deadline':
                                    self.now += 61
                                elif failure == 'source':
                                    collector.manifest['context']['source_sha'] = '8' * 40
                                elif failure == 'output':
                                    self.output.side_effect = OSError('synthetic private output failure')
                                else:
                                    path = root / target
                                    path.unlink()
                                    path.write_bytes(b'foreign replacement must survive')
                                    path.chmod(0o600)
                                    self.now += 61
                            return rollback
                        collector.publish = publish_then_change_binding
                        with self.assertRaises(metadata.MetadataFailure) as raised:
                            collector.collect()
                        receipt = raised.exception.receipt
                        self.assertNotIn('config', receipt['metadata'])
                        if target == metadata.PLATFORM_FILE:
                            self.assertEqual(receipt['metadata'], {})
                            self.assertEqual(self.transport.request.call_count, 2)
                        else:
                            self.assertEqual((root / metadata.PLATFORM_FILE).read_bytes(), PLATFORM)
                            self.assertIn('platform', receipt['metadata'])
                            self.assertEqual(self.transport.request.call_count, 3)
                        if failure == 'foreign-replacement':
                            self.assertEqual((root / target).read_bytes(), b'foreign replacement must survive')
                        else:
                            self.assertFalse((root / target).exists(), 'Rejected current artifact survived final collector checks')
                        self.assertFalse((root / metadata.STAGING[target]).exists())
                    finally:
                        os.close(directory)

    def test_publication_pins_created_inode_until_acceptance_or_rollback(self):
        for outcome in ('accept', 'rollback', 'close-error'):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                root.chmod(0o700)
                directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
                handle = None
                try:
                    opened = []
                    real_open, real_close = os.open, os.close
                    def record_open(name, *args, **kwargs):
                        descriptor = real_open(name, *args, **kwargs)
                        if name == metadata.STAGING[metadata.CONFIG_FILE]:
                            opened.append(descriptor)
                        return descriptor
                    def close_then_maybe_fail(descriptor):
                        real_close(descriptor)
                        if outcome == 'close-error' and descriptor == opened[0]:
                            raise OSError('synthetic private close failure')
                    with patch.object(metadata.os, 'open', side_effect=record_open), \
                            patch.object(metadata.os, 'close', side_effect=close_then_maybe_fail) as closes:
                        handle = metadata.publish_artifact(directory, metadata.CONFIG_FILE, CONFIG, lambda: None)
                        self.assertEqual(len(opened), 1)
                        descriptor = opened[0]
                        held = os.fstat(descriptor)
                        path = root / metadata.CONFIG_FILE
                        self.assertEqual((held.st_dev, held.st_ino), (path.stat().st_dev, path.stat().st_ino))
                        if outcome == 'accept':
                            handle.accept()
                            self.assertEqual(path.read_bytes(), CONFIG)
                        elif outcome == 'rollback':
                            path.unlink()
                            self.assertEqual(os.fstat(descriptor).st_ino, held.st_ino)
                            path.write_bytes(b'foreign replacement')
                            self.assertNotEqual(path.stat().st_ino, held.st_ino)
                            handle()
                            self.assertEqual(path.read_bytes(), b'foreign replacement')
                        else:
                            with self.assertRaises(metadata.BoundaryFailure) as caught:
                                handle.accept()
                            self.assertEqual(caught.exception.reason, 'publication_cleanup')
                            path.unlink()
                            path.write_bytes(b'foreign after close failure')
                            with self.assertRaises(metadata.BoundaryFailure):
                                handle()
                            self.assertEqual(path.read_bytes(), b'foreign after close failure')
                        self.assertEqual(sum(call.args[0] == descriptor for call in closes.call_args_list), 1)
                        with self.assertRaises(OSError) as caught:
                            os.fstat(descriptor)
                        self.assertEqual(caught.exception.errno, errno.EBADF)
                finally:
                    if callable(getattr(handle, 'accept', None)):
                        handle.accept()
                    os.close(directory)

    def test_failed_post_publish_cleanup_is_sanitized_and_never_accepts_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            try:
                collector = self.collector()
                def publish_then_block_cleanup(name, raw, validate):
                    rollback = metadata.publish_artifact(directory, name, raw, validate)
                    if name != metadata.CONFIG_FILE:
                        return rollback
                    self.now += 61
                    def blocked_rollback():
                        with patch.object(metadata, '_remove_owned', return_value=False):
                            rollback()
                    blocked_rollback.accept = rollback.accept
                    return blocked_rollback
                collector.publish = publish_then_block_cleanup
                with self.assertRaises(metadata.MetadataFailure) as raised:
                    collector.collect()
                receipt = raised.exception.receipt
                self.assertEqual(receipt['failure']['reason'], 'publication_cleanup')
                self.assertEqual(receipt['failure']['status_code'], 200)
                self.assertNotIn('config', receipt['metadata'])
                self.assertIn('platform', receipt['metadata'])
                self.assertEqual((root / metadata.PLATFORM_FILE).read_bytes(), PLATFORM)
                self.assertEqual((root / metadata.CONFIG_FILE).stat().st_mode & 0o777, 0o600)
                self.assertNotIn(TOKEN.encode(), canonical(receipt))
                self.assertEqual(self.transport.request.call_count, 3)
                with self.assertRaises(Refused):
                    collector.collect()
                self.assertEqual(self.transport.request.call_count, 3)
            finally:
                os.close(directory)

    def test_file_only_prepare_and_fake_execute_bind_ca_outputs_and_persistent_marker(self):
        from test_controller_adapters import contract, seal
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            retained = root / 'retained.json'
            entries = [{'source_repository': ref.split('@')[0], 'manifest_digest': ref.split('@')[1],
                        'image_id': 'sha256:' + '8' * 64, 'platform': 'linux/amd64'} for ref in self.refs.values()]
            entries = [IMAGE if entry['source_repository'] == IMAGE['source_repository'] else entry for entry in entries]
            retained.write_bytes(canonical({'images': entries}))
            inputs_path = root / 'inputs.json'
            inputs_path.write_bytes(canonical({'attempt': 'fixture-registry-cli', 'image_refs': self.refs, 'local_files': {},
                'total_timeout': 60, 'retained_manifest_path': str(retained), 'retained_manifest_sha256': sha(retained.read_bytes())}))
            current = contract()
            current['identity']['source_sha'] = 'a' * 40
            current['pairing_sha256'] = sha(canonical(current['identity']))
            seal(current)
            contract_path, ca_file = root / 'contract.json', root / 'ca.pem'
            contract_path.write_bytes(canonical(current))
            ca_file.write_bytes(CA)
            output = root / 'output'
            args = Namespace(repo=str(root), source_sha='a' * 40, contract=str(contract_path),
                image_inputs=str(inputs_path), ca_file=str(ca_file), ca_sha256=sha(CA), directory=str(output))
            with patch.object(metadata.base, '_source'), \
                    patch.object(metadata, '_dependencies', return_value={'registry_metadata.py': 'f' * 64}), \
                    patch.object(metadata, 'HTTPSAdapter') as factory:
                digest = metadata.prepare_action(args)
                factory.assert_not_called()
                self.assertEqual(output.stat().st_mode & 0o777, 0o700)
                manifest_path = output / metadata.MANIFEST
                self.assertEqual(manifest_path.stat().st_mode & 0o777, 0o600)
                marker = output / metadata.MARKER
                self.assertFalse(marker.exists())
                execute = Namespace(manifest=str(manifest_path), manifest_sha256=digest,
                                    runner_sha256=sha(Path(metadata.__file__).read_bytes()))
                ca_file.write_bytes(CA + b'changed')
                with self.assertRaises(Refused):
                    metadata.execute_action(execute)
                factory.assert_not_called()
                self.assertFalse(marker.exists())
                ca_file.write_bytes(CA)
                def request(url, headers, *, timeout, maximum_bytes):
                    self.assertTrue(marker.is_file())
                    self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
                    index = [action['url'] for action in self.manifest['actions']].index(url)
                    return self.responses[index]
                factory.return_value.request.side_effect = request
                metadata.execute_action(execute)
                self.assertEqual(factory.return_value.request.call_count, 3)
                self.assertEqual((output / metadata.PLATFORM_FILE).read_bytes(), PLATFORM)
                self.assertEqual((output / metadata.CONFIG_FILE).read_bytes(), CONFIG)
                receipt = (output / metadata.RECEIPT).read_bytes()
                for path in output.iterdir():
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    self.assertNotIn(TOKEN.encode(), path.read_bytes())
                with self.assertRaises(Refused):
                    metadata.execute_action(execute)
                self.assertEqual(factory.return_value.request.call_count, 3)
                output2 = root / 'output2'
                args.directory = str(output2)
                digest2 = metadata.prepare_action(args)
                execute2 = Namespace(manifest=str(output2 / metadata.MANIFEST), manifest_sha256=digest2,
                                     runner_sha256=execute.runner_sha256)
                outside = root / 'unapproved-output'
                outside.mkdir()
                def replace_output(url, *args, **kwargs):
                    index = [action['url'] for action in self.manifest['actions']].index(url)
                    if index == 2:
                        output2.rename(root / 'detached-output2')
                        output2.symlink_to(outside, target_is_directory=True)
                    return self.responses[index]
                factory.return_value.request.reset_mock()
                factory.return_value.request.side_effect = replace_output
                with self.assertRaises(Refused):
                    metadata.execute_action(execute2)
                self.assertEqual(factory.return_value.request.call_count, 3)
                self.assertEqual(list(outside.iterdir()), [])
                self.assertFalse((root / 'detached-output2' / metadata.CONFIG_FILE).exists())
                failure = json.loads((root / 'detached-output2' / metadata.RECEIPT).read_bytes())
                self.assertNotIn('config', failure['metadata'])
                self.assertEqual(failure['actions'][2]['status_code'], 200)
                self.assertEqual((output / metadata.RECEIPT).read_bytes(), receipt)
                child_called = root / 'forbidden-child-network'
                def child_replay():
                    def forbidden(*_args, **_kwargs):
                        child_called.write_text('attempted')
                        raise RuntimeError('Unexpected fake network replay')
                    factory.return_value.request.side_effect = forbidden
                    with self.assertRaises(Refused):
                        metadata.execute_action(execute)
                process = multiprocessing.get_context('fork').Process(target=child_replay)
                process.start()
                process.join(timeout=5)
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
                    self.fail('Synthetic registry replay process did not finish')
                self.assertEqual(process.exitcode, 0)
                self.assertFalse(child_called.exists())
                output.rename(root / 'old-output')
                output.mkdir(mode=0o700)
                manifest_path.write_bytes((root / 'old-output' / metadata.MANIFEST).read_bytes())
                with self.assertRaises(Refused):
                    metadata.execute_action(execute)
                self.assertEqual(factory.return_value.request.call_count, 3)


if __name__ == '__main__':
    unittest.main()

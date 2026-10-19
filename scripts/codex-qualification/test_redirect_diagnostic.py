"""Synthesized Location parsing and injected two-request transport only."""
import copy
import unittest
from unittest.mock import Mock, patch

import redirect_diagnostic as diagnostic
import test_registry_metadata as fixtures
from prepare import Refused, canonical, sha

LOCATION = ('https://UNREVIEWED.invalid:443/private/' + fixtures.IMAGE['image_id'] +
            '?capability=SYNTHESIZED_PRIVATE_QUERY')


class RedirectDiagnostic(unittest.TestCase):
    def setUp(self):
        fixtures.RegistryMetadata.setUp(self)
        self.platform = {'path': '/fixture/platform.json', 'sha256': sha(fixtures.PLATFORM),
                         'bytes': len(fixtures.PLATFORM), 'config_descriptor': {
                             'mediaType': 'application/vnd.oci.image.config.v1+json',
                             'digest': fixtures.IMAGE['image_id'], 'size': len(fixtures.CONFIG)}}
        self.manifest = diagnostic.action_manifest(retained_image=fixtures.IMAGE,
            platform_evidence=self.platform, **self.context)
        self.responses = [(200, 'application/json', canonical({'token': fixtures.TOKEN})),
                          (307, [('Location', LOCATION)], b'')]
        self.transport.request.side_effect = self.respond

    def respond(self, url, headers, *, timeout, maximum_bytes):
        self.gate.assert_called_once_with()
        index = [action['url'] for action in self.manifest['actions']].index(url)
        expected = dict(self.manifest['actions'][index]['headers'])
        if index:
            expected['Authorization'] = 'Bearer ' + fixtures.TOKEN
        self.assertEqual(headers, expected)
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)
        self.assertEqual(maximum_bytes, self.manifest['actions'][index]['maximum_bytes'])
        return copy.deepcopy(self.responses[index])

    def collector(self):
        return diagnostic.RedirectDiagnostic(self.manifest, self.transport, self.gate,
            manifest_sha256=sha(canonical(self.manifest)), clock=lambda: self.now,
            output_binding=self.output)

    def test_exact_two_requests_project_normalized_route_and_hashes_only(self):
        collector = self.collector()
        self.transport.request.assert_not_called()
        receipt = collector.collect()
        self.assertEqual(self.transport.request.call_count, 2)
        self.assertEqual([call.args[0] for call in self.transport.request.call_args_list],
                         [diagnostic.TOKEN_URL,
                          diagnostic.REGISTRY + 'blobs/' + fixtures.IMAGE['image_id']])
        self.assertEqual([action['method'] for action in self.manifest['actions']], ['GET', 'GET'])
        self.assertEqual(self.manifest['actions'][1]['permitted_status'], 307)
        self.assertEqual(self.manifest['actions'][1]['response_body'], 'never-read')
        self.assertEqual(receipt['status'], 'redirect-headers-observed')
        projected = receipt['routing']
        self.assertEqual(projected['scheme'], 'https')
        self.assertEqual(projected['hostname'], 'unreviewed.invalid')
        self.assertEqual(projected['route_class'], 'other-dns-host')
        self.assertEqual(projected['location_sha256'], sha(LOCATION.encode()))
        self.assertEqual(projected['location_bytes'], len(LOCATION.encode()))
        self.assertEqual(projected['path_sha256'], sha(('/private/' + fixtures.IMAGE['image_id']).encode()))
        self.assertEqual(projected['port'], 443)
        self.assertTrue(projected['query_present'])
        self.assertTrue(projected['expected_config_digest_in_path'])
        for sentinel in (LOCATION, 'UNREVIEWED.invalid', 'private/', 'SYNTHESIZED_PRIVATE_QUERY', fixtures.TOKEN):
            self.assertNotIn(sentinel.encode(), canonical(receipt))
        self.assertFalse(receipt['destination_authorized'])
        self.assertFalse(receipt['execute_authorized'])
        self.assertEqual(receipt['receipt_sha256'], sha(canonical(
            {key: value for key, value in receipt.items() if key != 'receipt_sha256'})))
        with self.assertRaises(Refused):
            collector.collect()
        self.assertEqual(self.transport.request.call_count, 2)

    def test_location_projection_rejects_unsafe_or_ambiguous_shapes(self):
        invalid = ['', 'http://example.invalid/x', '//example.invalid/x',
                   'https://name:password@example.invalid/x', 'https://example.invalid/x#fragment',
                   'https://example.invalid/x#', 'https://example.invalid:444/x',
                   'https://127.0.0.1/x', 'https://[::1]/x', 'https://example.invalid:/x',
                   'https://example.invalid../x',
                   'https://127.1/x', 'https://2130706433/x',
                   'https://example.invalid/x\r\nSecret: value', ' https://example.invalid/x',
                   'https://example.invalid/with space', 'https://example%2einvalid/x',
                   'https://example.invalid\\@other.invalid/x', 'https://-bad.invalid/x',
                   'https://example.invalid/' + 'a' * 8192]
        for value in invalid:
            with self.subTest(value_sha256=sha(value.encode())), self.assertRaises(Refused):
                diagnostic.project_location(value, fixtures.IMAGE['image_id'])
        projected = diagnostic.project_location('https://REGISTRY-1.DOCKER.IO./path', fixtures.IMAGE['image_id'])
        self.assertEqual(projected['hostname'], 'registry-1.docker.io')
        self.assertEqual(projected['route_class'], 'same-registry-host')
        self.assertFalse(projected['query_present'])
        self.assertFalse(projected['expected_config_digest_in_path'])
        empty_query = diagnostic.project_location('https://example.invalid/path?', fixtures.IMAGE['image_id'])
        self.assertTrue(empty_query['query_present'])
        with self.assertRaises(Refused):
            diagnostic.project_location('https://example.invalid/é', fixtures.IMAGE['image_id'])

    def test_status_duplicate_location_or_sensitive_failures_stop_with_fixed_receipt(self):
        cases = [(200, [('Location', LOCATION)], b''), (401, [], b''),
                 (302, [('Location', LOCATION)], b''), (307, [], b''),
                 (307, [('Location', LOCATION), ('location', LOCATION)], b''),
                 (307, [('Location', LOCATION + '#SYNTHESIZED_PRIVATE_FRAGMENT')], b''),
                 (307, [('Location', LOCATION)], b'SYNTHESIZED_PRIVATE_BODY')]
        for response in cases:
            self.setUp()
            self.responses[1] = response
            with self.subTest(status=response[0]), self.assertRaises(diagnostic.DiagnosticFailure) as raised:
                self.collector().collect()
            receipt = raised.exception.receipt
            self.assertEqual(receipt['request_count'], 2)
            self.assertEqual(receipt['actions'][1]['status_code'], response[0])
            self.assertNotIn('routing', receipt)
            self.assertNotIn(b'SYNTHESIZED_PRIVATE', canonical(receipt))
            self.assertNotIn(LOCATION.encode(), canonical(receipt))

    def test_adapter_reads_no_config_body_and_rejects_duplicate_or_unbounded_headers(self):
        for status, headers, reason in (
                (307, [('Location', LOCATION)], None), (200, [('Location', LOCATION)], None),
                (307, [('Location', LOCATION), ('Location', LOCATION)], 'header_shape'),
                (307, [('Location', LOCATION), ('X-Secret', 'a' * 32768)], 'header_shape')):
            with self.subTest(status=status, reason=reason), patch.object(diagnostic.metadata.ssl, 'SSLContext'), \
                    patch.object(diagnostic.metadata.http.client, 'HTTPSConnection') as connections:
                adapter = diagnostic.HTTPSAdapter(self.manifest, fixtures.CA,
                    manifest_sha256=sha(canonical(self.manifest)))
                connections.assert_not_called()
                response = connections.return_value.getresponse.return_value
                response.status, response.getheaders.return_value = status, headers
                action = self.manifest['actions'][1]
                arguments = (action['url'], {**action['headers'], 'Authorization': 'Bearer ' + fixtures.TOKEN})
                if reason:
                    with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
                        adapter.request(*arguments, timeout=10, maximum_bytes=action['maximum_bytes'])
                    self.assertEqual(raised.exception.reason, reason)
                else:
                    returned = adapter.request(*arguments, timeout=10, maximum_bytes=action['maximum_bytes'])
                    self.assertEqual(returned, (status, headers if status == 307 else [], b''))
                response.read.assert_not_called()
                response.read1.assert_not_called()
                response.close.assert_called_once()
                connections.return_value.close.assert_called_once()
                connections.assert_called_once()
                connections.return_value.request.assert_called_once()
                self.assertEqual(connections.call_args.args[:2], ('registry-1.docker.io', 443))
                self.assertEqual(connections.return_value.request.call_args.args[0], 'GET')

    def test_platform_bytes_require_raw_digest_and_exact_config_descriptor(self):
        self.assertEqual(diagnostic.verified_platform(fixtures.PLATFORM, fixtures.IMAGE),
                         {key: self.platform[key] for key in ('sha256', 'bytes', 'config_descriptor')})
        for raw in (fixtures.PLATFORM + b' ', b'{}'):
            with self.assertRaises(Refused):
                diagnostic.verified_platform(raw, fixtures.IMAGE)

    def test_execution_bindings_cover_attempt_manifest_digest_and_all_roles(self):
        inputs = {'attempt': self.context['attempt'],
                  'retained_manifest_sha256': self.context['retained_manifest_sha256'],
                  'image_refs': copy.deepcopy(self.context['image_refs'])}
        diagnostic.check_retained_bindings(self.manifest['context'], inputs)
        for field in ('attempt', 'retained_manifest_sha256', 'image_refs'):
            changed = copy.deepcopy(inputs)
            if field == 'image_refs':
                changed[field]['db'] += ':different'
            else:
                changed[field] += '-different'
            with self.subTest(field=field), self.assertRaises(Refused):
                diagnostic.check_retained_bindings(self.manifest['context'], changed)


if __name__ == '__main__':
    unittest.main()

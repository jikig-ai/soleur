"""Synthesized Location parsing and injected two-request transport only."""
import copy
import errno
import select
import unittest
from unittest.mock import patch

import redirect_diagnostic as diagnostic
import test_registry_metadata as fixtures
from prepare import Refused, canonical, sha

LOCATION = ('https://UNREVIEWED.invalid:443/private/' + fixtures.IMAGE['image_id'] +
            '?capability=SYNTHESIZED_PRIVATE_QUERY')


class TrickleSocket:
    def __init__(self, clock, payload, *, step=0.4):
        self.clock = clock
        self.payload = memoryview(payload)
        self.step = step
        self.blocked = False
        self.closed = False

    def setblocking(self, value):
        self.blocking = value

    def recv(self, amount):
        if not self.blocked:
            self.blocked = True
            raise BlockingIOError(errno.EAGAIN, 'synthetic would block')
        self.blocked = False
        if not self.payload:
            return b''
        self.clock.now += self.step
        result = bytes(self.payload[:min(1, amount)])
        self.payload = self.payload[len(result):]
        return result

    def send(self, value):
        self.clock.now += self.step
        return min(1, len(value))

    def close(self):
        self.closed = True

    def fileno(self):
        return 15


class Clock:
    def __init__(self, now=100):
        self.now = now

    def __call__(self):
        return self.now


class FakeTLSSocket(TrickleSocket):
    def __init__(self, response):
        super().__init__(Clock(), response, step=0)
        self.sent = bytearray()
        self.handshakes = 0

    def do_handshake(self):
        self.handshakes += 1

    def recv(self, amount):
        if not self.payload:
            return b''
        self.clock.now += self.step
        result = bytes(self.payload[:amount])
        self.payload = self.payload[len(result):]
        return result

    def send(self, value):
        self.sent.extend(value)
        return len(value)


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
        self.assertEqual(set(projected), {'scheme', 'hostname', 'port', 'location_sha256',
            'location_bytes', 'path_sha256', 'query_present', 'fragment_or_userinfo_present',
            'expected_config_digest_in_path'})
        self.assertEqual(projected['scheme'], 'https')
        self.assertEqual(projected['hostname'], 'unreviewed.invalid')
        self.assertEqual(projected['location_sha256'], sha(LOCATION.encode()))
        self.assertEqual(projected['location_bytes'], len(LOCATION.encode()))
        self.assertEqual(projected['path_sha256'], sha(('/private/' + fixtures.IMAGE['image_id']).encode()))
        self.assertEqual(projected['port'], 443)
        self.assertTrue(projected['query_present'])
        self.assertFalse(projected['fragment_or_userinfo_present'])
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
        self.assertEqual(set(projected), {'scheme', 'hostname', 'port', 'location_sha256',
            'location_bytes', 'path_sha256', 'query_present', 'fragment_or_userinfo_present',
            'expected_config_digest_in_path'})
        self.assertFalse(projected['query_present'])
        self.assertFalse(projected['fragment_or_userinfo_present'])
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
        cases = (
            (307, [('Location', LOCATION)], b'SYNTHETIC_PRIVATE_BODY', 1, None),
            (200, [('Content-Type', 'application/json'), ('Content-Length', '2')], b'{}', 0, None),
            (200, [('Content-Type', 'application/json'), ('Content-Length', '23')],
             b'SYNTHETIC_PRIVATE_BODY', 1, 'body_size'),
            (307, [('Location', LOCATION), ('Location', LOCATION)], b'', 1, 'header_shape'),
            (307, [('Location', LOCATION), ('X-Secret', 'a' * 32768)], b'', 1, 'header_shape'))
        for status, headers, body, action_index, reason in cases:
            with self.subTest(status=status, reason=reason), patch.object(diagnostic.metadata.ssl, 'SSLContext') as contexts, \
                    patch.object(diagnostic.socket, 'getaddrinfo', return_value=[
                        (diagnostic.socket.AF_INET, diagnostic.socket.SOCK_STREAM, 6, '', ('203.0.113.9', 443))]) as resolver, \
                    patch.object(diagnostic.socket, 'socket') as sockets:
                wire = FakeTLSSocket(b'HTTP/1.1 ' + str(status).encode() + b' Synthetic\r\n' +
                    b''.join(key.encode() + b': ' + value.encode('latin-1') + b'\r\n' for key, value in headers) +
                    b'\r\n' + body)
                contexts.return_value.wrap_socket.return_value = wire
                adapter = diagnostic.HTTPSAdapter(self.manifest, fixtures.CA,
                    manifest_sha256=sha(canonical(self.manifest)))
                raw_socket = sockets.return_value
                raw_socket.connect_ex.return_value = 0
                action = self.manifest['actions'][action_index]
                request_headers = dict(action['headers'])
                if action['bearer']:
                    request_headers['Authorization'] = 'Bearer ' + fixtures.TOKEN
                arguments = (action['url'], request_headers)
                if reason:
                    with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
                        adapter.request(*arguments, timeout=10, maximum_bytes=action['maximum_bytes'])
                    self.assertEqual(raised.exception.reason, reason)
                    if action_index == 1 and status == 200:
                        self.assertEqual(wire.payload.tobytes(), body)
                else:
                    returned = adapter.request(*arguments, timeout=10, maximum_bytes=action['maximum_bytes'])
                    expected = ((status, [('Location', LOCATION)], b'') if status == 307 else
                                (status, 'application/json', b'{}') if action_index == 0 else
                                (status, [], b''))
                    self.assertEqual(returned, expected)
                resolver.assert_called_once_with('registry-1.docker.io' if action_index else 'auth.docker.io',
                                                  443, type=diagnostic.socket.SOCK_STREAM)
                sockets.assert_called_once_with(diagnostic.socket.AF_INET, diagnostic.socket.SOCK_STREAM, 6)
                raw_socket.connect_ex.assert_called_once_with(('203.0.113.9', 443))
                raw_socket.close.assert_not_called()
                self.assertTrue(wire.closed)
                self.assertEqual(wire.handshakes, 1)
                if action_index:
                    self.assertTrue(bytes(wire.sent).startswith(b'GET /v2/axllent/mailpit/blobs/'))
                    self.assertIn(b'Authorization: Bearer ' + fixtures.TOKEN.encode(), bytes(wire.sent))
                else:
                    self.assertIn(b'GET /token?service=', bytes(wire.sent))
                    self.assertNotIn(b'Authorization:', bytes(wire.sent))
                if action_index == 1 and reason is None:
                    self.assertEqual(wire.payload.tobytes(), body)

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

    def test_https_header_reader_enforces_one_absolute_deadline_during_trickle(self):
        clock = Clock()
        deadline = clock.now + 1
        wire = TrickleSocket(clock, b'HTTP/1.1 307 Temporary Redirect\r\nLocation: https://example.invalid/x\r\n\r\n')
        with patch.object(select, 'select', side_effect=lambda r, w, x, timeout=None:
                          (wire.clock.__setattr__('now', wire.clock.now + min(0.4, timeout)) or
                           (list(r), list(w), []))):
            stream = diagnostic.DeadlineWire(wire, clock=clock, deadline=deadline)
            with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
                stream.read_headers()
        self.assertEqual(raised.exception.reason, 'deadline')

    def test_https_header_reader_caps_bytes_before_complete_parse(self):
        clock = Clock()
        wire = TrickleSocket(clock, b'HTTP/1.1 307 Redirect\r\nX: ' + b'a' * 500 + b'\r\n\r\n', step=0)
        with patch.object(select, 'select', side_effect=lambda r, w, x, timeout=None:
                          (list(r), list(w), [])):
            stream = diagnostic.DeadlineWire(wire, clock=clock, deadline=clock.now + 20,
                                              maximum_header_bytes=64)
            with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
                stream.read_headers()
        self.assertEqual(raised.exception.reason, 'header_shape')

    def test_https_header_reader_caps_count_as_lines_arrive(self):
        clock = Clock()
        payload = (b'HTTP/1.1 307 Redirect\r\n' +
                   b''.join(b'X: a\r\n' for _ in range(diagnostic.MAX_HEADER_COUNT + 1)) +
                   b'\r\n' + b'UNREAD')
        wire = TrickleSocket(clock, payload, step=0)
        with patch.object(select, 'select', side_effect=lambda r, w, x, timeout=None:
                          (list(r), list(w), [])):
            stream = diagnostic.DeadlineWire(wire, clock=clock, deadline=clock.now + 20)
            with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
                stream.read_headers()
        self.assertEqual(raised.exception.reason, 'header_shape')
        self.assertNotEqual(wire.payload.tobytes(), b'UNREAD')

    def test_https_sender_enforces_deadline_during_partial_writes(self):
        clock = Clock()
        wire = TrickleSocket(clock, b'', step=0.4)
        stream = diagnostic.DeadlineWire(wire, clock=clock, deadline=clock.now + 1)
        with self.assertRaises(diagnostic.metadata.BoundaryFailure) as raised:
            stream.send(b'GET /fixed HTTP/1.1\r\n' * 8)
        self.assertEqual(raised.exception.reason, 'deadline')


if __name__ == '__main__':
    unittest.main()

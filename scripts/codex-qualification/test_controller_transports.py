"""Contract tests using temporary synthetic Unix peers and deterministic mocks only."""
import copy
from contextlib import ExitStack
import errno
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import time
import traceback
import unittest
from unittest.mock import Mock, patch

import controller_transports as transports
import operational
from prepare import Refused, sha
from test_controller_adapters import contract, seal


LIMIT = 16 * 1024 ** 2
SENTINEL = 'SYNTHETIC_PRIVATE_PEER_CONTENT'


def bound_contract():
    value = contract()
    value['source_references']['scripts/codex-qualification/controller_transports.py'] = {
        'sha256': sha((Path(__file__).parent / 'controller_transports.py').read_bytes())}
    return seal(value)


def fixed(body=b'{"ok":true}', status=200, headers=()):
    lines = [f'HTTP/1.1 {status} Synthetic'.encode(),
             b'Content-Length: ' + str(len(body)).encode(), b'Content-Type: application/json']
    return b'\r\n'.join(lines + list(headers)) + b'\r\n\r\n' + body


def chunked(chunks):
    return (b'HTTP/1.1 200 Synthetic\r\nTransfer-Encoding: chunked\r\n'
            b'Content-Type: application/json\r\n\r\n' +
            b''.join(format(len(body), 'x').encode() + b'\r\n' + body + b'\r\n'
                     for body in chunks) + b'0\r\n\r\n')


class Clock:
    def __init__(self, now=100):
        self.now = now
        self.calls = 0
        self.script = []

    def __call__(self):
        self.calls += 1
        return self.script.pop(0) if self.script else self.now


class Peer:
    """One synthetic connection, bounded thread, checked errors and captured request."""
    def __init__(self, fragments, *, delay=0, linger=0):
        self.fragments = fragments
        self.delay = delay
        self.linger = linger
        self.received = b''
        self.errors = []
        self.client_disconnects = []
        self.connections = 0
        self.directory = tempfile.TemporaryDirectory(prefix='cq9051-peer-', dir='/tmp')
        self.listener = None
        initialized = False
        try:
            self.endpoint = str(Path(self.directory.name) / 'peer.sock')
            self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.listener.settimeout(2)
            self.listener.bind(self.endpoint)
            self.listener.listen(1)
            self.thread = threading.Thread(target=self.serve, daemon=True)
            self.thread.start()
            initialized = True
        finally:
            if not initialized:
                try:
                    if self.listener is not None:
                        self.listener.close()
                finally:
                    self.directory.cleanup()

    def serve(self):
        try:
            connection, _ = self.listener.accept()
            self.connections += 1
            with connection:
                connection.settimeout(2)
                length = None
                while length is None or len(self.received) < length:
                    data = connection.recv(4096)
                    if not data:
                        return
                    self.received += data
                    if b'\r\n\r\n' in self.received and length is None:
                        header, _ = self.received.split(b'\r\n\r\n', 1)
                        fields = header.split(b'\r\n')[1:]
                        sizes = [int(line.split(b':', 1)[1]) for line in fields
                                 if line.lower().startswith(b'content-length:')]
                        if len(sizes) != 1:
                            raise AssertionError('Synthetic request must have exactly one length')
                        length = len(header) + 4 + sizes[0]
                    if len(self.received) > LIMIT + 32768:
                        raise AssertionError('Synthetic request capture exceeded bound')
                for fragment in self.fragments:
                    if self.delay:
                        time.sleep(self.delay)
                    connection.sendall(fragment)
                if self.linger:
                    time.sleep(self.linger)
        except (BrokenPipeError, ConnectionResetError) as error:
            # Expected when the client refuses malformed or late synthetic data.
            self.client_disconnects.append(error.errno)
        except Exception as error:
            self.errors.append(error)

    def close(self):
        self.listener.close()
        self.thread.join(3)
        alive = self.thread.is_alive()
        self.directory.cleanup()
        if alive:
            raise AssertionError('Synthetic peer thread did not terminate')
        if self.errors:
            raise AssertionError('Synthetic peer error: ' + repr(self.errors))
        if self.client_disconnects and (self.connections != 1 or b'\r\n\r\n' not in self.received or
                any(number not in (errno.EPIPE, errno.ECONNRESET) for number in self.client_disconnects)):
            raise AssertionError('Synthetic peer disconnected outside a captured request')


class FakeSocket:
    """Public socket behavior; select waits advance the injected clock deterministically."""
    def __init__(self, clock, response, stalled=None, error=None):
        self.clock = clock
        self.response = memoryview(response)
        self.header_remaining = response.find(b'\r\n\r\n') + 4
        self.stalled = stalled
        self.error = error
        self.stage = 'connect'
        self.sent = b''
        self.closed = False
        self.blocking = None
        self.connect_calls = 0
        self.waits = []
        self.waited_stages = []
        self.would_block = set()
        self.write_sizes = []

    def setblocking(self, blocking):
        self.blocking = blocking

    def connect_ex(self, endpoint):
        self.connect_calls += 1
        if self.error == 'connect':
            raise OSError(SENTINEL)
        return errno.EINPROGRESS

    def connect(self, endpoint):
        self.connect_ex(endpoint)
        raise BlockingIOError(errno.EINPROGRESS, 'synthetic in progress')

    def getsockopt(self, *args):
        return 0

    def send(self, data):
        self.stage = 'send'
        if self.error == 'send':
            raise OSError(SENTINEL)
        if self.stalled == 'send':
            raise BlockingIOError(errno.EAGAIN, 'synthetic send stall')
        if 'send' not in self.would_block:
            self.would_block.add('send')
            raise BlockingIOError(errno.EAGAIN, 'synthetic send readiness')
        size = min(len(data), 13)
        self.sent += bytes(data[:size])
        self.write_sizes.append(size)
        return size

    def recv(self, size):
        self.stage = ('header' if self.header_remaining > 0 else
                      'body' if self.response else 'eof')
        if self.error == self.stage:
            raise OSError(SENTINEL)
        if self.stalled == self.stage:
            raise BlockingIOError(errno.EAGAIN, 'synthetic read stall')
        if self.stage not in self.would_block:
            self.would_block.add(self.stage)
            raise BlockingIOError(errno.EAGAIN, 'synthetic read readiness')
        if self.stage == 'header':
            size = min(size, self.header_remaining)
        data = bytes(self.response[:size])
        self.response = self.response[size:]
        if self.stage == 'header':
            self.header_remaining -= len(data)
        return data

    def fileno(self):
        return -1 if self.closed else 987654

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def readiness(self, readers, writers, exceptional, timeout=None):
        self.waits.append(timeout)
        self.waited_stages.append(self.stage)
        if self.stage == self.stalled:
            self.clock.now += timeout
            return [], [], []
        # Partial successful phases consume time, so subsequent waits must shrink.
        self.clock.now += min(0.001, timeout / 4)
        return list(readers), list(writers), []


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.value = bound_contract()

    def pending(self, value):
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertIs(value[field], False, field)
        self.assertEqual(value['issuer_verification'], 'pending')
        self.assertEqual(value['independent_review'], 'pending')
        self.assertEqual(value['runtime_evidence'], 'pending-synthetic-transport-tests-only')
        self.assertEqual(value['pairing_sha256'], self.value['pairing_sha256'])
        self.assertEqual(value['operational_sha256'], self.value['operational_sha256'])

    def peer_request(self, response, *, method='GET', path='/synthetic?x=1', payload=b'',
                     timeout=1, fragment_size=None, delay=0, linger=0):
        fragments = ([response] if fragment_size is None else
                     [response[index:index + fragment_size]
                      for index in range(0, len(response), fragment_size)])
        peer = Peer(fragments, delay=delay, linger=linger)
        self.addCleanup(peer.close)
        real_socket = socket.socket
        clients = []
        def client(*args, **kwargs):
            # accept() wraps the already-created peer FD through socket.socket too.
            if kwargs.get('fileno') is not None:
                return real_socket(*args, **kwargs)
            self.assertEqual(args[:2], (socket.AF_UNIX, socket.SOCK_STREAM))
            connection = real_socket(*args, **kwargs)
            clients.append(connection)
            return connection
        transport = transports.UnixJsonTransport(self.value, peer.endpoint)
        try:
            with patch.object(transports.socket, 'socket', side_effect=client):
                result = transport.request(method, path, payload, timeout=timeout)
        finally:
            self.assertEqual(len(clients), 1)
            self.assertTrue(all(connection.fileno() == -1 for connection in clients))
        self.pending(transport.snapshot())
        self.assertNotIn(peer.endpoint, repr(transport.snapshot()))
        self.assertNotIn(SENTINEL, repr(transport.snapshot()))
        return result, peer

    def refused_response(self, response):
        try:
            self.peer_request(response)
        except Refused as error:
            rendered = ''.join(traceback.format_exception(error))
            self.assertNotIn(SENTINEL, rendered)
            self.assertTrue(error.__suppress_context__)
            return
        self.fail('Malformed synthetic response was accepted')

    def test_constructor_has_no_socket_or_endpoint_operations_and_copies_contract(self):
        endpoint = '/tmp/nonexistent-synthetic.sock'
        clock = Mock(side_effect=AssertionError('constructor clock operation'))
        endpoint_calls = []
        def local_source_only(original):
            def guarded(path, *args, **kwargs):
                if not isinstance(path, int):
                    if os.fspath(path) == endpoint:
                        endpoint_calls.append(original.__name__)
                        raise OSError('synthetic endpoint I/O')
                return original(path, *args, **kwargs)
            return guarded
        factory = Mock(side_effect=AssertionError('constructor socket I/O'))
        with ExitStack() as stack:
            stack.enter_context(patch.object(transports.socket, 'socket', factory))
            for module, name in ((os, 'stat'), (os, 'lstat'), (os, 'open'), (io, 'open')):
                original = getattr(module, name)
                stack.enter_context(patch.object(module, name, side_effect=local_source_only(original)))
            transport = transports.UnixJsonTransport(self.value, endpoint, clock=clock)
        factory.assert_not_called()
        self.assertEqual(endpoint_calls, [])
        self.assertEqual(clock.call_count, 0)
        self.pending(transport.snapshot())
        before = copy.deepcopy(transport.snapshot())
        self.value['identity']['source_sha'] = 'caller mutation'
        transport.snapshot()['execute_authorized'] = True
        self.assertEqual(transport.snapshot(), before)

    def test_invalid_endpoint_and_source_substitution_refuse_without_socket(self):
        endpoints = ('', 'relative.sock', '\x00/tmp/x', '/tmp/../x', '/tmp/./x', '/tmp//x',
                     '/tmp/x\n', '/tmp/é', '/' + 'x' * 100, '@abstract', b'/tmp/x', None)
        with patch.object(transports.socket, 'socket',
                          side_effect=AssertionError('invalid constructor I/O')) as factory:
            for endpoint in endpoints:
                with self.subTest(endpoint=endpoint):
                    with self.assertRaises(Refused):
                        transports.UnixJsonTransport(self.value, endpoint)
                    factory.assert_not_called()
            for change in ('missing', 'stale', 'tampered'):
                value = copy.deepcopy(self.value)
                reference = 'scripts/codex-qualification/controller_transports.py'
                if change == 'missing':
                    del value['source_references'][reference]
                    seal(value)
                elif change == 'stale':
                    value['source_references'][reference]['sha256'] = '0' * 64
                    seal(value)
                else:
                    value['identity']['source_sha'] = 'b' * 40
                with self.subTest(change=change):
                    with self.assertRaises(Refused):
                        transports.UnixJsonTransport(value, '/tmp/synthetic.sock')
                    factory.assert_not_called()

    def test_exact_request_bytes_and_fragmented_fixed_json(self):
        payload = '{ "synthetic": "é" }'.encode('utf-8')
        result, peer = self.peer_request(fixed(), method='POST', path='/objects?name=fixture',
                                         payload=payload, fragment_size=1)
        self.assertEqual(result, (200, {'ok': True}))
        expected = (b'POST /objects?name=fixture HTTP/1.1\r\nHost: localhost\r\n'
                    b'Connection: close\r\nContent-Type: application/json\r\n'
                    b'Content-Length: ' + str(len(payload)).encode() + b'\r\n\r\n' + payload)
        self.assertEqual(peer.received, expected)
        self.assertEqual(peer.connections, 1)

    def test_fixed_chunked_empty_and_non_2xx_positive_controls(self):
        cases = [(fixed(), (200, {'ok': True})),
                 (fixed(b'', 204), (204, {})), (fixed(b'', 304), (304, {})),
                 (b'HTTP/1.1 200 Synthetic\r\nContent-Length: 0\r\n\r\n', (200, {})),
                 (b'HTTP/1.1 200 Synthetic\r\n\r\n', (200, {})),
                 (b'HTTP/1.1 204 Synthetic\r\n\r\n', (204, {})),
                 (b'HTTP/1.1 304 Synthetic\r\n\r\n', (304, {})),
                 (fixed(b'{"message":"synthetic"}', 409), (409, {'message': 'synthetic'})),
                 (b'HTTP/1.1 201 Synthetic\r\nTransfer-Encoding: chunked\r\n'
                  b'Content-Type: application/json; charset=utf-8\r\n\r\n'
                  b'4\r\n{"ok\r\n7\r\n":true}\r\n0\r\n\r\n', (201, {'ok': True})),
                 (b'HTTP/1.1 200 Synthetic\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n',
                  (200, {}))]
        for response, expected in cases:
            with self.subTest(response=response[:70]):
                result, _ = self.peer_request(response, fragment_size=3)
                self.assertEqual(result, expected)

    def test_invalid_request_and_budget_refuse_before_socket(self):
        transport = transports.UnixJsonTransport(self.value, '/tmp/synthetic.sock')
        cases = [('PUT', '/', b'', 1), ('get', '/', b'', 1), (True, '/', b'', 1),
                 ('GET', 'http://synthetic/', b'', 1), ('GET', '/', b'{}', 1),
                 ('DELETE', '/', b'{}', 1), ('POST', '/', bytearray(b'{}'), 1),
                 ('POST', '/', b'[]', 1), ('POST', '/', b'{"x":1,"x":2}', 1),
                 ('POST', '/', b'{"x":NaN}', 1), ('POST', '/', b'{"x":Infinity}', 1),
                 ('POST', '/', b'{"x":-Infinity}', 1), ('POST', '/', b'{"x":"\xff"}', 1),
                 ('POST', '/', b' ' * (LIMIT + 1), 1)]
        for path in ('', '/a b', '/a#b', '/a\\b', '/a\r\nX: x', '/é', '/' * 8193):
            cases.append(('GET', path, b'', 1))
        for timeout in (0, -1, True, float('inf'), float('nan'), None,
                        operational.BUDGET['work_seconds'] + 1):
            cases.append(('GET', '/', b'', timeout))
        with patch.object(transports.socket, 'socket',
                          side_effect=AssertionError('invalid request I/O')) as factory:
            for method, path, payload, timeout in cases:
                with self.subTest(method=method, path=str(path)[:20], timeout=timeout):
                    with self.assertRaises(Refused):
                        transport.request(method, path, payload, timeout=timeout)
                    factory.assert_not_called()

    def test_strict_json_duplicates_nonfinite_arrays_deep_and_invalid_utf8(self):
        bodies = [b'{"x":1,"x":2}', b'{"nested":{"x":1,"x":2}}', b'{"x":NaN}',
                  b'{"x":Infinity}', b'{"x":-Infinity}', b'[]', b'null', b'"object"',
                  b'{"x":"\xff"}', b'{"x":1} trailing', b'{"x":' * 2000 + b'0' + b'}' * 2000]
        for body in bodies:
            with self.subTest(body=body[:40]):
                self.refused_response(fixed(body))

    def test_array_payload_refuses_before_socket(self):
        transport = transports.UnixJsonTransport(self.value, '/tmp/synthetic.sock')
        with patch.object(transports.socket, 'socket',
                          side_effect=AssertionError('invalid array payload I/O')) as factory:
            with self.assertRaises(Refused):
                transport.request('POST', '/', b'[]', timeout=1)
            factory.assert_not_called()

    def test_duplicate_json_response_is_refused(self):
        self.refused_response(fixed(b'{"x":1,"x":2}'))

    def test_parseable_json_nesting_boundary(self):
        allowed = b'{"x":' * 128 + b'0' + b'}' * 128
        result, _ = self.mock_request(response=fixed(allowed))
        self.assertEqual(result[0], 200)
        nested = result[1]
        for _ in range(128):
            self.assertEqual(set(nested), {'x'})
            nested = nested['x']
        self.assertEqual(nested, 0)
        refused = b'{"x":' * 129 + b'0' + b'}' * 129
        with self.assertRaisesRegex(Refused, 'JSON nesting bound exceeded'):
            self.mock_request(response=fixed(refused))

    def test_parseable_chunk_count_boundary(self):
        response = chunked([b' '] * 4095 + [b'{}'])
        result, _ = self.mock_request(response=response)
        self.assertEqual(result, (200, {}))
        response = chunked([b' '] * 4096 + [b'{}'])
        with self.assertRaisesRegex(Refused, 'HTTP chunk count bound exceeded'):
            self.mock_request(response=response)

    def test_complete_valid_fixed_and_chunked_decoded_body_boundary(self):
        for size in (LIMIT, LIMIT + 1):
            body = b' ' * (size - 2) + b'{}'
            for encoding in ('fixed', 'chunked'):
                # Split the oversize chunked body at the bound: each individual
                # chunk is admissible and only their cumulative size exceeds it.
                response = fixed(body) if encoding == 'fixed' else chunked(
                    [body] if size == LIMIT else [body[:LIMIT], body[LIMIT:]])
                with self.subTest(size=size, encoding=encoding):
                    if size == LIMIT:
                        result, _ = self.mock_request(response=response)
                        self.assertEqual(result, (200, {}))
                    else:
                        with self.assertRaisesRegex(Refused, 'Unix JSON transport body bound exceeded'):
                            self.mock_request(response=response)

    def test_peer_initialization_failures_close_socket_and_cleanup_directory(self):
        for phase in ('bind', 'listen', 'start'):
            listener = Mock()
            directory = Mock(name='synthetic-directory')
            directory.name = '/tmp/synthetic-cq9051-peer'
            thread = Mock()
            getattr(listener if phase != 'start' else thread, phase).side_effect = OSError(SENTINEL)
            with patch.object(socket, 'socket', return_value=listener), \
                 patch.object(tempfile, 'TemporaryDirectory', return_value=directory), \
                 patch.object(threading, 'Thread', return_value=thread):
                with self.subTest(phase=phase):
                    with self.assertRaises(OSError):
                        Peer([fixed()])
                    listener.close.assert_called_once_with()
                    directory.cleanup.assert_called_once_with()

    def test_status_headers_and_framing_refusals(self):
        responses = [b'HTTP/1.0 200 Synthetic\r\nContent-Length: 0\r\n\r\n',
                     b'HTTP/1.1 100 Continue\r\n\r\n' + fixed(),
                     b'HTTP/1.1 101 Upgrade\r\nContent-Length: 0\r\n\r\n',
                     b'HTTP/1.1 600 Synthetic\r\nContent-Length: 0\r\n\r\n',
                     b'HTTP/1.1 200 Synthetic\nContent-Length: 0\n\n',
                     b'HTTP/1.1 200 Synthetic\r\n\r\n{}',
                     b'HTTP/1.1 200 Synthetic\r\nContent-Length: 02\r\n\r\n{}',
                     b'HTTP/1.1 200 Synthetic\r\nContent-Length: +2\r\n\r\n{}',
                     fixed(headers=(b'content-length: 11',)),
                     fixed(headers=(b'Transfer-Encoding: chunked',)),
                     fixed(headers=(b'Content-Encoding: gzip',)),
                     fixed(headers=(b'Connection: upgrade', b'Upgrade: synthetic')),
                     fixed(headers=(b'X-Test: one', b'x-test: two')),
                     fixed(headers=(b' X-Folded: value',)),
                     fixed(headers=(b'Bad Name: value',)), fixed(headers=(b'X-Control: \x01',)),
                     fixed(headers=(b'X-Private: ' + SENTINEL.encode() + b'\x00',)),
                     fixed(b'{}', 204), fixed(b'{}', 304),
                     b'HTTP/1.1 200 Synthetic\r\nContent-Length: 2\r\n\r\n{}',
                     fixed(headers=(b'Content-Type: text/plain',)),
                     b'HTTP/1.1 200 Synthetic\r\nContent-Length: 2\r\n'
                     b'Content-Type: application/json; charset=latin1\r\n\r\n{}',
                     fixed()[:-1], fixed() + b'trailing', fixed() + fixed(),
                     b'HTTP/1.1 200 Synthetic\r\nContent-Length: ' + str(LIMIT + 1).encode() + b'\r\n\r\n',
                     b'HTTP/1.1 200 Synthetic\r\nX: ' + b'x' * 32768 + b'\r\n\r\n',
                     b'HTTP/1.1 200 Synthetic\r\n' +
                     b''.join(b'X-' + str(i).encode() + b': a\r\n' for i in range(1025)) +
                     b'Content-Length: 0\r\n\r\n']
        for index, response in enumerate(responses):
            with self.subTest(case=index):
                self.refused_response(response)

    def test_chunk_encoding_bounds_trailers_and_contamination(self):
        prefix = (b'HTTP/1.1 200 Synthetic\r\nTransfer-Encoding: chunked\r\n'
                  b'Content-Type: application/json\r\n\r\n')
        chunks = [b'2;extension=x\r\n{}\r\n0\r\n\r\n', b'Z\r\n{}\r\n0\r\n\r\n',
                  b'2\r\n{}\n0\r\n\r\n', b'2\r\n{}\r\n0\r\nX: trailer\r\n\r\n',
                  b'1000001\r\n', b'F' * 8192 + b'\r\n', b'2\r\n{',
                  b'2\r\n{}\r\n0\r\n\r\nextra',
                  b'1\r\n \r\n' * 65537 + b'0\r\n\r\n']
        for index, chunk in enumerate(chunks):
            with self.subTest(case=index):
                self.refused_response(prefix + chunk)
        for encoding in (b'gzip', b'chunked, gzip', b'identity', b'Chunked, chunked'):
            self.refused_response(prefix.replace(b'chunked', encoding) + b'0\r\n\r\n')

    def mock_request(self, *, stalled=None, error=None, clock=None, response=None, timeout=0.1):
        clock = clock or Clock()
        fake = FakeSocket(clock, fixed() if response is None else response, stalled=stalled, error=error)
        transport = transports.UnixJsonTransport(self.value, '/tmp/synthetic.sock', clock=clock)
        factory = Mock(return_value=fake)
        with patch.object(transports.socket, 'socket', factory), \
             patch.object(transports.select, 'select', fake.readiness):
            try:
                result = transport.request('GET', '/synthetic', b'', timeout=timeout)
            finally:
                self.assertEqual(factory.call_count, 1)
                self.assertEqual(fake.connect_calls, 1)
                self.assertIs(fake.blocking, False)
                self.assertTrue(fake.closed)
                self.pending(transport.snapshot())
        return result, fake

    def test_full_deadline_covers_connect_send_header_body_and_eof_stalls(self):
        for stage in ('connect', 'send', 'header', 'body', 'eof'):
            with self.subTest(stage=stage), self.assertRaises(Refused):
                self.mock_request(stalled=stage)

    def test_readiness_uses_remaining_budget_and_no_retry(self):
        result, fake = self.mock_request()
        self.assertEqual(result, (200, {'ok': True}))
        self.assertGreaterEqual(len(fake.waits), 5)
        self.assertEqual(set(fake.waited_stages), {'connect', 'send', 'header', 'body', 'eof'})
        self.assertTrue(all(0 < wait <= 0.1 for wait in fake.waits))
        self.assertTrue(all(after < before for before, after in zip(fake.waits, fake.waits[1:])))
        self.assertGreater(len(fake.write_sizes), 1)
        self.assertTrue(all(0 < size <= 13 for size in fake.write_sizes))
        self.assertEqual(fake.sent, b'GET /synthetic HTTP/1.1\r\nHost: localhost\r\n'
                         b'Connection: close\r\nContent-Type: application/json\r\n'
                         b'Content-Length: 0\r\n\r\n')

    def test_finite_zero_clock_is_a_valid_monotonic_origin(self):
        result, _ = self.mock_request(clock=Clock(0))
        self.assertEqual(result, (200, {'ok': True}))

    def test_socket_failures_close_once_without_retry_or_peer_content(self):
        for stage in ('connect', 'send', 'header', 'body', 'eof'):
            try:
                self.mock_request(error=stage)
            except Refused as error:
                self.assertNotIn(SENTINEL, ''.join(traceback.format_exception(error)))
                self.assertTrue(error.__suppress_context__)
            else:
                self.fail('Synthetic ' + stage + ' socket error was accepted')

    def test_backward_nonfinite_and_boolean_clocks_refuse_before_socket(self):
        for value in (99, float('inf'), float('nan'), True):
            clock = Clock()
            transport = transports.UnixJsonTransport(self.value, '/tmp/synthetic.sock', clock=clock)
            clock.script = [100, value]
            with patch.object(transports.socket, 'socket',
                              side_effect=AssertionError('invalid clock I/O')) as factory:
                with self.subTest(value=value):
                    with self.assertRaises(Refused):
                        transport.request('POST', '/', b'{}', timeout=1)
                    factory.assert_not_called()

    def test_validation_and_response_json_parse_have_after_deadline_checks(self):
        original = json.loads
        for phase in ('request', 'response'):
            clock = Clock()
            transport = transports.UnixJsonTransport(self.value, '/tmp/synthetic.sock', clock=clock)
            fake = FakeSocket(clock, fixed())
            def late_parse(*args, **kwargs):
                parsed = original(*args, **kwargs)
                clock.now += 2
                return parsed
            factory = Mock(return_value=fake)
            with patch.object(transports.json, 'loads', side_effect=late_parse), \
                 patch.object(transports.socket, 'socket', factory), \
                 patch.object(transports.select, 'select', fake.readiness):
                with self.subTest(phase=phase), self.assertRaises(Refused):
                    transport.request('POST' if phase == 'request' else 'GET', '/',
                                      b'{}' if phase == 'request' else b'', timeout=1)
            self.assertEqual(factory.call_count, 0 if phase == 'request' else 1)
            if phase == 'response':
                self.assertTrue(fake.closed)

    def test_synthetic_trickle_and_eof_wait_share_original_deadline(self):
        start = time.monotonic()
        with self.assertRaises(Refused):
            self.peer_request(fixed(), timeout=0.07, fragment_size=1, delay=0.01)
        self.assertLess(time.monotonic() - start, 0.7)
        start = time.monotonic()
        with self.assertRaises(Refused):
            self.peer_request(fixed(), timeout=0.07, linger=0.15)
        self.assertLess(time.monotonic() - start, 0.7)


class GuardDiscriminator(unittest.TestCase):
    def test_array_normalization_causes_before_socket_behavioral_assertion_failure(self):
        original = json.loads
        def normalize_array(*args, **kwargs):
            result = original(*args, **kwargs)
            return {} if isinstance(result, list) else result
        result = unittest.TestResult()
        with patch.object(transports.json, 'loads', side_effect=normalize_array):
            TransportTests('test_array_payload_refuses_before_socket').run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.errors), 0)
        self.assertEqual(len(result.failures), 1)
        self.assertIn("Expected 'socket' to not have been called", result.failures[0][1])

    def test_duplicate_key_guard_removal_causes_behavioral_assertion_failure(self):
        original = json.loads
        def no_duplicate_guard(*args, **kwargs):
            kwargs.pop('object_pairs_hook', None)
            return original(*args, **kwargs)
        result = unittest.TestResult()
        with patch.object(transports.json, 'loads', side_effect=no_duplicate_guard):
            TransportTests('test_duplicate_json_response_is_refused').run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.errors), 0)
        self.assertEqual(len(result.failures), 1)
        self.assertIn('Malformed synthetic response was accepted', result.failures[0][1])


if __name__ == '__main__':
    unittest.main()

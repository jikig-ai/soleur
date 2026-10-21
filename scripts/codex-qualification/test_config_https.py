"""Synthetic Config transport boundaries; no resolver or origin is contacted."""
import importlib.util
import json
import io
import os
from pathlib import Path
import socket
import ssl
import signal
import tempfile
import time
import unittest
from unittest.mock import patch, Mock

try:
    import config_https as transport
except ModuleNotFoundError:
    transport = None


class FakeSocket:
    def __init__(self, response=b'', peer=('8.8.8.8', 443)):
        self.response = bytearray(response)
        self.peer = peer
        self.sent = bytearray()
        self.closed = False
        self.read_sizes = []
        self.peer_calls = 0

    def setblocking(self, _value):
        pass

    def connect_ex(self, address):
        self.address = address
        return 0

    def getpeername(self):
        self.peer_calls += 1
        return self.peer

    def send(self, value):
        self.sent.extend(value)
        return len(value)

    def recv(self, amount):
        self.read_sizes.append(amount)
        value = bytes(self.response[:amount])
        del self.response[:amount]
        return value

    def do_handshake(self):
        pass

    def selected_alpn_protocol(self):
        return 'http/1.1'

    def close(self):
        self.closed = True


def response(status=200, headers=None, body=b''):
    headers = headers or []
    return ('HTTP/1.1 ' + str(status) + ' Result\r\n' +
            ''.join(key + ': ' + value + '\r\n' for key, value in headers) + '\r\n').encode() + body


@unittest.skipIf(transport is None, 'implementation absent; required import checked separately')
class TransportTests(unittest.TestCase):
    def run_request(self, raw, role='destination', *, peer=('8.8.8.8', 443), location=None, bearer=None):
        sock = FakeSocket(raw, peer)
        context = Mock()
        context.wrap_socket.return_value = sock
        events = []
        with patch.object(transport, '_tls_context', return_value=context), \
                patch.object(transport, 'resolve_addresses', return_value=[[int(socket.AF_INET), '8.8.8.8', 443, 0, 0]]), \
                patch.object(transport.socket, 'socket', return_value=sock):
            client = transport.BoundedHTTPS(b'CA', transport.sha(b'CA'), clock=lambda: 1.0)
            try:
                result = client.request(role, location=(location or 'https://production.cloudfront.docker.com/p?a=%2F') if role == 'destination' else None,
                    bearer=bearer, deadline=11.0, observe=lambda event, value: events.append((event, value)))
            except Exception as error:
                result = error
        return result, sock, context, events

    def test_location_preserves_signed_target_and_rejects_authority_ambiguity(self):
        self.assertEqual(transport.checked_location('https://production.cloudfront.docker.com:443/a%2Fb?q=%3F'), '/a%2Fb?q=%3F')
        bad = ['http://production.cloudfront.docker.com/a', 'https://production.cloudfront.docker.com./a',
               'https://production.cloudfront.docker.com:0443/a', 'https://PRODUCTION.cloudfront.docker.com/a',
               'https://production.cloudfront.docker.com/a#', 'https://user@production.cloudfront.docker.com/a',
               'https://production.cloudfront.docker.com/a%2', 'https://production.cloudfront.docker.com',
               'https://production.cloudfront.docker.com/a\\b', 'https://production.cloudfront.docker.com/a\r\nX:x',
               'https://production.cloudfront.docker.com/a b', 'https://production.cloudfront.docker.com.evil/a',
               'https://production.cloudfront.docker.com/a' + 'x' * 4096]
        for value in bad:
            with self.subTest(value=value), self.assertRaises(transport.TransportRefused) as caught:
                transport.checked_location(value)
            self.assertEqual(caught.exception.code, 'location')
            self.assertNotIn(value, str(caught.exception))

    def test_address_set_refuses_special_mixed_scoped_and_overbudget(self):
        for ip in ['127.0.0.1', '10.0.0.1', '100.64.0.1', '169.254.1.1', '192.0.0.9', '192.88.99.1',
                   '224.0.0.1', '240.0.0.1', '::1', '::ffff:8.8.8.8', '64:ff9b::808:808',
                   '2001::1', '2002:0808:0808::1', 'fe80::1', 'ff02::1']:
            family = socket.AF_INET6 if ':' in ip else socket.AF_INET
            with self.subTest(ip=ip), self.assertRaises(transport.TransportRefused):
                transport.selected_address([[int(socket.AF_INET), '8.8.8.8', 443, 0, 0], [int(family), ip, 443, 0, 0]])
        for rows in ([], [[socket.AF_INET6, '2606:4700:4700::1111', 443, 0, 2]],
                     [[socket.AF_INET, '8.8.8.8', 443, 0, 0]] * 17):
            with self.assertRaises(transport.TransportRefused):
                transport.selected_address(rows)
        a = [int(socket.AF_INET), '8.8.8.8', 443, 0, 0]
        b = [int(socket.AF_INET), '1.1.1.1', 443, 0, 0]
        self.assertEqual(transport.selected_address([a, b]), transport.selected_address([b, a]))

    def test_destination_reads_exact_frame_without_eof_or_credential_forwarding(self):
        raw = response(headers=[('Content-Length', '2646'), ('Content-Type', 'application/octet-stream')], body=b'x' * 2646 + b'UNREAD')
        result, sock, context, events = self.run_request(raw)
        self.assertEqual(result, (200, b'x' * 2646))
        self.assertEqual(bytes(sock.response), b'UNREAD')
        self.assertEqual(events[-1], ('body_bytes', 2646))
        self.assertEqual(events.count(('send', None)), 1)
        self.assertGreaterEqual(sock.peer_calls, 2)
        self.assertIn(b'GET /p?a=%2F HTTP/1.1\r\n', sock.sent)
        for header in [b'Authorization', b'Cookie', b'Referer', b'Proxy-Authorization']:
            self.assertNotIn(header, sock.sent)
        self.assertTrue(sock.closed)
        self.assertEqual(context.wrap_socket.call_args.kwargs['server_hostname'], transport.DESTINATION)
        self.assertFalse(context.wrap_socket.call_args.kwargs['suppress_ragged_eofs'])

    def test_headers_and_status_refuse_before_body_reads(self):
        cases = [response(307, [('Location', 'https://evil/a')], b'CANARY'),
                 response(headers=[('Content-Length', '2645'), ('Content-Type', 'application/octet-stream')], body=b'CANARY'),
                 response(headers=[('Content-Length', '2646'), ('Content-Length', '2646'), ('Content-Type', 'application/octet-stream')], body=b'CANARY'),
                 response(headers=[('Content-Length', '2646'), ('Transfer-Encoding', 'chunked'), ('Content-Type', 'application/octet-stream')], body=b'CANARY'),
                 response(headers=[('Content-Length', '2646'), ('Content-Type', 'application/octet-stream; charset=utf-8')], body=b'CANARY'),
                 response(headers=[('Content-Length', '2646'), ('Content-Type', 'application/octet-stream'), ('Docker-Content-Digest', 'sha256:' + 'a' * 64)], body=b'CANARY')]
        for raw in cases:
            result, sock, _, _ = self.run_request(raw)
            self.assertIsInstance(result, transport.TransportRefused)
            self.assertEqual(bytes(sock.response), b'CANARY')
            self.assertNotIn('CANARY', str(result))

    def test_registry_is_header_only_and_bearer_never_leaks(self):
        url = 'https://production.cloudfront.docker.com/p?q=CANARY'
        result, sock, _, _ = self.run_request(response(307, [('Location', url)], b'UNREAD'), role='registry', bearer='abc.def')
        self.assertEqual(result, (307, url))
        self.assertEqual(bytes(sock.response), b'UNREAD')
        self.assertIn(b'Authorization: Bearer abc.def\r\n', sock.sent)
        result, sock, _, _ = self.run_request(response(200, [], b'UNREAD'), role='registry', bearer='abc.def')
        self.assertIsInstance(result, transport.TransportRefused)
        self.assertEqual(bytes(sock.response), b'UNREAD')

    def test_peer_mismatch_prevents_tls_and_send(self):
        result, sock, context, events = self.run_request(b'', peer=('1.1.1.1', 443))
        self.assertIsInstance(result, transport.TransportRefused)
        self.assertEqual(result.code, 'peer')
        context.wrap_socket.assert_not_called()
        self.assertFalse(sock.sent)
        self.assertNotIn(('send', None), events)

    def test_token_reviewed_length_chunked_clean_eof(self):
        for headers, body in [([('Content-Length', '2')], b'{}'),
                              ([('Transfer-Encoding', 'chunked')], b'2\r\n{}\r\n0\r\n\r\n'),
                              ([], b'{}')]:
            result, _, _, _ = self.run_request(response(headers=[('Content-Type', 'application/json')] + headers, body=body), role='token')
            self.assertEqual(result, (200, b'{}'))

    def test_tls_policy_uses_only_bound_ca_and_has_no_fallback(self):
        context = Mock()
        with patch.object(transport.ssl, 'SSLContext', return_value=context) as create, \
                patch.object(transport.metadata, '_certificate_pem', return_value='PINNED'):
            self.assertIs(transport._tls_context(b'CA', transport.sha(b'CA')), context)
        create.assert_called_once_with(ssl.PROTOCOL_TLS_CLIENT)
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertEqual(context.minimum_version, ssl.TLSVersion.TLSv1_2)
        context.load_verify_locations.assert_called_once_with(cadata='PINNED')
        context.load_default_certs.assert_not_called()
        with patch.object(transport.ssl, 'SSLContext') as create:
            with self.assertRaises(transport.TransportRefused) as caught:
                transport._tls_context(b'CA', '0' * 64)
            self.assertEqual(caught.exception.code, 'binding')
            create.assert_not_called()

    def test_second_peer_mismatch_and_certificate_failure_send_nothing(self):
        for tls_failure in (False, True):
            sock = FakeSocket()
            context = Mock()
            context.wrap_socket.side_effect = ssl.SSLCertVerificationError('CANARY') if tls_failure else None
            context.wrap_socket.return_value = sock
            if not tls_failure:
                sock.getpeername = Mock(side_effect=[('8.8.8.8', 443), ('1.1.1.1', 443)])
            events = []
            with patch.object(transport, '_tls_context', return_value=context), \
                    patch.object(transport, 'resolve_addresses', return_value=[[2, '8.8.8.8', 443, 0, 0]]), \
                    patch.object(transport.socket, 'socket', return_value=sock):
                client = transport.BoundedHTTPS(b'CA', transport.sha(b'CA'), clock=lambda: 1.0)
                with self.assertRaises(transport.TransportRefused) as caught:
                    client.request('token', deadline=11.0, observe=lambda *event: events.append(event))
            self.assertEqual(caught.exception.code, 'tls' if tls_failure else 'peer')
            self.assertFalse(sock.sent)
            self.assertNotIn(('send', None), events)
            self.assertNotIn('CANARY', str(caught.exception))
            self.assertTrue(sock.closed)

    def test_http10_interim_duplicate_encoding_and_header_budgets(self):
        base = [('Content-Length', '2646'), ('Content-Type', 'application/octet-stream')]
        cases = [response(headers=base).replace(b'HTTP/1.1', b'HTTP/1.0'), response(100),
                 response(headers=base + [('Content-Encoding', 'identity'), ('Content-Encoding', 'identity')]),
                 response(headers=base + [('X-' + str(i), 'x') for i in range(99)]),
                 response(headers=base + [('X', 'x' * 16384)]),
                 response(headers=base + [('X', 'x\x00CANARY')])]
        for raw in cases:
            result, sock, _, _ = self.run_request(raw + b'UNREAD')
            self.assertIsInstance(result, transport.TransportRefused)
            self.assertTrue(bytes(sock.response).endswith(b'UNREAD'))
            self.assertNotIn('CANARY', str(result))

    def test_truncated_destination_retains_only_partial_count(self):
        result, sock, _, events = self.run_request(response(headers=[('Content-Length', '2646'),
            ('Content-Type', 'application/octet-stream')], body=b'x' * 12))
        self.assertIsInstance(result, transport.TransportRefused)
        self.assertEqual(result.code, 'body')
        self.assertIn(('body_bytes', 12), events)
        self.assertNotIn(('body_bytes', 2646), events)
        self.assertTrue(sock.closed)

    def test_trickling_body_does_not_reset_deadline(self):
        sock = FakeSocket(response(headers=[('Content-Length', '2646'), ('Content-Type', 'application/octet-stream')], body=b'x' * 2646))
        now = [1.0]
        original = sock.recv

        def receive(amount):
            if amount > 1:
                now[0] += 6
                amount = 1
            return original(amount)

        sock.recv = receive
        context = Mock()
        context.wrap_socket.return_value = sock
        with patch.object(transport, '_tls_context', return_value=context), \
                patch.object(transport, 'resolve_addresses', return_value=[[2, '8.8.8.8', 443, 0, 0]]), \
                patch.object(transport.socket, 'socket', return_value=sock):
            client = transport.BoundedHTTPS(b'CA', transport.sha(b'CA'), clock=lambda: now[0])
            with self.assertRaises(transport.TransportRefused) as caught:
                client.request('destination', location='https://production.cloudfront.docker.com/a',
                    deadline=11.0, observe=lambda *_: None)
        self.assertEqual(caught.exception.code, 'deadline')
        self.assertTrue(sock.closed)

    def test_invalid_location_and_overlong_deadline_precede_dns(self):
        with patch.object(transport, '_tls_context', return_value=Mock()), \
                patch.object(transport, 'resolve_addresses') as resolve:
            client = transport.BoundedHTTPS(b'CA', transport.sha(b'CA'), clock=lambda: 1.0)
            for location, deadline in [('https://evil/a', 11), ('https://production.cloudfront.docker.com/a', 12)]:
                with self.assertRaises(transport.TransportRefused):
                    client.request('destination', location=location, deadline=deadline, observe=lambda *_: None)
            resolve.assert_not_called()

    def test_token_ambiguous_and_overflow_framing_closes_without_followup(self):
        cases = [([('Content-Length', '2'), ('Transfer-Encoding', 'chunked')], b'CANARY'),
                 ([('Transfer-Encoding', 'gzip')], b'CANARY'),
                 ([('Content-Length', '16385')], b'CANARY'),
                 ([('Transfer-Encoding', 'chunked')], b'2;ext=x\r\n{}\r\n0\r\n\r\n'),
                 ([('Transfer-Encoding', 'chunked')], b'2\r\n{}\r\n0\r\nX: CANARY\r\n\r\n'),
                 ([], b'x' * 16385)]
        for headers, body in cases:
            result, sock, _, _ = self.run_request(response(headers=[('Content-Type', 'application/json')] + headers,
                body=body), role='token')
            self.assertIsInstance(result, transport.TransportRefused)
            self.assertTrue(sock.closed)
            self.assertNotIn('CANARY', str(result))

    def test_tls_stall_and_backward_clock_are_deadline_refusals(self):
        for backwards in (False, True):
            sock = FakeSocket()
            now = [1.0]

            def handshake():
                now[0] = 0.0 if backwards else 11.0
                raise ssl.SSLWantReadError()

            sock.do_handshake = handshake
            context = Mock()
            context.wrap_socket.return_value = sock
            with patch.object(transport, '_tls_context', return_value=context), \
                    patch.object(transport, 'resolve_addresses', return_value=[[2, '8.8.8.8', 443, 0, 0]]), \
                    patch.object(transport.socket, 'socket', return_value=sock):
                client = transport.BoundedHTTPS(b'CA', transport.sha(b'CA'), clock=lambda: now[0])
                with self.assertRaises(transport.TransportRefused) as caught:
                    client.request('token', deadline=11, observe=lambda *_: None)
            self.assertEqual(caught.exception.code, 'deadline')
            self.assertFalse(sock.sent)
            self.assertTrue(sock.closed)


@unittest.skipIf(transport is None, 'implementation absent; required import checked separately')
class ResolverTests(unittest.TestCase):
    def process(self, returncode=0):
        process = Mock()
        process.stdout.fileno.return_value = 40
        process.poll.return_value = returncode
        process.wait.return_value = returncode
        return process

    def test_helper_process_contract_bounded_output_and_reaping(self):
        process = self.process()
        raw = json.dumps([[2, '8.8.8.8', 443, 0, 0]]).encode()
        with patch.object(transport.subprocess, 'Popen', return_value=process) as popen, \
                patch.object(transport.os, 'set_blocking'), \
                patch.object(transport.os, 'read', side_effect=[raw, b'']), \
                patch.object(transport.select, 'select', return_value=([process.stdout], [], [])):
            rows = transport.resolve_addresses('auth.docker.io', deadline=11, clock=lambda: 1.0)
        self.assertEqual(rows, [[2, '8.8.8.8', 443, 0, 0]])
        args, kwargs = popen.call_args
        self.assertEqual(args[0][1:4], ['-I', '-S', '-B'])
        self.assertTrue(Path(args[0][0]).is_absolute())
        self.assertEqual(args[0][-2:], ['auth.docker.io', str(os.getpid())])
        self.assertIs(kwargs['start_new_session'], False)
        self.assertEqual(kwargs['env'], {})
        self.assertTrue(kwargs['close_fds'])
        self.assertEqual(kwargs['stdin'], transport.subprocess.DEVNULL)
        self.assertEqual(kwargs['stderr'], transport.subprocess.DEVNULL)
        self.assertEqual(kwargs['cwd'], '/')
        self.assertNotIn('preexec_fn', kwargs)
        self.assertGreaterEqual(process.wait.call_count, 1)
        process.stdout.close.assert_called_once()

    def test_stalled_dns_is_killed_reaped_and_never_connects(self):
        process = self.process(None)
        with patch.object(transport.subprocess, 'Popen', return_value=process), \
                patch.object(transport.os, 'set_blocking'), \
                patch.object(transport.select, 'select', return_value=([], [], [])), \
                patch.object(transport.socket, 'socket') as connect:
            with self.assertRaises(transport.TransportRefused) as caught:
                transport.resolve_addresses('auth.docker.io', deadline=11, clock=lambda: 1.0)
        self.assertEqual(caught.exception.code, 'deadline')
        process.kill.assert_called_once()
        process.wait.assert_called_once()
        connect.assert_not_called()

    def test_real_sleeping_substitute_is_bounded_killed_and_reaped(self):
        # Copy the real implementation unchanged. Its sibling helper is a
        # synthesized sleeper with no resolver/network imports or operations.
        launched = []
        original_popen = transport.subprocess.Popen

        def capture(*args, **kwargs):
            process = original_popen(*args, **kwargs)
            launched.append(process)
            return process

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config_https.py'
            path.write_bytes(Path(transport.__file__).read_bytes())
            helper = Path(directory) / 'config_resolver.py'
            helper.write_text('import time\ntime.sleep(60)\n')
            spec = importlib.util.spec_from_file_location('sleeping_transport', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            started = time.monotonic()
            try:
                with patch.object(module.subprocess, 'Popen', side_effect=capture), \
                        patch.object(module.socket, 'getaddrinfo', side_effect=AssertionError('DNS forbidden')), \
                        patch.object(module.socket, 'socket', side_effect=AssertionError('socket forbidden')):
                    with self.assertRaises(module.TransportRefused) as caught:
                        module.resolve_addresses('auth.docker.io', deadline=started + 1.25, clock=time.monotonic)
                elapsed = time.monotonic() - started
                self.assertEqual(caught.exception.code, 'deadline')
                self.assertLess(elapsed, 1.25)
                self.assertEqual(len(launched), 1)
                child = launched[0]
                self.assertEqual(child.poll(), -signal.SIGKILL)
                self.assertTrue(child.stdout.closed)
                with self.assertRaises(ChildProcessError):
                    os.waitpid(child.pid, os.WNOHANG)
                # The helper shares this coordinator's process group; its own PID is reaped.
                with self.assertRaises(ProcessLookupError):
                    os.kill(child.pid, 0)
            finally:
                # A regression in the oracle must never leave the sleeper alive.
                for child in launched:
                    if child.poll() is None:
                        child.kill()
                    child.wait(timeout=1)
                    if child.stdout is not None:
                        child.stdout.close()

    def test_resolver_oversize_malformed_and_mixed_outputs_are_refused(self):
        for raw in [b'x' * 4097, b'CANARY', b'[[2,"8.8.8.8",443,0,0],[2,"127.0.0.1",443,0,0]]']:
            process = self.process(None)
            with patch.object(transport.subprocess, 'Popen', return_value=process), \
                    patch.object(transport.os, 'set_blocking'), \
                    patch.object(transport.os, 'read', side_effect=[raw, b'']), \
                    patch.object(transport.select, 'select', return_value=([process.stdout], [], [])):
                with self.assertRaises(transport.TransportRefused) as caught:
                    transport.resolve_addresses('auth.docker.io', deadline=11, clock=lambda: 1.0)
            self.assertEqual(caught.exception.code, 'dns')
            self.assertNotIn('CANARY', str(caught.exception))
            process.kill.assert_called_once()

    def test_helper_main_only_resolves_allowlisted_hostname(self):
        import config_resolver
        output = Mock()
        output.buffer = io.BytesIO()
        with patch.object(config_resolver.sys, 'argv', ['helper', 'auth.docker.io', str(os.getpid())]), \
                patch('resolver_supervisor.arm_parent_death') as arm, \
                patch.object(config_resolver.sys, 'stdout', output), \
                patch.object(config_resolver.socket, 'getaddrinfo', return_value=[
                    (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', 443))]) as resolve:
            self.assertEqual(config_resolver.main(), 0)
        self.assertEqual(json.loads(output.buffer.getvalue()), [[2, '8.8.8.8', 443, 0, 0]])
        resolve.assert_called_once()
        arm.assert_called_once_with(os.getpid())
        with patch.object(config_resolver.sys, 'argv', ['helper', 'CANARY']), \
                patch.object(config_resolver.socket, 'getaddrinfo') as resolve:
            self.assertEqual(config_resolver.main(), 1)
            resolve.assert_not_called()


    def test_helper_refuses_invalid_parent_before_arming_or_resolution(self):
        import config_resolver
        for parent in ('', '1', '0', '-2', '+123', ' 123', '123 ', '1.5', '１２３', '9' * 100):
            with self.subTest(parent=parent), \
                    patch.object(config_resolver.sys, 'argv', ['helper', 'auth.docker.io', parent]), \
                    patch('resolver_supervisor.arm_parent_death') as arm, \
                    patch.object(config_resolver.socket, 'getaddrinfo') as resolve:
                self.assertEqual(config_resolver.main(), 1)
                arm.assert_not_called()
                resolve.assert_not_called()

    def test_helper_refuses_parent_group_or_session_mismatch_before_resolution(self):
        import config_resolver
        for target in ('getpgid', 'getsid'):
            original = getattr(os, target)
            def mismatched(pid):
                return original(pid) + (1 if pid == os.getpid() else 0)
            with self.subTest(target=target), \
                    patch.object(config_resolver.sys, 'argv', ['helper', 'auth.docker.io', str(os.getpid())]), \
                    patch('resolver_supervisor.arm_parent_death'), \
                    patch.object(os, target, side_effect=mismatched), \
                    patch.object(config_resolver.socket, 'getaddrinfo') as resolve:
                self.assertEqual(config_resolver.main(), 1)
                resolve.assert_not_called()

    def test_helper_parent_race_and_arming_failure_prevent_resolution(self):
        import config_resolver
        for failure in (RuntimeError('parent changed'), OSError('prctl unavailable')):
            with patch.object(config_resolver.sys, 'argv', ['helper', 'auth.docker.io', str(os.getpid())]), \
                    patch('resolver_supervisor.arm_parent_death', side_effect=failure) as arm, \
                    patch.object(config_resolver.socket, 'getaddrinfo') as resolve:
                self.assertEqual(config_resolver.main(), 1)
                arm.assert_called_once_with(os.getpid())
                resolve.assert_not_called()

    def test_helper_import_or_prctl_failure_refuses_before_resolution(self):
        import builtins
        import config_resolver
        import resolver_supervisor
        original_import = builtins.__import__

        def refused_import(name, *args, **kwargs):
            if name == 'resolver_supervisor':
                raise ImportError('synthetic containment dependency unavailable')
            return original_import(name, *args, **kwargs)

        for guard in (patch('builtins.__import__', side_effect=refused_import),
                      patch.object(resolver_supervisor, '_prctl', side_effect=OSError('synthetic unavailable'))):
            with guard, \
                    patch.object(config_resolver.sys, 'argv', ['helper', 'auth.docker.io', str(os.getpid())]), \
                    patch.object(config_resolver.socket, 'getaddrinfo') as resolve:
                self.assertEqual(config_resolver.main(), 1)
                resolve.assert_not_called()


@unittest.skipIf(transport is None, 'implementation absent; required import checked separately')
class MutationTests(unittest.TestCase):
    def test_mutated_runtime_guards_are_detected_by_behavior(self):
        source = Path(transport.__file__).read_text()
        mutations = [
            ("parsed.netloc not in (DESTINATION, DESTINATION + ':443')", 'False', 'location'),
            ("names.get('content-length') != ['2646']", 'False', 'headers'),
            ("            _peer(connection, address)\n", '            pass\n', 'peer'),
            ("row[2:] != [443, 0, 0]", 'False', 'dns'),
        ]
        for index, (old, new, code) in enumerate(mutations):
            with self.subTest(guard=code), tempfile.TemporaryDirectory() as directory:
                # Each mutated fixture first proves the exact refusal on pristine
                # code. An internal error or different refusal is never a kill.
                self.assert_guard_behavior(transport, code, mutated=False)
                self.assertEqual(source.count(old), 1)
                path = Path(directory) / 'mutant.py'
                path.write_text(source.replace(old, new))
                spec = importlib.util.spec_from_file_location('mutant' + str(index), path)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                self.assert_guard_behavior(module, code, mutated=True)

    def assert_guard_behavior(self, module, code, *, mutated):
        if code == 'location':
            if mutated:
                self.assertEqual(module.checked_location('https://evil/a'), '/a')
            else:
                with self.assertRaises(module.TransportRefused) as caught:
                    module.checked_location('https://evil/a')
                self.assertEqual(caught.exception.code, 'location')
            return
        if code == 'dns':
            rows = [[10, '2606:4700:4700::1111', 443, 0, 2]]
            if mutated:
                self.assertEqual(module.selected_address(rows),
                    (socket.AF_INET6, ('2606:4700:4700::1111', 443, 0, 0)))
            else:
                with self.assertRaises(module.TransportRefused) as caught:
                    module.selected_address(rows)
                self.assertEqual(caught.exception.code, 'dns')
            return
        self.assert_request_guard_behavior(module, code, mutated=mutated)

    def assert_request_guard_behavior(self, module, code, *, mutated):
        self.assertIn(code, ('headers', 'peer'))
        body = b'x' * 2646
        sock = FakeSocket(response(headers=[('Content-Length', '2645' if code == 'headers' else '2646'),
            ('Content-Type', 'application/octet-stream')], body=body),
            peer=('1.1.1.1', 443) if code == 'peer' else ('8.8.8.8', 443))
        context = Mock()
        context.wrap_socket.return_value = sock
        if code == 'peer':
            def wrap(*_args, **_kwargs):
                sock.peer = ('8.8.8.8', 443)
                return sock
            context.wrap_socket.side_effect = wrap
        events = []
        with patch.object(module, '_tls_context', return_value=context), \
                patch.object(module, 'resolve_addresses', return_value=[[2, '8.8.8.8', 443, 0, 0]]), \
                patch.object(module.socket, 'socket', return_value=sock):
            client = module.BoundedHTTPS(b'CA', module.sha(b'CA'), clock=lambda: 1.0)
            result, caught = None, None
            try:
                result = client.request('destination', location='https://production.cloudfront.docker.com/a',
                    deadline=11, observe=lambda event, value: events.append((event, value)))
            except module.TransportRefused as error:
                caught = error.code
        self.assertTrue(sock.closed)
        if mutated:
            self.assertIsNone(caught)
            self.assertEqual(result, (200, body))
            context.wrap_socket.assert_called_once()
            self.assertEqual(events.count(('send', None)), 1)
            self.assertIn(('body_bytes', 2646), events)
            self.assertEqual(bytes(sock.response), b'')
        else:
            self.assertEqual(caught, code)
            self.assertIsNone(result)
            self.assertTrue(bytes(sock.response).endswith(body))
            self.assertFalse(any(event == 'body_bytes' for event, _ in events))
            if code == 'peer':
                context.wrap_socket.assert_not_called()
                self.assertNotIn(('send', None), events)

    def test_mutation_oracle_rejects_an_unrelated_internal_refusal(self):
        with patch.object(transport.Wire, 'read_headers', side_effect=transport.TransportRefused('internal')):
            # Exercise normal socket cleanup, then prove the oracle rejects
            # specifically the unrelated category rather than missing cleanup.
            with self.assertRaisesRegex(AssertionError, "'internal' is not None"):
                self.assert_request_guard_behavior(transport, 'headers', mutated=True)


class ImplementationRequired(unittest.TestCase):
    def test_transport_module_exists(self):
        self.assertIsNotNone(transport, 'Config transport source absent')


if __name__ == '__main__':
    unittest.main()

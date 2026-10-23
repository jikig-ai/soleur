"""Real task-CA handshakes and synthetic loopback HTTP; no application auth."""
import http.client
from pathlib import Path
import socket
import ssl
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch
import local_tls
from local_tls import Refused, material_recipe, generate_fixture_material, server_context, client_context
from local_tls import _TLSProxy as TLSProxy
from prepare import browser_contract


class LocalTLS(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='codex9051-tls-fixture-')
        cls.hostname = browser_contract()['url'].removeprefix('https://')
        cls.material = generate_fixture_material(Path(cls.temp.name) / 'tls', cls.hostname)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def handshake(self, hostname, trust=True):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(3)
        errors = []
        refusals = []
        received = []
        def server():
            try:
                connection, _ = listener.accept()
                with server_context(self.material, self.hostname).wrap_socket(connection, server_side=True) as tls:
                    received.append(tls.recv(1))
            except ssl.SSLError as error:
                refusals.append(error)
            except Exception as error:
                errors.append(error)
        worker = threading.Thread(target=server)
        worker.start()
        try:
            context = client_context(self.material['ca']) if trust else ssl.create_default_context()
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            with socket.create_connection(listener.getsockname(), timeout=3) as connection:
                with context.wrap_socket(connection, server_hostname=hostname) as tls:
                    tls.sendall(b'x')
        finally:
            worker.join(4)
            listener.close()
            self.assertFalse(worker.is_alive())
            self.assertEqual(errors, [])
            expected_refusal = not trust or hostname != self.hostname
            self.assertEqual(len(refusals), int(expected_refusal))
            self.assertEqual(received, [] if expected_refusal else [b'x'])

    def test_actual_ca_and_exact_sni(self):
        self.handshake(self.hostname)
        with self.assertRaises(ssl.SSLError):
            self.handshake(self.hostname, trust=False)
        with self.assertRaises(ssl.SSLError):
            self.handshake('other.supabase.co')

    def test_raw_proxy_constructor_is_private_to_fixtures(self):
        self.assertFalse(hasattr(local_tls, 'TLSProxy'))

    def test_material_is_scoped_and_recipe_never_insecure(self):
        recipe = material_recipe(self.hostname)
        self.assertEqual(recipe['san'], ['DNS:' + self.hostname])
        self.assertEqual(recipe['trust_scope'], ['owned-renderer-process', 'owned-browser-profile'])
        self.assertEqual(Path(self.material['key']).stat().st_mode & 0o777, 0o600)
        self.assertEqual(Path(self.material['ca_key']).stat().st_mode & 0o777, 0o600)
        self.assertEqual(recipe['browser_trust']['environment'], {'HOME': '/qualification/browser-home'})
        self.assertEqual(recipe['browser_trust']['nss_database'], 'sql:/qualification/browser-home/.pki/nssdb')
        with self.assertRaises(Refused):
            material_recipe('*.supabase.co')
        with self.assertRaises(Refused):
            material_recipe(self.hostname + '\nDNS:other.supabase.co')
        with self.assertRaises(Refused):
            material_recipe('z' * 20 + '.supabase.co')

    def test_leaf_hostname_validation_is_real(self):
        # Independent fixture server bypasses the exact-SNI callback, so OpenSSL's
        # client SAN check (rather than only our callback) must reject this name.
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(3)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.material['cert'], self.material['key'])
        errors = []
        refusals = []
        def serve():
            try:
                connection, _ = listener.accept()
                with context.wrap_socket(connection, server_side=True):
                    pass
            except ssl.SSLError as error:
                refusals.append(error)
            except Exception as error:
                errors.append(error)
        worker = threading.Thread(target=serve)
        worker.start()
        try:
            with socket.create_connection(listener.getsockname(), timeout=3) as connection:
                with self.assertRaises(ssl.SSLCertVerificationError):
                    client_context(self.material['ca']).wrap_socket(connection, server_hostname='other.supabase.co')
        finally:
            worker.join(4)
            listener.close()
            self.assertFalse(worker.is_alive())
            self.assertEqual(errors, [])
            self.assertEqual(len(refusals), 1)

    def test_http_boundary_has_no_general_proxy_or_redirect_escape(self):
        proxy = TLSProxy(self.hostname, '172.28.5.3', 8000)
        self.assertEqual(proxy.admit('GET', '/auth/v1/settings', [('Host', self.hostname)]), '/auth/v1/settings')
        self.assertEqual(proxy.admit('GET', '/auth/v1/caf\N{LATIN SMALL LETTER E WITH ACUTE}?next=r\N{LATIN SMALL LETTER E WITH ACUTE}sum\N{LATIN SMALL LETTER E WITH ACUTE}',
                                     [('Host', self.hostname)]),
                         '/auth/v1/caf%C3%A9?next=r%C3%A9sum%C3%A9')
        for method, path, headers in [
            ('CONNECT', self.hostname + ':443', [('Host', self.hostname)]),
            ('GET', 'https://foreign.invalid/', [('Host', self.hostname)]),
            ('GET', '//foreign.invalid/', [('Host', self.hostname)]),
            ('GET', '/', [('Host', 'foreign.invalid')]),
            ('GET', '/', [('Host', self.hostname), ('Host', self.hostname)]),
            ('GET', '/', [('Host', self.hostname), ('Upgrade', 'websocket')]),
            ('GET', '/', [('Host', self.hostname), ('Connection', 'authorization')]),
            ('GET', '/', [('Host', self.hostname), ('X-Forwarded-Port', '444')]),
            ('TRACE', '/', [('Host', self.hostname)]),
        ]:
            with self.assertRaises(Refused):
                proxy.admit(method, path, headers)
        for path in ['/admin/v1/users', '/metrics', '/auth/v1/../admin/v1/users',
                     '/auth/v1/%2e%2e/admin/v1/users']:
            with self.assertRaises(Refused):
                proxy.admit('GET', path, [('Host', self.hostname)])
        self.assertEqual(proxy.redirect('/auth/v1/settings'), '/auth/v1/settings')
        self.assertEqual(proxy.redirect('https://' + self.hostname + '/auth/v1/settings'),
                         'https://' + self.hostname + '/auth/v1/settings')
        for value in ['http://' + self.hostname + '/', 'https://foreign.invalid/', '//foreign.invalid/',
                      '/\\foreign.invalid/', 'https://' + self.hostname + ':444/', '/\r\nX: value']:
            with self.assertRaises(Refused):
                proxy.redirect(value)
        for ip in ['127.0.0.1', '8.8.8.8', 'kong', '169.254.169.254']:
            with self.assertRaises(Refused):
                TLSProxy(self.hostname, ip, 8000)

    def test_actual_https_listener_refuses_foreign_host_before_upstream(self):
        upstream = Mock(side_effect=OSError('Fixture forbids every upstream connection'))
        status, payload, _headers = self.https_response(b'GET / HTTP/1.0\r\nHost: foreign.invalid\r\n\r\n', upstream)
        self.assertEqual(status, 502)
        self.assertEqual(payload, b'')
        upstream.assert_not_called()

    def test_actual_https_listener_forwards_valid_host_to_strict_synthetic_response(self):
        payload = b'owned-synthetic-upstream-response'
        response = Mock(status=200)
        response.getheaders.return_value = [('Content-Type', 'text/plain')]
        response.read.return_value = payload
        connection = Mock()
        connection.getresponse.return_value = response
        upstream = Mock(return_value=connection)
        status, actual, headers = self.https_response(('GET /auth/v1/fixture_path?name=a%20b HTTP/1.0\r\nHost: ' + self.hostname +
                                             '\r\nConnection: close\r\n\r\n').encode(), upstream)
        self.assertEqual(status, 200)
        self.assertEqual(actual, payload)
        self.assertNotIn('X-Synthetic', headers)
        self.assertNotIn('Content-Type', headers)
        upstream.assert_called_once_with('172.28.5.3', 8000, timeout=5)
        connection.request.assert_called_once_with('GET', '/auth/v1/fixture_path?name=a%20b', b'',
                                                   {'Host': self.hostname, 'X-Forwarded-Proto': 'https'})
        connection.getresponse.assert_called_once_with()
        response.read.assert_called_once_with(TLSProxy.LIMIT + 1)
        connection.close.assert_called_once_with()

    def test_actual_https_listener_never_forwards_upstream_response_headers(self):
        response = Mock(status=200)
        response.getheaders.return_value = [('X-Synthetic', 'safe\r\nX-Injected: yes')]
        response.read.return_value = b''
        connection = Mock()
        connection.getresponse.return_value = response
        upstream = Mock(return_value=connection)
        status, payload, headers = self.https_response(('GET /auth/v1/fixture HTTP/1.0\r\nHost: ' + self.hostname +
                                              '\r\nConnection: close\r\n\r\n').encode(), upstream)
        self.assertEqual(status, 200)
        self.assertEqual(payload, b'')
        self.assertNotIn('X-Synthetic', headers)
        response.read.assert_called_once_with(TLSProxy.LIMIT + 1)
        response.getheaders.assert_not_called()
        connection.close.assert_called_once_with()

    def test_foreign_host_oracle_detects_deleted_handler_admission(self):
        # Compile an isolated in-memory mutant. The exercised listener still
        # uses the fail-on-construction mock, so no nonfixture socket can open.
        source = Path(local_tls.__file__).read_text()
        guard = '\n                    target = proxy.admit(self.command, self.path, list(self.headers.items()))\n'
        self.assertEqual(source.count(guard), 1)
        namespace = {'__name__': 'synthetic_tls_admission_mutant'}
        exec(compile(source.replace(guard, '\n'), '<synthetic-tls-admission-mutant>', 'exec'), namespace)
        result = unittest.TestResult()
        with patch.dict(globals(), {'TLSProxy': namespace['_TLSProxy']}):
            unittest.FunctionTestCase(self.test_actual_https_listener_refuses_foreign_host_before_upstream).run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.failures), 1)
        self.assertIn("Expected 'mock' to not have been called", result.failures[0][1])
        self.assertIn("call('172.28.5.3', 8000, timeout=5)", result.failures[0][1])

    def https_response(self, request, upstream):
        # Every upstream constructor is mocked for the complete server lifetime.
        # Even a deleted admission guard cannot contact the nonfixture address.
        server = TLSProxy(self.hostname, '172.28.5.3').make_server(('127.0.0.1', 0), self.material)
        errors = []
        def serve():
            try:
                server.handle_request()
            except Exception as error:
                errors.append(error)
        server.timeout = 3
        worker = threading.Thread(target=serve)
        with patch('local_tls.http.client.HTTPConnection', upstream):
            worker.start()
            try:
                with socket.create_connection(server.server_address, timeout=3) as raw:
                    with client_context(self.material['ca']).wrap_socket(raw, server_hostname=self.hostname) as connection:
                        connection.sendall(request)
                        response = http.client.HTTPResponse(connection)
                        response.begin()
                        result = response.status, response.read(), dict(response.getheaders())
                        response.close()
                        return result
            finally:
                worker.join(4)
                server.server_close()
                self.assertFalse(worker.is_alive())
                self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()

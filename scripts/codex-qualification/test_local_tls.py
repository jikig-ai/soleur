"""Real task-CA handshakes and synthetic loopback HTTP; no application auth."""
import http.client
from pathlib import Path
import socket
import ssl
import tempfile
import threading
import unittest
from local_tls import Refused, material_recipe, generate_fixture_material, server_context, client_context, TLSProxy
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
        def server():
            try:
                connection, _ = listener.accept()
                with server_context(self.material, self.hostname).wrap_socket(connection, server_side=True) as tls:
                    tls.recv(1)
            except ssl.SSLError:
                pass  # Expected peer/SNI certificate refusal; checked by client below.
            except Exception as error:
                errors.append(error)
        worker = threading.Thread(target=server)
        worker.start()
        try:
            context = client_context(self.material['ca']) if trust else ssl.create_default_context()
            with socket.create_connection(listener.getsockname(), timeout=3) as connection:
                with context.wrap_socket(connection, server_hostname=hostname) as tls:
                    tls.sendall(b'x')
        finally:
            worker.join(4)
            listener.close()
            self.assertFalse(worker.is_alive())
            self.assertEqual(errors, [])

    def test_actual_ca_and_exact_sni(self):
        self.handshake(self.hostname)
        with self.assertRaises(ssl.SSLError):
            self.handshake(self.hostname, trust=False)
        with self.assertRaises(ssl.SSLError):
            self.handshake('other.supabase.co')

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
        def serve():
            try:
                connection, _ = listener.accept()
                with context.wrap_socket(connection, server_side=True):
                    pass
            except ssl.SSLError:
                pass
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

    def test_http_boundary_has_no_general_proxy_or_redirect_escape(self):
        proxy = TLSProxy(self.hostname, '172.28.5.3', 8000)
        self.assertEqual(proxy.admit('GET', '/auth/v1/settings', [('Host', self.hostname)]), '/auth/v1/settings')
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
        server = TLSProxy(self.hostname, '172.28.5.3').make_server(('127.0.0.1', 0), self.material)
        errors = []
        def serve():
            try:
                server.handle_request()
            except Exception as error:
                errors.append(error)
        server.timeout = 3
        worker = threading.Thread(target=serve)
        worker.start()
        try:
            with socket.create_connection(server.server_address, timeout=3) as raw:
                with client_context(self.material['ca']).wrap_socket(raw, server_hostname=self.hostname) as connection:
                    connection.sendall(b'GET / HTTP/1.0\r\nHost: foreign.invalid\r\n\r\n')
                    response = http.client.HTTPResponse(connection)
                    response.begin()
                    self.assertEqual(response.status, 502)
                    self.assertEqual(response.read(), b'')
                    response.close()
        finally:
            worker.join(4)
            server.server_close()
            self.assertFalse(worker.is_alive())
            self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()

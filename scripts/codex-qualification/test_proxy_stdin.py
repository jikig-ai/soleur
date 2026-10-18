"""Prohibited upgraded stdin never reaches a task-owned fake Unix backend."""
import http.server
import errno
from pathlib import Path
import socket
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import api_proxy
from api_policy import Policy, Refused
from api_proxy import Proxy, UnixHTTPServer
from fixture_roles import fixture_profiles
from fixture_transport import receive_until

class Stdin(unittest.TestCase):
    def test_exec_halfclose_preserves_expected_disconnect_and_refuses_other_socket_errors(self):
        for error_number in (errno.ENOTCONN, errno.EBADF):
            proxy = SimpleNamespace(lock=threading.RLock(), deadline=time.monotonic() + 30,
                                    fatal=None, backend='/never-contacted', require_open=Mock())
            backend = Mock()
            backend.recv.side_effect = [b'HTTP/1.1 101 Synthetic\r\n\r\n', b'']
            front = Mock()
            front.shutdown.side_effect = OSError(error_number, 'SYNTHETIC_PRIVATE_SHUTDOWN_FAILURE')
            handler = SimpleNamespace(headers={}, command='POST', connection=front, close_connection=False)
            with self.subTest(error_number=error_number), \
                    patch.object(api_proxy.select, 'select', return_value=([backend], [], [])):
                if error_number == errno.ENOTCONN:
                    Proxy.hijack_owned(proxy, handler, '/exec/fixture/start', b'', backend)
                    self.assertTrue(handler.close_connection)
                    backend.close.assert_called_once()
                else:
                    with self.assertRaisesRegex(Refused, '^Exec stream half-close failed$') as caught:
                        Proxy.hijack_owned(proxy, handler, '/exec/fixture/start', b'', backend)
                    self.assertTrue(caught.exception.__suppress_context__)
                    self.assertNotIn('SYNTHETIC_', str(caught.exception))
            front.shutdown.assert_called_once_with(socket.SHUT_WR)

    def test_oracle_detects_deleted_stdin_guard(self):
        source = Path(api_proxy.__file__).read_text()
        guard = "                if source is front:\n                    raise Refused('Exec stdin is unavailable; source-bound mounted recipes required')\n"
        self.assertEqual(source.count(guard), 1)
        scope = {'__name__': 'synthetic_exec_stdin_mutant'}
        exec(compile(source.replace(guard, ''), '<synthetic-exec-stdin-mutant>', 'exec'), scope)
        result = unittest.TestResult()
        with patch.object(Proxy, 'hijack_owned', scope['Proxy'].hijack_owned):
            Stdin('test_upgraded_input_is_refused_before_backend_bytes').run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.failures), 1)
        self.assertIn('PROHIBITED-SYNTHETIC-INPUT', result.failures[0][1])

    def test_upgraded_input_is_refused_before_backend_bytes(self):
        with tempfile.TemporaryDirectory(prefix='codex9051-stdin-') as name:
            root = Path(name)
            received = []
            done = threading.Event()
            class Fake(http.server.BaseHTTPRequestHandler):
                protocol_version = 'HTTP/1.1'
                def log_message(self, *_): pass
                def do_POST(self):
                    self.rfile.read(int(self.headers['Content-Length']))
                    self.send_response(101)
                    self.send_header('Connection', 'Upgrade')
                    self.send_header('Upgrade', 'tcp')
                    self.end_headers()
                    self.wfile.write(b'fixture-ready\n')
                    self.wfile.flush()
                    self.connection.settimeout(5)
                    received.append(self.connection.recv(4096))
                    done.set()
                    self.close_connection = True
            backend = UnixHTTPServer(str(root/'backend.sock'), Fake)
            worker = threading.Thread(target=backend.serve_forever, daemon=True)
            worker.start()
            image = 'sha256:' + 'a'*64
            policy = Policy('fixture', 'fixture-internal', root, {image:image},
                            role_profiles=fixture_profiles('fixture', {image:image}))
            policy.ids.add('b'*64)
            policy.name_ids['supabase_db_fixture'] = 'b'*64
            policy.admit('POST', '/containers/'+'b'*64+'/exec', b'{"Cmd":["fixture"]}')
            policy.created_exec('c'*64, 'b'*64)
            proxy = Proxy(root/'proxy.sock', root/'backend.sock', policy, lifetime=15)
            proxy.start()
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as front:
                    front.settimeout(5)
                    front.connect(proxy.path)
                    body = b'{"Detach":false,"Tty":false}'
                    headers = ('POST /exec/'+'c'*64+'/start HTTP/1.1\r\nHost: fixture\r\n'
                               'Connection: Upgrade\r\nUpgrade: tcp\r\nContent-Length: '+str(len(body))+'\r\n\r\n').encode()
                    front.sendall(headers+body)
                    response = receive_until(front, b'fixture-ready\n')
                    self.assertTrue(response.startswith(b'HTTP/1.1 101'))
                    front.sendall(b'PROHIBITED-SYNTHETIC-INPUT')
                    self.assertTrue(done.wait(5), 'Backend did not close after refusal')
                    self.assertEqual(received, [b''])
                    # Backend EOF occurs while hijack unwinds, before fail()
                    # publishes fatal. Frontend EOF follows the final refusal.
                    total = 0
                    while True:
                        block = front.recv(4096)
                        if not block:
                            break
                        total += len(block)
                        self.assertLessEqual(total, 8192, 'Unbounded synthetic refusal response')
                    self.assertIsNotNone(proxy.fatal)
                    self.assertIn('Exec stdin is unavailable', proxy.fatal)
            finally:
                proxy.stop()
                backend.shutdown()
                backend.server_close()
                worker.join(5)
                self.assertFalse(worker.is_alive())
                self.assertEqual(backend.errors, [])
                self.assertEqual(proxy.server.errors, [])

if __name__ == '__main__':
    unittest.main()

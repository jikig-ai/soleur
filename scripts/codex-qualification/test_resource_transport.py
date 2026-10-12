"""Hostile resource ownership responses at a fake private Unix backend only."""
import http.server
import json
from pathlib import Path
import tempfile
import threading
import unittest
from api_policy import Policy
from api_proxy import Proxy, UnixHTTPServer, UnixConnection

IMAGE = 'sha256:' + 'a' * 64
NETWORK_ID = 'b' * 64
VOLUME = 'supabase_db_fixture'

class ResourceTransport(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='codex9051-resources-')
        self.root = Path(self.directory.name)
        self.requests = []
        self.volume = None
        self.network = None
        outer = self
        class Fake(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'
            def log_message(self, *_): pass
            def reply(self, code, value):
                data = b'' if code == 204 else json.dumps(value).encode()
                self.send_response(code)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                if data:
                    self.wfile.write(data)
            def do_GET(self):
                outer.requests.append(('GET', self.path))
                value = outer.volume if self.path.startswith('/volumes/') else outer.network
                self.reply(200 if value else 404, value or {})
            def do_POST(self):
                data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
                outer.requests.append(('POST', self.path))
                if self.path == '/volumes/create':
                    if outer.volume is None:
                        outer.volume = {**data, 'Scope': 'local', 'CreatedAt': '2026-10-12T12:00:00Z', 'Options': {}}
                    self.reply(201, outer.volume)
                elif self.path == '/networks/create':
                    outer.network = {**data, 'Id': NETWORK_ID}
                    self.reply(201, {'Id': NETWORK_ID})
                elif self.path.startswith('/containers/create'):
                    self.reply(201, {'Id': 'c' * 64})
                else:
                    self.reply(400, {})
            def do_DELETE(self):
                outer.requests.append(('DELETE', self.path))
                self.reply(204, {})
        self.backend = UnixHTTPServer(str(self.root / 'backend.sock'), Fake)
        self.thread = threading.Thread(target=self.backend.serve_forever, daemon=True)
        self.thread.start()
        self.policy = Policy('fixture', 'fixture-internal', self.root, {IMAGE: IMAGE})
        self.proxy = Proxy(self.root / 'proxy.sock', self.root / 'backend.sock', self.policy, lifetime=20)
        self.proxy.start()

    def tearDown(self):
        self.proxy.stop()
        self.backend.shutdown()
        self.backend.server_close()
        self.thread.join(timeout=5)
        self.directory.cleanup()
        self.assertEqual(self.backend.errors, [], 'Fake backend thread failed')
        self.assertEqual(self.proxy.server.errors, [], 'Proxy thread failed')

    def request(self, method, path, body=None):
        connection = UnixConnection(self.proxy.path)
        connection.request(method, path, json.dumps(body).encode() if body else None)
        response = connection.getresponse()
        status = response.status
        response.read()
        connection.close()
        return status

    def create(self, kind, name):
        return self.request('POST', '/' + kind + '/create', {
            'Name': name, 'Labels': {'com.supabase.cli.project': 'fixture'},
        })

    def test_reserved_volume_delete_never_reaches_backend(self):
        self.assertEqual(self.request('DELETE', '/volumes/' + VOLUME), 403)
        self.assertEqual(self.requests, [])

    def test_preexisting_volume_is_not_adopted(self):
        self.volume = {'Name': VOLUME, 'Labels': {'foreign': 'synthetic'}}
        self.assertEqual(self.create('volumes', VOLUME), 403)
        self.assertEqual(self.requests, [('GET', '/volumes/' + VOLUME)])
        self.assertEqual(self.policy.volume_receipts, {})

    def test_registered_volume_is_checked_then_removed(self):
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.assertIn(VOLUME, self.policy.volume_receipts)
        self.assertEqual(self.request('DELETE', '/volumes/' + VOLUME), 204)
        self.assertEqual(self.requests[-2:], [('GET', '/volumes/' + VOLUME), ('DELETE', '/volumes/' + VOLUME)])
        self.assertEqual(self.policy.volume_receipts, {})

    def test_replaced_volume_cannot_be_deleted(self):
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.volume['CreatedAt'] = 'foreign-replacement'
        self.assertEqual(self.request('DELETE', '/volumes/' + VOLUME), 403)
        self.assertFalse(any(method == 'DELETE' for method, _ in self.requests))

    def test_network_cleanup_resolves_id_and_checks_isolation(self):
        self.assertEqual(self.create('networks', 'fixture-internal'), 201)
        self.assertEqual(self.request('DELETE', '/networks/fixture-internal'), 204)
        self.assertEqual(self.requests[-2:], [('GET', '/networks/' + NETWORK_ID), ('DELETE', '/networks/' + NETWORK_ID)])
        self.assertIsNone(self.policy.network_id)

    def test_altered_network_isolation_blocks_cleanup(self):
        self.assertEqual(self.create('networks', 'fixture-internal'), 201)
        self.network['Internal'] = False
        self.assertEqual(self.request('DELETE', '/networks/fixture-internal'), 403)
        self.assertFalse(any(method == 'DELETE' for method, _ in self.requests))

    def test_fatal_attempt_can_clean_owned_volume_without_reopening_execution(self):
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.assertEqual(self.request('POST', '/containers/foreign/start'), 403)
        self.assertIsNotNone(self.proxy.fatal)
        self.proxy.begin_cleanup()
        before = len(self.requests)
        self.assertEqual(self.create('networks', 'fixture-internal'), 403)
        self.assertEqual(self.request('POST', '/containers/foreign/start'), 403)
        self.assertEqual(len(self.requests), before)
        self.assertEqual(self.request('DELETE', '/volumes/' + VOLUME), 204)
        self.assertEqual(self.policy.volume_receipts, {})

    def mount(self):
        return self.request('POST', '/containers/create?name=supabase_db_fixture', {
            'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'},
            'HostConfig': {'Binds': [VOLUME + ':/var/lib/postgresql/data']},
        })

    def test_owned_mount_verifies_volume_and_network(self):
        self.assertEqual(self.create('networks', 'fixture-internal'), 201)
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.assertEqual(self.mount(), 201)
        self.assertEqual(self.requests[-3:][0:2], [('GET', '/networks/' + NETWORK_ID), ('GET', '/volumes/' + VOLUME)])

    def test_replaced_volume_is_rejected_before_mount(self):
        self.assertEqual(self.create('networks', 'fixture-internal'), 201)
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.volume['CreatedAt'] = 'foreign-replacement'
        self.assertEqual(self.mount(), 403)
        self.assertFalse(any(path.startswith('/containers/create') for _, path in self.requests))

    def test_changed_network_is_rejected_before_container_create(self):
        self.assertEqual(self.create('networks', 'fixture-internal'), 201)
        self.assertEqual(self.create('volumes', VOLUME), 201)
        self.network['Internal'] = False
        self.assertEqual(self.mount(), 403)
        self.assertFalse(any(path.startswith('/containers/create') for _, path in self.requests))

if __name__ == '__main__':
    unittest.main()

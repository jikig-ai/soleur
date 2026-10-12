"""Offline Unix HTTP and Docker exec-hijack fixtures; never opens a Docker socket."""
import http.server
import json
from pathlib import Path
import socket
import tempfile
import threading
from api_policy import Policy
from fixture_roles import fixture_profiles, fixture_image
from api_proxy import Proxy, UnixHTTPServer, UnixConnection
from fixture_transport import receive_until

with tempfile.TemporaryDirectory(prefix='codex9051-api-fixture-') as directory:
    root = Path(directory)
    image = 'sha256:' + 'a' * 64
    container_id = 'b' * 64
    exec_id = 'c' * 64
    received = []
    class Fake(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def log_message(self, *_): pass
        def do_GET(self):
            received.append(('GET', self.path, None))
            body = json.dumps([] if '/containers/json' in self.path else {'fixture': True}).encode()
            if self.path.startswith('/networks/'):
                body = json.dumps({'Id': 'd' * 64, 'Name': 'fixture-internal', 'Driver': 'bridge',
                    'Internal': True, 'EnableIPv6': False, 'Labels': {'soleur.recovery.attempt': 'fixture'}}).encode()
            if self.path.startswith('/images/'):
                body = json.dumps(fixture_image(image)).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            received.append(('POST', self.path, json.loads(body) if body else None))
            if self.path.endswith('/start'):
                self.send_response(101)
                self.send_header('Connection', 'Upgrade')
                self.send_header('Upgrade', 'tcp')
                self.end_headers()
                self.wfile.write(b'fixture-ready\n')
                self.wfile.flush()
                self.wfile.write(b'fixture-reply:OUTPUT\n')
                self.wfile.flush()
                self.close_connection = True
                return
            payload = json.dumps({'Id': exec_id if self.path.endswith('/exec') else container_id}).encode()
            self.send_response(201)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
    backend = UnixHTTPServer(str(root / 'fake.sock'), Fake)
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()
    p = Policy('fixture', 'fixture-internal', root, {image: image},
               role_profiles=fixture_profiles('fixture', {image: image}))
    p.admit('POST', '/networks/create', json.dumps({'Name': p.network,
            'Labels': {'com.supabase.cli.project': p.project}}).encode())
    p.created_network(p.network, {'Id': 'd' * 64})
    proxy = Proxy(root / 'proxy.sock', root / 'fake.sock', p, lifetime=20)
    proxy.start()
    try:
        c = UnixConnection(str(root / 'proxy.sock'))
        config = {'Image': image, 'Labels': {'com.supabase.cli.project': 'fixture'},
                  'HostConfig': {'ExtraHosts': ['host.docker.internal:host-gateway']}}
        c.request('POST', '/containers/create?name=supabase_db_fixture', json.dumps(config))
        result = c.getresponse()
        assert result.status == 201 and json.loads(result.read())['Id'] == container_id
        assert container_id in p.ids
        assert received[-1][2]['HostConfig']['Memory'] == 1024**3
        assert received[-1][2]['HostConfig']['ExtraHosts'] == []
        c.close()
        c = UnixConnection(str(root / 'proxy.sock'))
        c.request('POST', '/containers/' + container_id + '/exec', json.dumps({'Cmd': ['fixture']}))
        assert json.loads(c.getresponse().read())['Id'] == exec_id
        assert exec_id in p.exec_ids
        c.close()
        front = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        front.settimeout(5)
        front.connect(str(root / 'proxy.sock'))
        payload = b'{"Detach":false,"Tty":false}'
        request = ('POST /exec/' + exec_id + '/start HTTP/1.1\r\nHost: fixture\r\n'
                   'Connection: Upgrade\r\nUpgrade: tcp\r\nContent-Length: ' + str(len(payload)) + '\r\n\r\n').encode()
        front.sendall(request + payload)
        data = receive_until(front, b'fixture-ready\n')
        assert data.startswith(b'HTTP/1.1 101') and b'fixture-ready\n' in data
        if b'fixture-reply:OUTPUT\n' not in data:
            data += receive_until(front, b'fixture-reply:OUTPUT\n')
        assert b'fixture-reply:OUTPUT\n' in data
        front.close()
        c = UnixConnection(str(root / 'proxy.sock'))
        c.request('GET', '/containers/json?all=true&filters=%7B%7D')
        assert c.getresponse().read() == b'[]'
        assert 'fixture' in received[-1][1] and 'com.supabase.cli.project' in received[-1][1]
        c.close()
        before = len(received)
        c = UnixConnection(str(root / 'proxy.sock'))
        c.request('POST', '/images/create?fromImage=ubuntu')
        response = c.getresponse()
        assert response.status == 403
        response.read()
        c.close()
        assert len(received) == before and proxy.fatal
        print(json.dumps({'transport_checks': 7, 'docker_calls': 0,
                          'http_upgrade_and_output_only_exec': 'pass', 'pull_refusal': 'pass'}))
    finally:
        proxy.stop()
        backend.shutdown()
        backend.server_close()
        backend_thread.join(timeout=5)
        assert not backend.errors and not proxy.server.errors, 'Fake transport thread failed'

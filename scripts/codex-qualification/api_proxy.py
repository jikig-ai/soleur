"""Private Unix Docker API proxy. Transport tests use a fake Unix backend only."""
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import select
import socket
import socketserver
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit
from api_policy import Refused, MissingOwnedContainer

MAX_BODY = 16 * 1024**2
HOP_HEADERS = {'connection', 'transfer-encoding', 'keep-alive', 'proxy-authenticate',
               'proxy-authorization', 'te', 'trailer', 'upgrade'}

class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__('localhost', timeout=45)
        self.path = path
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)

class UnixHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    address_family = socket.AF_UNIX
    daemon_threads = True
    def __init__(self, *args, **kwargs):
        self.errors = []
        super().__init__(*args, **kwargs)
    def handle_error(self, request, client_address):
        self.errors.append(sys.exc_info()[0].__name__)
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = 'task-owned-unix'
        self.server_port = 0

class Proxy:
    def __init__(self, path, backend, policy, lifetime=1800):
        self.path = str(path)
        self.backend = str(backend)
        self.policy = policy
        self.lock = threading.RLock()
        self.fatal = None
        self.cleanup_only = False
        self.audit = []
        self.deadline = time.monotonic() + lifetime
        if Path(path).exists():
            raise Refused('Private task socket already exists')
        outer = self
        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'
            def log_message(self, *_):
                pass
            def do_GET(self): outer.handle(self)
            def do_HEAD(self): outer.handle(self)
            def do_POST(self): outer.handle(self)
            def do_DELETE(self): outer.handle(self)
        self.server = UnixHTTPServer(self.path, Handler)
        os.chmod(self.path, 0o600)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def begin_cleanup(self):
        """Controller-only transition; client HTTP cannot release a failure gate."""
        with self.lock:
            self.cleanup_only = True
            self.deadline = time.monotonic() + 300

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        Path(self.path).unlink(missing_ok=True)

    def fail(self, handler, message):
        with self.lock:
            self.fatal = message
        body = json.dumps({'message': 'Recovery boundary refused: ' + message}).encode()
        handler.send_response(403)
        handler.send_header('Content-Type', 'application/json')
        handler.send_header('Content-Length', str(len(body)))
        handler.send_header('Connection', 'close')
        handler.end_headers()
        handler.wfile.write(body)
        handler.close_connection = True

    def absent(self, handler):
        body = b'{"message":"No registered owned container"}'
        handler.send_response(404)
        handler.send_header('Content-Type','application/json')
        handler.send_header('Content-Length',str(len(body)))
        handler.send_header('Connection','close')
        handler.end_headers()
        handler.wfile.write(body)
        handler.close_connection = True

    def observe(self, method, path, status, body):
        route = re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(path).path)
        if method == 'POST' and route in ('/networks/create', '/volumes/create'):
            if status != 201:
                self.fatal = 'Resource creation failed; no ownership granted'
                return
            receipt = json.loads(body)
            if route == '/networks/create':
                self.policy.created_network(self.policy.network, receipt)
            else:
                self.policy.created_volume(receipt.get('Name'), receipt)
            return
        if method == 'POST' and route == '/containers/create' and status != 201:
            name = parse_qs(urlsplit(path).query)['name'][0]
            self.policy.failed_container_creation(name)
            self.fatal = 'Container creation did not return a successful new ID; stop'
            return
        if not 200 <= status < 300:
            return
        if method == 'POST' and route == '/containers/create':
            name = parse_qs(urlsplit(path).query)['name'][0]
            self.policy.created_container(name, json.loads(body)['Id'])
        elif method == 'POST' and route.endswith('/exec') and route.startswith('/containers/'):
            self.policy.created_exec(json.loads(body)['Id'],route.split('/')[2])
        elif method == 'DELETE' and re.fullmatch(r'/containers/[^/]+', route):
            target = route.rsplit('/', 1)[1]
            self.policy.removed_container(self.policy.name_ids.get(target, target))
        elif method == 'DELETE' and route.startswith('/volumes/'):
            self.policy.removed_volume(route[len('/volumes/'):])
        elif method == 'DELETE' and route.startswith('/networks/'):
            self.policy.removed_network(route[len('/networks/'):])

    def inspect_resource(self, path):
        backend = UnixConnection(self.backend)
        response = None
        try:
            backend.request('GET', path, headers={'Connection': 'close'})
            response = backend.getresponse()
            body = response.read(MAX_BODY + 1)
            if len(body) > MAX_BODY:
                raise Refused('Resource inspection exceeds reviewed bound')
            return response.status, json.loads(body)
        finally:
            if response is not None:
                response.close()
            backend.close()

    def handle(self, handler):
        backend = None
        response = None
        if time.monotonic() >= self.deadline or (self.fatal and not self.cleanup_only):
            return self.fail(handler, self.fatal or 'Proxy deadline exhausted')
        try:
            if self.cleanup_only:
                route = re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(handler.path).path)
                if not ((handler.command == 'DELETE' and re.fullmatch(r'/(containers|volumes|networks)/[^/]+', route)) or
                        (handler.command == 'GET' and re.fullmatch(r'/(containers/[^/]+/json|networks/[^/]+)', route))):
                    raise Refused('Cleanup admits only registered inventory inspection and deletion')
            if handler.headers.get('Transfer-Encoding'):
                raise Refused('Chunked Docker request bodies are not admitted')
            length = int(handler.headers.get('Content-Length', '0'))
            if not 0 <= length <= MAX_BODY:
                raise Refused('Docker request body exceeds reviewed bound')
            payload = handler.rfile.read(length)
            with self.lock:
                self.require_open()
                route = re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(handler.path).path)
                if handler.command == 'POST' and route == '/volumes/create':
                    config = json.loads(payload)
                    name = config.get('Name')
                    self.policy.require(name in self.policy.volume_names,
                                        'Foreign volume creation refused')
                    status, _ = self.inspect_resource('/volumes/' + name)
                    self.policy.require(status == 404, 'Preexisting or unreadable volume refused')
                    self.policy.recorded_volume_absence(name)
                if handler.command == 'POST' and route == '/containers/create':
                    self.policy.require(self.policy.network_id is not None,
                                        'Container requires registered owned network')
                    status, receipt = self.inspect_resource('/networks/' + self.policy.network_id)
                    self.policy.require(status == 200, 'Owned network is not inspectable before attach')
                    self.policy.verify_network(receipt)
                path, payload = self.policy.admit(handler.command, handler.path, payload)
                if handler.command == 'POST' and route == '/containers/create':
                    # Recheck the materialized role recipe, including omitted API
                    # fields; inspecting only client-supplied Binds misses defaults.
                    config = json.loads(payload)
                    name = parse_qs(urlsplit(path).query)['name'][0]
                    status, receipt = self.inspect_resource('/images/' + config['Image'] + '/json')
                    self.policy.require(status == 200, 'Immutable role image is not inspectable')
                    self.policy.roles.verify_image(name, receipt)
                    for bind in (config.get('HostConfig') or {}).get('Binds') or []:
                        name = bind.split(':', 1)[0]
                        if not name.startswith('/'):
                            self.policy.require(name in self.policy.volume_receipts,
                                                'Volume mount requires registered ownership')
                            status, receipt = self.inspect_resource('/volumes/' + name)
                            self.policy.require(status == 200, 'Owned volume is not inspectable before mount')
                            self.policy.verify_volume(name, receipt)
                admitted_route = re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(path).path)
                if handler.command == 'DELETE' and admitted_route.startswith('/volumes/'):
                    status, receipt = self.inspect_resource(admitted_route)
                    self.policy.require(status == 200, 'Owned volume is not inspectable')
                    self.policy.verify_volume(admitted_route[len('/volumes/'):], receipt)
                if handler.command in ('GET', 'DELETE') and admitted_route.startswith('/networks/'):
                    status, receipt = self.inspect_resource(admitted_route)
                    self.policy.require(status == 200, 'Owned network is not inspectable')
                    self.policy.verify_network(receipt)
                self.audit.append({'method': handler.command,
                                   'route': re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(path).path)})
            if handler.headers.get('Upgrade'):
                if not re.fullmatch(r'(?:/v[0-9.]+)?/exec/[0-9a-f]{64}/start', urlsplit(path).path):
                    raise Refused('Only inventoried Docker exec may hijack')
                return self.hijack(handler, path, payload)
            backend = UnixConnection(self.backend)
            headers = {k: v for k, v in handler.headers.items()
                       if k.lower() not in HOP_HEADERS | {'host', 'content-length'}}
            headers['Content-Length'] = str(len(payload))
            headers['Connection'] = 'close'
            with self.lock:
                self.require_open()
                backend.request(handler.command, path, body=payload, headers=headers)
            response = backend.getresponse()
            # Creation responses must be recorded before the client can start an ID.
            route = re.sub(r'^/v[0-9.]+(?=/)', '', urlsplit(path).path)
            observe = (handler.command == 'POST' and
                       (route in ('/containers/create', '/networks/create', '/volumes/create') or
                        route.endswith('/exec'))) or handler.command == 'DELETE'
            if observe:
                body = response.read(MAX_BODY + 1)
                if len(body) > MAX_BODY:
                    raise Refused('Docker mutation response exceeds reviewed bound')
                with self.lock:
                    self.observe(handler.command, path, response.status, body)
                handler.send_response(response.status)
                for k, v in response.getheaders():
                    if k.lower() not in HOP_HEADERS | {'content-length'}:
                        handler.send_header(k, v)
                handler.send_header('Content-Length', str(len(body)))
                handler.send_header('Connection', 'close')
                handler.end_headers()
                if body:
                    handler.wfile.write(body)
            else:
                handler.send_response(response.status)
                for k, v in response.getheaders():
                    if k.lower() not in HOP_HEADERS | {'content-length'}:
                        handler.send_header(k, v)
                handler.send_header('Connection', 'close')
                handler.end_headers()
                total = 0
                while time.monotonic() < self.deadline:
                    block = response.read1(65536)
                    if not block:
                        break
                    total += len(block)
                    if total > 32 * 1024**2:
                        raise Refused('Docker read response exceeds reviewed bound')
                    handler.wfile.write(block)
                    handler.wfile.flush()
            backend.close()
            handler.close_connection = True
        except MissingOwnedContainer:
            self.absent(handler)
        except (Refused, ValueError, KeyError, json.JSONDecodeError) as exc:
            self.fail(handler, str(exc))
        except Exception as exc:
            self.fatal = 'Proxy transport failed: ' + type(exc).__name__
            handler.close_connection = True
        finally:
            if response is not None:
                response.close()
            if backend is not None:
                backend.close()

    def hijack(self, handler, path, payload):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as backend:
            return self.hijack_owned(handler, path, payload, backend)

    def require_open(self):
        """Call under the controller lock at admission and immediately at dispatch."""
        if time.monotonic() >= self.deadline or (self.fatal and not self.cleanup_only):
            raise Refused(self.fatal or 'Proxy deadline exhausted')

    def hijack_owned(self, handler, path, payload, backend):
        backend.settimeout(30)
        backend.connect(self.backend)
        headers = dict(handler.headers)
        headers['Content-Length'] = str(len(payload))
        request = (handler.command + ' ' + path + ' HTTP/1.1\r\n' +
                   ''.join(k + ': ' + v + '\r\n' for k, v in headers.items()) + '\r\n').encode()
        with self.lock:
            self.require_open()
            backend.sendall(request + payload)
        head = b''
        while b'\r\n\r\n' not in head:
            block = backend.recv(4096)
            if not block or len(head) > 65536:
                raise Refused('Malformed Docker exec upgrade response')
            head += block
        header, initial = head.split(b'\r\n\r\n', 1)
        if not re.match(br'HTTP/1\.[01] 101(?: |$)', header):
            raise Refused('Docker exec upgrade did not return 101')
        handler.connection.sendall(header + b'\r\n\r\n' + initial)
        backend.settimeout(None)
        front = handler.connection
        front.settimeout(None)
        readable = [front, backend]
        total = 0
        while backend in readable and time.monotonic() < self.deadline and not self.fatal:
            ready, _, _ = select.select(readable, [], [], 1)
            for source in ready:
                data = source.recv(65536)
                destination = backend if source is front else front
                if not data:
                    readable.remove(source)
                    try: destination.shutdown(socket.SHUT_WR)
                    except OSError: pass
                    continue
                if source is front:
                    raise Refused('Exec stdin is unavailable; source-bound mounted recipes required')
                total += len(data)
                if total > 32 * 1024**2:
                    raise Refused('Docker exec stream exceeds reviewed bound')
                destination.sendall(data)
        backend.close()
        handler.close_connection = True

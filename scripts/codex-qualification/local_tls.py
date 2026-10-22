"""Owned HTTPS boundary components. Importing this module starts no service.

Operational callers must first establish registered ownership and namespace
evidence through the controller. These primitives cannot confer authorization.
Only generate_fixture_material executes commands, and only to make ephemeral
synthetic certificates; it never installs trust or contacts a network.
"""
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
from pathlib import Path
import re
import ssl
import subprocess
from urllib.parse import quote, urlsplit
from prepare import browser_contract


class Refused(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise Refused(message)


def checked_hostname(hostname):
    require(isinstance(hostname, str) and re.fullmatch(r'[a-z0-9]{20}\.supabase\.co', hostname),
            'Exact canonical-shaped synthetic hostname required')
    require(hostname == browser_contract()['url'].removeprefix('https://'),
            'Hostname must match this attempt synthetic browser contract')
    return hostname


def private_ipv4(value):
    try:
        address = ipaddress.IPv4Address(value)
    except (ipaddress.AddressValueError, TypeError):
        raise Refused('Literal owned internal IPv4 address required') from None
    require(any(address in ipaddress.ip_network(block) for block in
                ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')),
            'Upstream/address must be in an owned RFC1918 network')
    return str(address)


def material_recipe(hostname):
    checked_hostname(hostname)
    return {'hostname': hostname, 'san': ['DNS:' + hostname],
            'ca_scope': 'one-attempt-ephemeral-only', 'leaf_usage': 'serverAuth',
            'trust_scope': ['owned-renderer-process', 'owned-browser-profile'],
            'renderer_environment': {'NODE_EXTRA_CA_CERTS': '/qualification/tls/ca.crt'},
            'browser_trust': {'mechanism': 'NSS-database-in-isolated-browser-HOME',
                              'environment': {'HOME': '/qualification/browser-home'},
                              'profile': '/qualification/browser-profile',
                              'nss_database': 'sql:/qualification/browser-home/.pki/nssdb',
                              'ca': '/qualification/tls/ca.crt',
                              'prepare_directory': '/qualification/browser-home/.pki/nssdb',
                              'init_argv': ['certutil', '-N', '-d', 'sql:/qualification/browser-home/.pki/nssdb',
                                            '--empty-password'],
                              'import_argv': ['certutil', '-A', '-d', 'sql:/qualification/browser-home/.pki/nssdb',
                                              '-n', 'codex9051-task-ca', '-t', 'C,,', '-i', '/qualification/tls/ca.crt'],
                              'browser_argv_required': ['--user-data-dir=/qualification/browser-profile'],
                              'actual-browser-trust-observation': 'pending'},
            'forbidden': ['global-trust-install', 'host-DNS-write', 'ignore-certificate-errors',
                          'NODE_TLS_REJECT_UNAUTHORIZED=0', 'wildcard-SAN', 'external-DNS-forwarding'],
            'execute_authorized': False}


def generate_fixture_material(directory, hostname):
    """Explicit synthetic-test helper; create fresh task files, never global trust."""
    checked_hostname(hostname)
    directory = Path(directory)
    require(directory.is_absolute() and not directory.exists(), 'Fresh absolute fixture directory required')
    directory.mkdir(mode=0o700)
    env = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent/codex9051-tls', 'LANG': 'C'}
    ca_key, ca, key, csr, cert = [directory / name for name in ('ca.key', 'ca.crt', 'leaf.key', 'leaf.csr', 'leaf.crt')]
    commands = [
        ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '2',
         '-subj', '/CN=codex9051 synthetic task CA', '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
         '-addext', 'keyUsage=critical,keyCertSign,cRLSign', '-keyout', str(ca_key), '-out', str(ca)],
        ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj', '/CN=' + hostname,
         '-keyout', str(key), '-out', str(csr)],
        ['x509', '-req', '-in', str(csr), '-CA', str(ca), '-CAkey', str(ca_key),
         '-set_serial', '1', '-days', '1', '-sha256', '-extfile', str(directory / 'leaf.ext'), '-out', str(cert)],
    ]
    (directory / 'leaf.ext').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
                                       'extendedKeyUsage=serverAuth\nsubjectAltName=DNS:' + hostname + '\n')
    for command in commands:
        subprocess.run(['/usr/bin/openssl', *command], env=env, check=True,
                       capture_output=True, timeout=20)
    for path in (ca_key, key):
        path.chmod(0o600)
    return {'ca_key': str(ca_key), 'ca': str(ca), 'key': str(key), 'cert': str(cert),
            'ca_sha256': hashlib.sha256(ca.read_bytes()).hexdigest(),
            'cert_sha256': hashlib.sha256(cert.read_bytes()).hexdigest()}


def client_context(ca):
    context = ssl.create_default_context(cafile=str(ca))
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    require(context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED, 'TLS verification required')
    return context


def server_context(material, hostname):
    checked_hostname(hostname)
    # Inspect actual certificate bytes, not a supplied SAN receipt.
    leaf = ssl._ssl._test_decode_cert(str(material['cert']))
    require(leaf.get('subjectAltName') == (('DNS', hostname),), 'Leaf must have only the exact DNS SAN')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(material['cert'], material['key'])
    def sni(_connection, name, _context):
        if name != hostname:
            return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME
        return None
    context.set_servername_callback(sni)
    return context


class TLSProxy:
    """HTTPS to a fixed owned Kong IPv4:8000; never a forward/DNS proxy.

    Construction is configuration only. make_server is explicit and is used
    solely by local fixtures here; operational invocation needs fresh approval.
    """
    LIMIT = 8 * 1024 * 1024
    HOP = {'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
           'te', 'trailer', 'transfer-encoding', 'upgrade'}

    def __init__(self, hostname, upstream_ip, upstream_port=8000):
        self.hostname = checked_hostname(hostname)
        self.upstream_ip = private_ipv4(upstream_ip)
        require(type(upstream_port) is int and upstream_port == 8000, 'Only owned Kong port8000 admitted')
        self.upstream_port = upstream_port

    def admit(self, method, target, headers):
        require(method in ('GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'), 'Proxy method refused')
        require(isinstance(target, str) and target.startswith('/') and not target.startswith('//') and
                '#' not in target and
                not any(ord(char) < 33 or char == '\\' for char in target), 'Only unambiguous origin-form target admitted')
        parsed = urlsplit(target)
        require(not parsed.scheme and not parsed.netloc and not parsed.fragment, 'Forward proxy target refused')
        values = {}
        for name, value in headers:
            require(re.fullmatch(r'[!#$%&\'*+.^_`|~0-9A-Za-z-]+', name) and
                    not any(ord(char) < 32 or ord(char) == 127 for char in value), 'Invalid header refused')
            values.setdefault(name.lower(), []).append(value)
        require(values.get('host') in ([self.hostname], [self.hostname + ':443']), 'Exact single Host required')
        require(not any(key in values for key in ('upgrade', 'transfer-encoding', 'proxy-authorization',
                                                  'proxy-connection', 'forwarded')) and
                not any(key.startswith('x-forwarded-') for key in values),
                'Upgrade, proxy and caller forwarding overrides refused')
        require(all(len(values.get(key, [])) <= 1 for key in ('content-length', 'authorization', 'cookie', 'connection')),
                'Ambiguous sensitive header refused')
        require(values.get('connection') in (None, ['close'], ['keep-alive']), 'Connection nominated headers refused')
        lengths = values.get('content-length', [])
        require(not lengths or (re.fullmatch(r'[0-9]+', lengths[0]) and int(lengths[0]) <= self.LIMIT),
                'Unbounded/invalid request length refused')
        safe_path = quote(parsed.path, safe="/%:@!$&'()*+,;=-._~")
        safe_query = quote(parsed.query, safe="/%?:@!$&'()*+,;=-._~")
        return safe_path + ('?' + safe_query if parsed.query else '')

    def redirect(self, location):
        require(isinstance(location, str) and location and not any(ord(char) < 33 or char == '\\' for char in location),
                'Ambiguous redirect refused')
        parsed = urlsplit(location)
        if parsed.scheme or parsed.netloc:
            require(parsed.scheme == 'https' and parsed.netloc in (self.hostname, self.hostname + ':443'),
                    'Redirect leaves owned HTTPS origin')
        else:
            require(location.startswith('/') and not location.startswith('//'), 'Only owned root-relative redirect admitted')
        return location

    def make_server(self, address, material):
        proxy = self
        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.0'
            def log_message(self, *_args):
                pass  # Never log synthetic auth headers, request targets or bodies.
            def handle_request(self):
                connection = None
                try:
                    target = proxy.admit(self.command, self.path, list(self.headers.items()))
                    body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                    require(len(body) == int(self.headers.get('Content-Length', '0')), 'Early request EOF')
                    headers = {name: value for name, value in self.headers.items()
                               if name.lower() not in proxy.HOP and name.lower() not in
                               ('host', 'x-forwarded-for', 'x-forwarded-proto', 'content-length')}
                    headers.update({'Host': proxy.hostname, 'X-Forwarded-Proto': 'https'})
                    connection = http.client.HTTPConnection(proxy.upstream_ip, proxy.upstream_port, timeout=5)
                    connection.request(self.command, target, body, headers)
                    response = connection.getresponse()
                    response_headers = response.getheaders()
                    for name, value in response_headers:
                        require(isinstance(name, str) and re.fullmatch(r'[!#$%&\'*+.^_`|~0-9A-Za-z-]+', name)
                                and isinstance(value, str)
                                and not any(ord(char) < 32 or ord(char) == 127 for char in value),
                                'Invalid upstream response header refused')
                        if name.lower() == 'location':
                            proxy.redirect(value)
                        require(name.lower() != 'refresh', 'Upstream refresh redirect refused')
                    payload = response.read(proxy.LIMIT + 1)
                    require(len(payload) <= proxy.LIMIT, 'Upstream response limit exceeded')
                    self.send_response(response.status)
                    for name, value in response_headers:
                        if name.lower() not in proxy.HOP and name.lower() not in ('content-length', 'server', 'date'):
                            self.send_header(name, value)
                    self.send_header('Content-Length', str(len(payload)))
                    self.end_headers()
                    if self.command != 'HEAD':
                        self.wfile.write(payload)
                except (Refused, OSError, http.client.HTTPException):
                    self.send_response(502)
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                finally:
                    if connection is not None:
                        connection.close()
            do_GET = do_HEAD = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = handle_request
        class Server(ThreadingHTTPServer):
            daemon_threads = False
            block_on_close = True
            allow_reuse_address = False
            def get_request(self):
                connection, peer = super().get_request()
                connection.settimeout(5)
                try:
                    return context.wrap_socket(connection, server_side=True), peer
                except Exception:
                    connection.close()
                    raise
        context = server_context(material, self.hostname)
        server = Server(address, Handler)
        return server

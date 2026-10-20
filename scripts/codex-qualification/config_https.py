"""Dormant bounded Config HTTPS transport; execution requires separate authority.

No CLI, acquisition manifest, retry, output file or permission is supplied here.
Only fixed roles can construct a request. Capabilities and credentials stay in
this process; the fresh interpreter resolver receives only a fixed hostname.
"""
import errno
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import select
import socket
import ssl
import subprocess
import sys
import time
from urllib.parse import urlsplit

import redirect_diagnostic as legacy
import registry_metadata as metadata
from prepare import Refused, sha

TOKEN_URL = metadata.TOKEN_URL
CONFIG_DIGEST = 'sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5'
CONFIG_URL = metadata.REGISTRY + 'blobs/' + CONFIG_DIGEST
DESTINATION = 'production.cloudfront.docker.com'
CONFIG_MEDIA = 'application/vnd.oci.image.config.v1+json'
FAILURES = frozenset(('binding', 'output', 'replay', 'deadline', 'dns', 'peer', 'tls',
                     'headers', 'status', 'token', 'location', 'body', 'digest', 'schema', 'internal'))
HOSTS = frozenset(('auth.docker.io', 'registry-1.docker.io', DESTINATION))
DENY_V4 = tuple(ipaddress.ip_network(value) for value in (
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
    '172.16.0.0/12', '192.0.0.0/24', '192.0.2.0/24', '192.88.99.0/24', '192.168.0.0/16',
    '198.18.0.0/15', '198.51.100.0/24', '203.0.113.0/24', '224.0.0.0/4', '240.0.0.0/4'))
DENY_V6 = tuple(ipaddress.ip_network(value) for value in (
    '::/96', '::ffff:0:0/96', '64:ff9b::/96', '64:ff9b:1::/48', '100::/64',
    '2001::/23', '2001:db8::/32', '2002::/16', '3fff::/20', 'fc00::/7', 'fe80::/10', 'ff00::/8'))


class TransportRefused(Refused):
    def __init__(self, code):
        self.code = code if type(code) is str and code in FAILURES else 'internal'
        super().__init__('Config HTTPS transport refused')


def _remaining(clock, deadline):
    now = clock()
    if (type(now) not in (int, float) or not math.isfinite(now) or
            type(deadline) not in (int, float) or not math.isfinite(deadline) or now >= deadline):
        raise TransportRefused('deadline')
    return deadline - now


def checked_location(value):
    """Validate without normalizing the signed path/query or retaining its URL."""
    if (type(value) is not str or not value.isascii() or not 0 < len(value) <= 4096 or
            any(ord(char) <= 32 or ord(char) == 127 for char in value) or
            '\\' in value or '#' in value or re.search(r'%(?![0-9a-fA-F]{2})', value)):
        raise TransportRefused('location')
    try:
        parsed = urlsplit(value)
        if (not value.startswith('https://') or parsed.scheme != 'https' or
                parsed.netloc not in (DESTINATION, DESTINATION + ':443') or
                not parsed.path.startswith('/') or parsed.username is not None or parsed.password is not None):
            raise TransportRefused('location')
        # Preserve even an empty query delimiter; never decode/re-encode a capability.
        return value[len('https://') + len(parsed.netloc):]
    except TransportRefused:
        raise
    except Exception:
        raise TransportRefused('location') from None


def selected_address(rows):
    """Validate the entire resolution set, then select one deterministic numeric peer."""
    if type(rows) is not list or not 0 < len(rows) <= 16:
        raise TransportRefused('dns')
    addresses = []
    try:
        for row in rows:
            if (type(row) is not list or len(row) != 5 or type(row[0]) is not int or
                    row[0] not in (socket.AF_INET, socket.AF_INET6) or type(row[1]) is not str or
                    '%' in row[1] or any(type(value) is not int for value in row[2:]) or
                    row[2:] != [443, 0, 0]):
                raise TransportRefused('dns')
            address = ipaddress.ip_address(row[1])
            if ((address.version == 4) != (row[0] == socket.AF_INET) or not address.is_global or
                    address.is_private or address.is_loopback or address.is_link_local or
                    address.is_multicast or address.is_reserved or address.is_unspecified or
                    any(address in network for network in (DENY_V4 if address.version == 4 else DENY_V6)) or
                    (address.version == 6 and (address not in ipaddress.ip_network('2000::/3') or
                     address.ipv4_mapped is not None or address.sixtofour is not None or address.teredo is not None))):
                raise TransportRefused('dns')
            addresses.append((row[0], str(address), int(address)))
        family, numeric, _ = min(addresses, key=lambda item: (item[0], item[2]))
        return family, (numeric, 443) if family == socket.AF_INET else (numeric, 443, 0, 0)
    except TransportRefused:
        raise
    except Exception:
        raise TransportRefused('dns') from None


def resolve_addresses(host, *, deadline, clock):
    """Bound a fresh secret-free interpreter and reap it before releasing its result.

    Reserve 250 ms of the caller deadline for cancellation/reaping. No shell,
    preexec hook, inherited environment/stdin or capability-bearing input exists.
    The independently approved outer timeout remains the process-level backstop.
    """
    if host not in HOSTS or not Path(sys.executable).is_absolute():
        raise TransportRefused('dns')
    _remaining(clock, deadline)
    process = None
    raw = bytearray()
    try:
        child_deadline = deadline - 0.25
        _remaining(clock, child_deadline)
        process = subprocess.Popen([sys.executable, '-I', '-S', '-B',
            str(Path(__file__).with_name('config_resolver.py').resolve()), host],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={}, close_fds=True, cwd='/', start_new_session=True)
        os.set_blocking(process.stdout.fileno(), False)
        while True:
            remaining = _remaining(clock, child_deadline)
            readable, _, _ = select.select([process.stdout], [], [], remaining)
            _remaining(clock, child_deadline)
            if not readable:
                raise TransportRefused('deadline')
            part = os.read(process.stdout.fileno(), min(4097 - len(raw), 4096))
            if not part:
                break
            raw.extend(part)
            if len(raw) > 4096:
                raise TransportRefused('dns')
        if process.wait(timeout=_remaining(clock, child_deadline)) != 0:
            raise TransportRefused('dns')
        rows = json.loads(bytes(raw).decode('ascii'))
        selected_address(rows)
        return rows
    except TransportRefused:
        raise
    except subprocess.TimeoutExpired:
        raise TransportRefused('deadline') from None
    except Exception:
        raise TransportRefused('dns') from None
    finally:
        if process is not None:
            try:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=max(0, deadline - clock()))
            except Exception:
                raise TransportRefused('deadline') from None
            finally:
                if process.stdout is not None:
                    process.stdout.close()


def _tls_context(ca_bytes, ca_sha256):
    if (type(ca_bytes) is not bytes or not 0 < len(ca_bytes) <= 1024**2 or
            type(ca_sha256) is not str or sha(ca_bytes) != ca_sha256):
        raise TransportRefused('binding')
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_verify_locations(cadata=metadata._certificate_pem(ca_bytes))
        context.set_alpn_protocols(['http/1.1'])
        return context
    except Exception:
        raise TransportRefused('tls') from None


class Wire(legacy.DeadlineWire):
    def read_headers(self):
        raw = bytearray()
        while not raw.endswith(b'\r\n\r\n'):
            if len(raw) >= 16384:
                raise TransportRefused('headers')
            raw.extend(self.receive(1))
        lines = bytes(raw[:-4]).split(b'\r\n')
        match = re.fullmatch(rb'HTTP/1\.([01]) ([1-5][0-9]{2})(?: [\x20-\x7e]*)?', lines[0])
        if match is None or len(lines) - 1 > 100:
            raise TransportRefused('headers')
        self.http_version = lines[0].split(b' ', 1)[0]
        pairs = []
        for line in lines[1:]:
            name, sep, value = line.partition(b':')
            value = value.strip(b' \t')
            if (not sep or not re.fullmatch(rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+", name) or
                    any(byte < 32 or byte == 127 for byte in value)):
                raise TransportRefused('headers')
            pairs.append((name.decode('ascii').lower(), value.decode('latin-1')))
        return int(match.group(2)), pairs


def _peer(connection, address):
    try:
        observed = connection.getpeername()
        if (type(observed) is not tuple or len(observed) != len(address) or
                observed[1:] != address[1:] or ipaddress.ip_address(observed[0]) != ipaddress.ip_address(address[0])):
            raise TransportRefused('peer')
    except Exception:
        raise TransportRefused('peer') from None


class BoundedHTTPS:
    def __init__(self, ca_bytes, ca_sha256, *, clock=time.monotonic):
        self.context = _tls_context(ca_bytes, ca_sha256)
        self.clock = clock

    def request(self, role, *, location=None, bearer=None, deadline, observe):
        last_time = None

        def clock():
            nonlocal last_time
            now = self.clock()
            if (type(now) not in (int, float) or not math.isfinite(now) or
                    last_time is not None and now < last_time):
                raise TransportRefused('deadline')
            last_time = now
            return now

        if role not in ('token', 'registry', 'destination') or not callable(observe):
            raise TransportRefused('binding')
        if role == 'destination':
            target, host = checked_location(location), DESTINATION
            if bearer is not None:
                raise TransportRefused('binding')
        else:
            if location is not None:
                raise TransportRefused('binding')
            parsed = urlsplit(TOKEN_URL if role == 'token' else CONFIG_URL)
            target, host = parsed.path + ('?' + parsed.query if parsed.query else ''), parsed.hostname
            if role == 'token' and bearer is not None:
                raise TransportRefused('binding')
            if role == 'registry' and not metadata._token(bearer):
                raise TransportRefused('token')
        if _remaining(clock, deadline) > 10:
            raise TransportRefused('deadline')
        headers = [('Host', host), ('Accept', 'application/json' if role == 'token' else 'application/octet-stream'),
                   ('Accept-Encoding', 'identity'), ('Connection', 'close')]
        if role == 'registry':
            headers.append(('Authorization', 'Bearer ' + bearer))
        connection, tls, phase = None, None, 'dns'
        try:
            family, address = selected_address(resolve_addresses(host, deadline=deadline, clock=clock))
            _remaining(clock, deadline)
            phase = 'peer'
            connection = socket.socket(family, socket.SOCK_STREAM, socket.IPPROTO_TCP)
            connection.setblocking(False)
            wire = Wire(connection, clock=clock, deadline=deadline)
            result = connection.connect_ex(address)
            if result not in (0, errno.EINPROGRESS, errno.EWOULDBLOCK, errno.EALREADY, errno.EINTR):
                raise TransportRefused('peer')
            if result != 0:
                wire.wait(writing=True)
                if connection.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) != 0:
                    raise TransportRefused('peer')
            _peer(connection, address)
            observe('peer_ok', True)
            phase = 'tls'
            tls = self.context.wrap_socket(connection, server_hostname=host,
                do_handshake_on_connect=False, suppress_ragged_eofs=False)
            tls.setblocking(False)
            wire.connection = tls
            while True:
                wire.remaining()
                try:
                    tls.do_handshake()
                    wire.remaining()
                    break
                except ssl.SSLWantReadError:
                    wire.wait()
                except ssl.SSLWantWriteError:
                    wire.wait(writing=True)
            if tls.selected_alpn_protocol() not in (None, 'http/1.1'):
                raise TransportRefused('tls')
            observe('tls_ok', True)
            phase = 'peer'
            _peer(tls, address)
            phase = 'headers'
            wire.remaining()
            request = ('GET ' + target + ' HTTP/1.1\r\n' +
                ''.join(key + ': ' + value + '\r\n' for key, value in headers) + '\r\n').encode('ascii')
            observe('send', None)
            wire.send(request)
            status, pairs = wire.read_headers()
            observe('http_status', status)
            if status != (307 if role == 'registry' else 200):
                raise TransportRefused('status')
            names = {}
            for key, value in pairs:
                names.setdefault(key, []).append(value)
            if role == 'registry':
                if len(names.get('location', [])) != 1:
                    raise TransportRefused('location')
                checked_location(names['location'][0])
                return status, names['location'][0]
            if role == 'token':
                mode, size, _ = legacy.checked_body_headers(names, 16384, classify_token=True)
                phase = 'body'
                if mode == 'length':
                    body = wire.read_exact(size)
                elif mode == 'chunked':
                    if wire.http_version != b'HTTP/1.1':
                        raise TransportRefused('headers')
                    body = wire.read_chunked(16384)
                else:
                    body = wire.read_to_eof(16384)
                return status, body
            if (wire.http_version != b'HTTP/1.1' or names.get('content-length') != ['2646'] or
                    'transfer-encoding' in names or names.get('content-encoding', ['identity']) != ['identity'] or
                    names.get('content-type') not in (['application/octet-stream'], [CONFIG_MEDIA])):
                raise TransportRefused('headers')
            if 'docker-content-digest' in names and names['docker-content-digest'] != [CONFIG_DIGEST]:
                raise TransportRefused('digest')
            phase = 'body'
            body = bytearray()
            while len(body) < 2646:
                body.extend(wire.receive(2646 - len(body)))
                observe('body_bytes', len(body))
            return status, bytes(body)
        except TransportRefused as error:
            if error.code in ('peer', 'tls'):
                observe(error.code + '_ok', False)
            raise
        except metadata.BoundaryFailure as error:
            code = 'deadline' if error.reason == 'deadline' else phase
            if code in ('peer', 'tls'):
                observe(code + '_ok', False)
            raise TransportRefused(code) from None
        except Exception:
            if phase in ('peer', 'tls'):
                observe(phase + '_ok', False)
            raise TransportRefused(phase) from None
        finally:
            try:
                if tls is not None:
                    tls.close()
                elif connection is not None:
                    connection.close()
            except Exception:
                raise TransportRefused('internal') from None

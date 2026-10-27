"""Explicit Unix HTTP framing boundary; no discovery, admission or CLI.

Construction checks supplied source references only. Calling request opens one
explicit socket, but establishes no daemon identity, approval, ownership, image
profile, authentication or operational qualification. Namespace Policy remains
responsible for exact request admission and resource registration.
"""
import copy
import errno
import json
import math
from pathlib import Path
import re
import select
import socket
import time

import controller_inputs as inputs
from operational import BUDGET
from prepare import Refused, sha

MAX_BODY = 16 * 1024**2
MAX_HEADERS = 32 * 1024
MAX_HEADER_COUNT = 128
MAX_CHUNKS = 4096
MAX_CHUNK_LINE = 32
MAX_JSON_DEPTH = 128
READ_SIZE = 64 * 1024


class _BoundaryFailure(Exception):
    """Only fixed local messages may cross the public Refused boundary."""


def _require(condition, message):
    if not condition:
        raise _BoundaryFailure(message)


def _finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    except (OverflowError, TypeError, ValueError):
        return False


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, 'Duplicate JSON object key refused')
        result[key] = value
    return result


def _constant(_value):
    raise _BoundaryFailure('Nonfinite JSON number refused')


def _float(value):
    result = float(value)
    _require(math.isfinite(result), 'Nonfinite JSON number refused')
    return result


def _json_object(payload, deadline):
    deadline.remaining()
    value = json.loads(payload.decode('utf-8'), object_pairs_hook=_pairs,
                       parse_constant=_constant, parse_float=_float)
    _require(type(value) is dict, 'JSON object body required')
    # Iterator frames bound auxiliary memory by nesting, rather than by the
    # number of fields. JSON parsing itself is checked before and after; Python
    # parsing is not preempted by the socket deadline.
    stack = [iter(value.values())]
    while stack:
        try:
            child = next(stack[-1])
        except StopIteration:
            stack.pop()
            continue
        if type(child) in (dict, list):
            _require(len(stack) < MAX_JSON_DEPTH, 'JSON nesting bound exceeded')
            stack.append(iter(child.values() if type(child) is dict else child))
    deadline.remaining()
    return value


class _Deadline:
    def __init__(self, tick, start, timeout):
        _require(_finite(timeout) and 0 < timeout <= BUDGET['work_seconds'],
                 'Finite positive bounded transport timeout required')
        self._tick = tick
        self._end = start + timeout
        _require(_finite(self._end) and self._end > start,
                 'Finite advancing transport deadline required')

    def remaining(self):
        left = self._end - self._tick()
        _require(left > 0, 'Unix JSON transport deadline expired')
        return left


class _Stream:
    def __init__(self, connection, deadline):
        self.connection, self.deadline = connection, deadline
        self.buffer = bytearray()

    def wait(self, *, writing=False):
        timeout = self.deadline.remaining()
        readable, writable, exceptional = select.select(
            [] if writing else [self.connection],
            [self.connection] if writing else [], [self.connection], timeout)
        self.deadline.remaining()
        _require(not exceptional and bool(writable if writing else readable),
                 'Unix JSON transport readiness failed')

    def receive(self, amount, *, eof=False):
        while True:
            self.deadline.remaining()
            try:
                data = self.connection.recv(amount)
            except (BlockingIOError, InterruptedError):
                self.wait()
                continue
            self.deadline.remaining()
            _require(type(data) is bytes and len(data) <= amount,
                     'Unix JSON transport read failed')
            _require(data or eof, 'Truncated Unix JSON transport response')
            return data

    def send(self, request):
        view = memoryview(request)
        while view:
            self.deadline.remaining()
            try:
                sent = self.connection.send(view)
            except (BlockingIOError, InterruptedError):
                self.wait(writing=True)
                continue
            self.deadline.remaining()
            _require(type(sent) is int and 0 < sent <= len(view),
                     'Unix JSON transport send failed')
            view = view[sent:]

    def until(self, separator, limit):
        while True:
            self.deadline.remaining()
            offset = self.buffer.find(separator)
            if offset >= 0:
                end = offset + len(separator)
                _require(end <= limit, 'Unix JSON transport framing bound exceeded')
                result = bytes(self.buffer[:offset])
                del self.buffer[:end]
                self.deadline.remaining()
                return result
            _require(len(self.buffer) < limit, 'Unix JSON transport framing bound exceeded')
            self.buffer.extend(self.receive(min(READ_SIZE, limit - len(self.buffer))))

    def exact(self, size):
        self.deadline.remaining()
        _require(type(size) is int and 0 <= size <= MAX_BODY,
                 'Unix JSON transport body bound exceeded')
        while len(self.buffer) < size:
            self.buffer.extend(self.receive(min(READ_SIZE, size - len(self.buffer))))
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        self.deadline.remaining()
        return result

    def eof(self):
        self.deadline.remaining()
        _require(not self.buffer, 'Trailing Unix JSON transport bytes refused')
        _require(self.receive(1, eof=True) == b'', 'Trailing Unix JSON transport bytes refused')
        self.deadline.remaining()


def _headers(stream):
    lines = stream.until(b'\r\n\r\n', MAX_HEADERS).split(b'\r\n')
    stream.deadline.remaining()
    _require(len(lines) <= MAX_HEADER_COUNT + 1, 'HTTP header count bound exceeded')
    status = re.fullmatch(rb'HTTP/1\.1 ([2-5][0-9]{2}) [\x20-\x7e]*', lines[0])
    _require(status is not None, 'Final HTTP/1.1 response required')
    headers = {}
    for line in lines[1:]:
        name, separator, value = line.partition(b':')
        _require(separator and re.fullmatch(rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+", name),
                 'HTTP header name or folding refused')
        _require(all(32 <= byte <= 126 for byte in value), 'HTTP header control bytes refused')
        name = name.lower()
        _require(name not in headers, 'Duplicate HTTP header refused')
        headers[name] = value.strip(b' ')
    _require(b'upgrade' not in headers and b'upgrade' not in
             [token.strip().lower() for token in headers.get(b'connection', b'').split(b',')],
             'HTTP upgrade refused')
    _require(headers.get(b'content-encoding', b'identity').lower() == b'identity',
             'HTTP content encoding refused')
    stream.deadline.remaining()
    return int(status[1]), headers


def _chunked(stream):
    body = bytearray()
    count = 0
    while True:
        line = stream.until(b'\r\n', MAX_CHUNK_LINE)
        _require(re.fullmatch(rb'[0-9A-Fa-f]+', line), 'HTTP chunk size or extension refused')
        size = int(line, 16)
        _require(size <= MAX_BODY - len(body), 'Unix JSON transport body bound exceeded')
        if size == 0:
            _require(stream.exact(2) == b'\r\n', 'HTTP chunk trailer refused')
            return bytes(body)
        count += 1
        _require(count <= MAX_CHUNKS, 'HTTP chunk count bound exceeded')
        body.extend(stream.exact(size))
        _require(stream.exact(2) == b'\r\n', 'HTTP chunk terminator refused')


def _response(stream):
    status, headers = _headers(stream)
    length, transfer = headers.get(b'content-length'), headers.get(b'transfer-encoding')
    _require(length is None or transfer is None, 'Ambiguous HTTP response framing refused')
    if length is not None:
        _require(re.fullmatch(rb'0|[1-9][0-9]*', length), 'Canonical HTTP content length required')
        # Bound digit count before integer conversion as well as decoded size.
        _require(len(length) <= len(str(MAX_BODY)), 'Unix JSON transport body bound exceeded')
        length = int(length)
        _require(length <= MAX_BODY, 'Unix JSON transport body bound exceeded')
    if transfer is not None:
        _require(transfer.lower() == b'chunked', 'HTTP transfer encoding refused')
    if status in (204, 304):
        _require(transfer is None and length in (None, 0), 'Contradictory bodyless HTTP status refused')
    body = _chunked(stream) if transfer is not None else stream.exact(length or 0)
    # Absence of framing is admissible only for a proven empty response. EOF
    # also refuses pipelined/contaminating bytes after fixed or chunked bodies.
    stream.eof()
    if not body:
        return status, {}
    _require(re.fullmatch(rb'application/json(?: *; *charset *= *utf-8)?',
                         headers.get(b'content-type', b'').lower()),
             'JSON response content type required')
    return status, _json_object(body, stream.deadline)


class UnixJsonTransport:
    def __init__(self, contract: dict, endpoint: str, *, clock=time.monotonic):
        try:
            self._contract = copy.deepcopy(contract)
            inputs.checked_inputs(self._contract)
            reference = self._contract.get('source_references', {}).get(
                'scripts/codex-qualification/controller_transports.py', {})
            _require(reference.get('sha256') == sha(Path(__file__).read_bytes()),
                     'Executing transport component differs from source reference')
            _require(type(endpoint) is str and endpoint.startswith('/') and
                     0 < len(endpoint) <= 100 and endpoint.isascii() and
                     all(32 <= ord(character) <= 126 for character in endpoint) and
                     '//' not in endpoint and
                     not any(part in ('.', '..') for part in endpoint.split('/')),
                     'Explicit bounded absolute Unix endpoint required')
            _require(callable(clock), 'Monotonic transport clock required')
            self._endpoint, self._clock, self._last_clock = endpoint, clock, None
        except _BoundaryFailure as error:
            raise Refused(str(error)) from None
        except Exception:
            raise Refused('Unix JSON transport construction refused') from None

    def _tick(self):
        try:
            instant = self._clock()
        except Exception:
            raise _BoundaryFailure('Unix JSON transport clock failed') from None
        _require(_finite(instant) and (self._last_clock is None or instant >= self._last_clock),
                 'Finite ordered monotonic transport clock required')
        self._last_clock = instant
        return instant

    def snapshot(self) -> dict:
        return {'pairing_sha256': self._contract['pairing_sha256'],
                'operational_sha256': self._contract['operational_sha256'],
                'execute_authorized': False, 'profile_admissible': False,
                'authentication_established': False, 'ownership_verified': False,
                'quiescence_verified': False, 'issuer_verification': 'pending',
                'independent_review': 'pending',
                'runtime_evidence': 'pending-synthetic-transport-tests-only'}

    def request(self, method: str, path: str, payload: bytes, *, timeout: float) -> tuple[int, dict]:
        try:
            start = self._tick()
            deadline = _Deadline(self._tick, start, timeout)
            deadline.remaining()
            _require(type(method) is str and method in ('GET', 'POST', 'DELETE'),
                     'HTTP transport method refused')
            _require(type(path) is str and 1 <= len(path) <= 8192 and path.startswith('/') and
                     path.isascii() and all(33 <= ord(character) <= 126 for character in path) and
                     not any(character in path for character in ('#', '\\')),
                     'Bounded HTTP origin-form path required')
            _require(type(payload) is bytes and len(payload) <= MAX_BODY,
                     'Bounded exact bytes request body required')
            _require(method == 'POST' or not payload, 'Bodyless HTTP method required')
            if payload:
                _json_object(payload, deadline)
            request = (method.encode('ascii') + b' ' + path.encode('ascii') +
                       b' HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
                       b'Content-Type: application/json\r\nContent-Length: ' +
                       str(len(payload)).encode('ascii') + b'\r\n\r\n' + payload)
            deadline.remaining()
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                connection.setblocking(False)
                stream = _Stream(connection, deadline)
                deadline.remaining()
                result = connection.connect_ex(self._endpoint)
                deadline.remaining()
                if result in (errno.EINPROGRESS, errno.EALREADY, errno.EWOULDBLOCK,
                              errno.EAGAIN, errno.EINTR):
                    stream.wait(writing=True)
                    result = connection.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
                    deadline.remaining()
                _require(type(result) is int and result == 0, 'Unix JSON transport connection failed')
                stream.send(request)
                response = _response(stream)
            finally:
                connection.close()
            deadline.remaining()
            return response
        except _BoundaryFailure as error:
            raise Refused(str(error)) from None
        except Exception:
            raise Refused('Unix JSON transport request refused') from None

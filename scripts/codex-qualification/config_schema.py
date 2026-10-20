"""Inert bounded OCI Config validation; never returns execution/profile values.

Local contract derived from OCI image-spec v1.1.1 config.md and
schema/{config-schema,defs}.json. This is not the unmodified upstream schema:
normative optional-null behavior takes precedence; reserved fields, DiffID
syntax, empty set-map objects and pinned platform/count are checked too.
No remote references, schema packages, dynamic evaluation or resource fetches.
"""
import calendar
import hashlib
import json
import math
import re

from prepare import Refused


CONTRACT = 'oci-config-v1.1.1-normative-null-v1'
MAX_BYTES = 2646
MAX_DEPTH = 32

# Complete local reference closure: all field definitions and their referenced
# primitive/collection constraints live here; the validator source is separately
# source-bound by preparation. No external $ref resolution is performed.
REFERENCE_CLOSURE = {
    'contract': CONTRACT,
    'sources': ['https://github.com/opencontainers/image-spec/blob/v1.1.1/config.md',
                'https://github.com/opencontainers/image-spec/blob/v1.1.1/schema/config-schema.json',
                'https://github.com/opencontainers/image-spec/blob/v1.1.1/schema/defs.json'],
    'optional_null': 'absent-for-typing-without-rewriting-input',
    'required': {'architecture': 'amd64', 'os': 'linux',
                 'rootfs': {'type': 'layers', 'diff_ids': 'digest-array-matching-layer-count'}},
    'optional': {'created': 'timestamp', 'author': 'string', 'os.version': 'string',
                 'os.features': 'strings', 'variant': 'string', 'config': 'config',
                 'history': 'history'},
    'config': {'User': 'string', 'ExposedPorts': 'empty-object-map', 'Env': 'strings',
               'Entrypoint': 'strings', 'Cmd': 'strings', 'Volumes': 'empty-object-map',
               'WorkingDir': 'string', 'Labels': 'string-map', 'StopSignal': 'string',
               'ArgsEscaped': 'boolean', 'Memory': 'integer', 'MemorySwap': 'integer',
               'CpuShares': 'integer', 'Healthcheck': 'object'},
    'history': {'created': 'timestamp', 'author': 'string', 'created_by': 'string',
                'comment': 'string', 'empty_layer': 'boolean'},
    'definitions': {
        'string': 'JSON string containing Unicode scalar values',
        'boolean': 'JSON true or false, not numeric',
        'integer': 'JSON integer excluding booleans and floating point spellings',
        'object': 'JSON object; reserved Healthcheck members remain inert extensions',
        'strings': 'JSON array whose every item is a string',
        'empty-object-map': 'JSON object whose every value is an empty object',
        'string-map': 'JSON object whose every value is a string, including empty keys',
        'config': 'JSON object checked against config definitions',
        'history': 'JSON array of objects checked against history definitions',
        'timestamp': 'RFC3339 full date-time: valid calendar date, t/T and z/Z allowed, '
                     'seconds 00..60, fractional seconds optional, offset 00:00..23:59',
        'digest': 'lowercase algorithm components separated by +._-; encoded '
                  'ASCII alphanumeric/=_-; sha256/sha512 require lowercase hex 64/128',
    },
    'parse': {'bytes_ceiling': MAX_BYTES, 'container_depth_ceiling': MAX_DEPTH,
              'utf8': 'strict-no-BOM', 'duplicate_keys': 'reject-at-every-depth',
              'numbers': 'finite-only', 'root': 'object',
              'unicode': 'scalar-values-only', 'trailing': 'JSON-whitespace-only',
              'extensions': 'accepted-inert-under-identical-parse-bounds'},
}
REFERENCE_CLOSURE_SHA256 = hashlib.sha256(json.dumps(
    REFERENCE_CLOSURE, sort_keys=True, separators=(',', ':'),
    ensure_ascii=True).encode('ascii')).hexdigest()


def reference_closure_sha256():
    """Bind every local definition; preparation separately binds this source."""
    return hashlib.sha256(json.dumps(REFERENCE_CLOSURE, sort_keys=True,
                                    separators=(',', ':'), ensure_ascii=True).encode('ascii')).hexdigest()

_DATE = re.compile(r'([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]'
                   r'([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?'
                   r'(?:[Zz]|([+-])([0-9]{2}):([0-9]{2}))')
_DIGEST = re.compile(r'([a-z0-9]+(?:[+._-][a-z0-9]+)*):([A-Za-z0-9=_-]+)')


class _Invalid(ValueError):
    """Internal fixed diagnostic, never includes Config data."""


def _reject():
    raise _Invalid('invalid')


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            _reject()
        result[key] = value
    return result


def _bounded_text(raw):
    if type(raw) is not bytes or len(raw) > MAX_BYTES:
        _reject()
    if raw.startswith(b"\xef\xbb\xbf"):
        _reject()
    text = raw.decode('utf-8')
    # Count containers before decoding: attacker nesting cannot exhaust Python's
    # JSON decoder recursion. Brackets inside escaped strings are not containers.
    depth = 0
    quoted = False
    escaped = False
    for character in text:
        if quoted:
            if escaped:
                escaped = False
            elif character == '\\':
                escaped = True
            elif character == '"':
                quoted = False
        elif character == '"':
            quoted = True
        elif character in '[{':
            depth += 1
            if depth > MAX_DEPTH:
                _reject()
        elif character in ']}':
            depth -= 1
    return text


def _primitives(value):
    if type(value) is str:
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            _reject()
    elif type(value) is float and not math.isfinite(value):
        _reject()
    elif type(value) is list:
        for item in value:
            _primitives(item)
    elif type(value) is dict:
        for key, item in value.items():
            _primitives(key)
            _primitives(item)


def _timestamp(value):
    if type(value) is not str:
        return False
    match = _DATE.fullmatch(value)
    if match is None:
        return False
    year, month, day, hour, minute, second = map(int, match.group(1, 2, 3, 4, 5, 6))
    if not (1 <= month <= 12 and 1 <= day <= calendar.monthrange(year, month)[1]
            and hour <= 23 and minute <= 59 and second <= 60):
        return False
    return match[7] is None or (int(match[8]) <= 23 and int(match[9]) <= 59)


def _digest(value):
    if type(value) is not str:
        return False
    match = _DIGEST.fullmatch(value)
    if match is None:
        return False
    algorithm, encoded = match.groups()
    if algorithm in ('sha256', 'sha512'):
        size = 64 if algorithm == 'sha256' else 128
        return len(encoded) == size and re.fullmatch('[a-f0-9]+', encoded) is not None
    return True


def _matches(value, kind):
    if kind == 'string':
        return type(value) is str
    if kind == 'boolean':
        return type(value) is bool
    if kind == 'integer':
        return type(value) is int
    if kind == 'object':
        return type(value) is dict
    if kind == 'strings':
        return type(value) is list and all(type(item) is str for item in value)
    if kind == 'empty-object-map':
        return type(value) is dict and all(type(item) is dict and not item for item in value.values())
    if kind == 'string-map':
        return type(value) is dict and all(type(item) is str for item in value.values())
    if kind == 'timestamp':
        return _timestamp(value)
    if kind == 'config':
        if type(value) is not dict:
            return False
        _fields(value, REFERENCE_CLOSURE['config'])
        return True
    if kind == 'history':
        if type(value) is not list or any(type(item) is not dict for item in value):
            return False
        for item in value:
            _fields(item, REFERENCE_CLOSURE['history'])
        return True
    _reject()


def _fields(doc, definitions):
    for name, kind in definitions.items():
        if name not in doc or doc[name] is None:
            continue
        value = doc[name]
        if not _matches(value, kind):
            _reject()


def _validate(raw, layer_count):
    if type(layer_count) is not int or layer_count < 0:
        _reject()
    text = _bounded_text(raw)
    doc = json.loads(text, object_pairs_hook=_object, parse_constant=lambda _: _reject())
    if type(doc) is not dict:
        _reject()
    _primitives(doc)
    if doc.get("os") != "linux" or doc.get("architecture") != "amd64":
        _reject()
    rootfs = doc.get('rootfs')
    if type(rootfs) is not dict or rootfs.get('type') != 'layers':
        _reject()
    diff_ids = rootfs.get('diff_ids')
    if type(diff_ids) is not list:
        _reject()
    if len(diff_ids) != layer_count:
        _reject()
    for value in diff_ids:
        if not _digest(value):
            _reject()
    _fields(doc, REFERENCE_CLOSURE['optional'])


def validate_config(raw: bytes, *, layer_count: int) -> None:
    """Accept only the pinned inert structure; refuse without raw diagnostics."""
    failed = False
    try:
        _validate(raw, layer_count)
    except (ValueError, TypeError, RecursionError, OverflowError):
        failed = True
    # Raise outside the handler: JSONDecodeError contains the original document,
    # so even exception __context__ must not retain that decoder exception.
    if failed:
        raise Refused('Config schema refused')

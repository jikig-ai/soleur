"""Two-request Mailpit redirect-header diagnostic; never contacts a Location."""
import argparse
import copy
import http.client
import ipaddress
import os
from pathlib import Path
import re
import ssl
import stat
import time
import unicodedata
from urllib.parse import urlsplit

import registry_metadata as metadata
from prepare import Refused, canonical, require, sha

ERROR = 'Redirect header diagnostic incomplete'
MANIFEST = 'redirect-diagnostic-manifest.json'
MARKER = '.redirect-diagnostic-consumed'
RECEIPT = 'redirect-diagnostic-receipt.json'
TOKEN_URL = metadata.TOKEN_URL
REGISTRY = metadata.REGISTRY
MAX_LOCATION = 8192
MAX_HEADER_COUNT = 128
MAX_HEADER_BYTES = 32768


def verified_platform(raw, image):
    """Verify pinned platform bytes and the exact OCI Config descriptor."""
    require(type(raw) is bytes and 0 < len(raw) <= 1024**2 and type(image) is dict and
            set(image) == {'source_repository', 'manifest_digest', 'image_id', 'platform'} and
            image['source_repository'] == metadata.reference.REPOSITORY and
            image['platform'] == 'linux/amd64' and metadata._immutable(image['manifest_digest']) and
            metadata._immutable(image['image_id']) and 'sha256:' + sha(raw) == image['manifest_digest'],
            'Pinned platform bytes differ')
    value = metadata.base._decode_json(raw)
    require(type(value) is dict and value.get('schemaVersion') == 2 and
            value.get('mediaType') in metadata.PLATFORM_MEDIA, 'Pinned platform manifest shape differs')
    descriptor = value.get('config')
    require(type(descriptor) is dict and descriptor.get('mediaType') in metadata.CONFIG_MEDIA and
            descriptor.get('digest') == image['image_id'] and type(descriptor.get('size')) is int and
            0 < descriptor['size'] <= 1024**2, 'Pinned Config descriptor differs')
    return {'sha256': sha(raw), 'bytes': len(raw), 'config_descriptor': {
        key: descriptor[key] for key in ('mediaType', 'digest', 'size')}}


def _validated_context(retained_image, context):
    # Reuse the existing exact public-host contract validator, without its 3-GET action plan.
    common = metadata.action_manifest(retained_image=retained_image, **context)
    return common


def action_manifest(*, retained_image, platform_evidence, **context):
    common = _validated_context(retained_image, context)
    require(type(platform_evidence) is dict and set(platform_evidence) == {
        'path', 'sha256', 'bytes', 'config_descriptor'}, 'Pinned platform evidence binding required')
    metadata.base._path(platform_evidence['path'])
    metadata.base._digest(platform_evidence['sha256'])
    descriptor = platform_evidence['config_descriptor']
    require(type(platform_evidence['bytes']) is int and 0 < platform_evidence['bytes'] <= 1024**2 and
            type(descriptor) is dict and set(descriptor) == {'mediaType', 'digest', 'size'} and
            descriptor['mediaType'] in metadata.CONFIG_MEDIA and descriptor['digest'] == retained_image['image_id'] and
            type(descriptor['size']) is int and 0 < descriptor['size'] <= 1024**2,
            'Exact pinned Config descriptor required')
    actions = [copy.deepcopy(common['actions'][0]), {
        'method': 'GET', 'url': REGISTRY + 'blobs/' + retained_image['image_id'],
        'headers': {'Host': 'registry-1.docker.io', 'Accept': 'application/octet-stream',
                    'Accept-Encoding': 'identity', 'Connection': 'close'},
        'bearer': True, 'maximum_bytes': 0, 'permitted_status': 307,
        'response_body': 'never-read'}]
    return {'version': 1, 'kind': 'mailpit-config-redirect-header-diagnostic',
            'context': copy.deepcopy(context), 'retained_image': copy.deepcopy(retained_image),
            'platform_evidence': copy.deepcopy(platform_evidence), 'actions': actions,
            'total_timeout': 60, 'request_timeout_max': 10, 'maximum_location_bytes': MAX_LOCATION,
            'marker_name': MARKER, 'receipt_name': RECEIPT,
            'execute_authorized': False, 'destination_authorized': False,
            'authentication_established': False, 'ownership_verified': False,
            'quiescence_verified': False, 'local_image_observed': False,
            'independent_review': 'pending', 'issuer_verification': 'pending',
            'publisher_authentication': 'pending'}


def checked_manifest(manifest, expected_sha256):
    metadata.base._digest(expected_sha256)
    require(type(manifest) is dict and len(canonical(manifest)) <= 65536 and
            sha(canonical(manifest)) == expected_sha256, 'Diagnostic manifest digest differs')
    expected = action_manifest(retained_image=manifest['retained_image'],
        platform_evidence=manifest['platform_evidence'], **manifest['context'])
    require(canonical(expected) == canonical(manifest), 'Diagnostic manifest fields differ')


def project_location(value, expected_digest):
    """Return only approved routing identity and hashes; caller must discard input."""
    require(type(value) is str and value.isascii() and 0 < len(value) <= MAX_LOCATION and
            type(expected_digest) is str and metadata._immutable(expected_digest), 'Bounded Location required')
    require(not any(unicodedata.category(char) in ('Cc', 'Cf') for char in value) and
            not any(char.isspace() for char in value) and '#' not in value and '\\' not in value,
            'Unsafe Location characters')
    try:
        parsed = urlsplit(value)
        host, port = parsed.hostname, parsed.port
    except (ValueError, UnicodeError):
        raise Refused(ERROR) from None
    require(parsed.scheme.lower() == 'https' and parsed.netloc and host and
            '@' not in parsed.netloc and parsed.username is None and parsed.password is None and
            parsed.fragment == '' and '?' not in parsed.netloc and not parsed.netloc.endswith(':'),
            'Unsafe Location authority')
    normalized = host.lower()
    require(not normalized.endswith('..'), 'Malformed DNS root labels')
    if normalized.endswith('.'):
        normalized = normalized[:-1]
    require(normalized and '.' in normalized and any(char.isalpha() for char in normalized) and
            len(normalized) <= 253 and normalized.isascii() and
            re.fullmatch(r'[a-z0-9.-]+', normalized) and
            all(0 < len(label) <= 63 and re.fullmatch(r'[a-z0-9](?:[a-z0-9-]*[a-z0-9])?', label)
                for label in normalized.split('.')), 'DNS hostname required')
    try:
        ipaddress.ip_address(normalized)
        raise Refused(ERROR)
    except ValueError:
        pass
    require(port in (None, 443) and (parsed.path == '' or parsed.path.startswith('/')) and
            len(parsed.path) <= MAX_LOCATION and
            (not parsed.query or all(unicodedata.category(char) not in ('Cc', 'Cf') for char in parsed.query)),
            'Unsupported Location route')
    suffix_start = value.find('://') + 3 + len(parsed.netloc)
    return {'scheme': 'https', 'hostname': normalized,
            'route_class': 'same-registry-host' if normalized == 'registry-1.docker.io'
                           else 'other-dns-host',
            'port': 443, 'location_sha256': sha(value.encode('ascii')),
            'location_bytes': len(value), 'path_sha256': sha(parsed.path.encode('ascii')),
            'query_present': '?' in value[suffix_start:], 'fragment_or_userinfo_present': False,
            'expected_config_digest_in_path': expected_digest in parsed.path}


class DiagnosticFailure(Refused):
    def __init__(self, receipt):
        super().__init__(ERROR)
        self.receipt = copy.deepcopy(receipt)


class HTTPSAdapter:
    """Explicit-CA adapter; Config response headers only, with no body read."""
    def __init__(self, manifest, ca_bytes, *, manifest_sha256, clock=time.monotonic):
        checked_manifest(manifest, manifest_sha256)
        context = manifest['context']
        require(type(ca_bytes) is bytes and 0 < len(ca_bytes) <= 1024**2 and
                sha(ca_bytes) == context['ca_sha256'], ERROR)
        self.manifest = copy.deepcopy(manifest)
        self.clock = clock
        # The existing adapter performs strict PEM projection and explicit TLS setup only.
        common = metadata.action_manifest(retained_image=manifest['retained_image'], **context)
        self.tls = metadata.HTTPSAdapter(common, ca_bytes,
            manifest_sha256=sha(canonical(common)), clock=clock)

    def request(self, url, headers, *, timeout, maximum_bytes):
        action = next((item for item in self.manifest['actions'] if item['url'] == url), None)
        require(action is not None and type(headers) is dict and type(timeout) in (int, float) and
                0 < timeout <= 10 and maximum_bytes == action['maximum_bytes'], 'Unapproved HTTPS request')
        expected = dict(action['headers'])
        if action['bearer']:
            bearer = headers.get('Authorization')
            require(type(bearer) is str and bearer.startswith('Bearer ') and metadata._token(bearer[7:]),
                    'Anonymous bearer required')
            expected['Authorization'] = bearer
        require(headers == expected, 'HTTPS headers differ')
        if url == self.manifest['actions'][0]['url']:
            return self.tls.request(url, headers, timeout=timeout, maximum_bytes=maximum_bytes)
        start, status, response, connection = self.clock(), None, None, None
        try:
            target = urlsplit(url)
            connection = http.client.HTTPSConnection(target.hostname, 443, context=self.tls.context,
                                                       timeout=timeout)
            connection.set_debuglevel(0)
            connection.request('GET', target.path, body=None, headers=headers)
            response = connection.getresponse()
            status = response.status if type(response.status) is int and 100 <= response.status <= 599 else None
            now = self.clock()
            if status is None or now < start or now >= start + timeout:
                raise metadata.BoundaryFailure('deadline', status)
            if status != 307:
                return status, [], b''
            pairs = response.getheaders()
            if len(pairs) > MAX_HEADER_COUNT or sum(len(k) + len(v) for k, v in pairs) > MAX_HEADER_BYTES:
                raise metadata.BoundaryFailure('header_shape', status)
            locations = []
            for key, value in pairs:
                if key.lower() == 'location':
                    if type(value) is not str or len(value.encode('utf-8')) > MAX_LOCATION:
                        raise metadata.BoundaryFailure('header_shape', status)
                    locations.append(value)
            if len(locations) != 1:
                raise metadata.BoundaryFailure('header_shape', status)
            return status, [('Location', value) for value in locations], b''
        except metadata.BoundaryFailure:
            raise
        except Exception:
            raise metadata.BoundaryFailure('unexpected_failure', status) from None
        finally:
            if response is not None:
                response.close()
            if connection is not None:
                connection.close()


class RedirectDiagnostic:
    def __init__(self, manifest, transport, consume_gate, *, manifest_sha256,
                 clock=time.monotonic, output_binding=None):
        checked_manifest(manifest, manifest_sha256)
        output_binding = (lambda: None) if output_binding is None else output_binding
        require(callable(getattr(transport, 'request', None)) and callable(consume_gate) and
                callable(clock) and callable(output_binding), 'Explicit diagnostic interfaces required')
        self.manifest, self.digest, self.transport = copy.deepcopy(manifest), manifest_sha256, transport
        self.gate, self.clock, self.output_binding = consume_gate, clock, output_binding
        self.attempted = False

    def collect(self):
        require(not self.attempted, 'Diagnostic is one-use')
        checked_manifest(self.manifest, self.digest)
        self.attempted = True
        context, plan = copy.deepcopy(self.manifest['context']), copy.deepcopy(self.manifest['actions'])
        states = [{'action_index': i, 'url_sha256': sha(action['url'].encode()),
                   'phase': 'initialization', 'reason': 'not_attempted', 'status_code': None}
                  for i, action in enumerate(plan, 1)]
        result = {'status': 'incomplete', 'manifest_sha256': self.digest,
                  'source_sha': context['source_sha'], 'pairing_sha256': context['pairing_sha256'],
                  'operational_sha256': context['operational_sha256'],
                  'retained_manifest_sha256': context['retained_manifest_sha256'],
                  'platform_manifest_sha256': self.manifest['platform_evidence']['sha256'],
                  'attempt': context['attempt'], 'actions': states,
                  'request_count': 0, 'started_at_monotonic': None, 'finished_at_monotonic': None,
                  'execute_authorized': False, 'destination_authorized': False,
                  'authentication_established': False, 'ownership_verified': False,
                  'quiescence_verified': False, 'local_image_observed': False,
                  'profile_admissible': False, 'publisher_authentication': 'pending',
                  'issuer_verification': 'pending', 'independent_review': 'pending'}
        current, last = {'action_index': None, 'phase': 'initialization',
                         'reason': 'unexpected_failure', 'status_code': None}, None
        token = None
        def enter(phase, reason='unexpected_failure'):
            current.update(phase=phase, reason=reason)
        def remaining():
            nonlocal last
            now = self.clock()
            require(metadata.base._finite(now) and last is not None and last <= now,
                    'Diagnostic deadline expired')
            left = self.deadline - now
            require(left > 0, 'Diagnostic deadline expired')
            last = now
            return min(10, left)
        def finish():
            result['finished_at_monotonic'] = last
            result['receipt_sha256'] = sha(canonical(result))
            return result
        try:
            start = self.clock()
            require(metadata.base._finite(start), ERROR)
            self.deadline, last = start + 60, start
            result['started_at_monotonic'] = start
            enter('output_binding', 'source_binding')
            self.output_binding()
            enter('consume_gate')
            self.gate()
            for index, (action, state) in enumerate(zip(plan, states)):
                current = state
                enter('binding', 'source_binding')
                checked_manifest(self.manifest, self.digest)
                remaining()
                headers = dict(action['headers'])
                if index:
                    headers['Authorization'] = 'Bearer ' + token
                enter('transport')
                timeout = remaining()
                result['request_count'] += 1
                response = self.transport.request(action['url'], headers, timeout=timeout,
                                                  maximum_bytes=action['maximum_bytes'])
                status = response[0] if type(response) is tuple and len(response) == 3 and type(response[0]) is int else None
                if status is not None and 100 <= status <= 599:
                    state['status_code'] = status
                remaining()
                require(status is not None and 100 <= status <= 599 and type(response) is tuple and len(response) == 3,
                        'Response shape differs')
                if index == 0:
                    enter('token_validation', 'token_shape')
                    require(status == 200 and type(response[1]) is str and
                            response[1].split(';', 1)[0].strip().lower() == 'application/json' and
                            type(response[2]) is bytes and len(response[2]) <= 16384, 'Token response differs')
                    payload = metadata.base._decode_json(response[2])
                    require(type(payload) is dict, ERROR)
                    token = payload.get('token', payload.get('access_token'))
                    require(metadata._token(token) and all(payload[key] == token for key in
                        ('token', 'access_token') if key in payload), 'Anonymous token differs')
                else:
                    enter('location_validation', 'http_status')
                    require(status == 307 and type(response[1]) is list and type(response[2]) is bytes and
                            response[2] == b'', 'Expected header-only 307 response')
                    locations = [value for key, value in response[1]
                                 if type(key) is str and key.lower() == 'location']
                    require(len(locations) == 1, 'Exactly one Location required')
                    enter('location_projection', 'location_shape')
                    projected = project_location(locations[0], self.manifest['retained_image']['image_id'])
                    self.output_binding()
                    result['routing'] = projected
                    state['phase'], state['reason'] = 'response_validation', 'observed'
            result['status'] = 'redirect-headers-observed'
            return finish()
        except Exception as error:
            if isinstance(error, metadata.BoundaryFailure):
                current['reason'] = error.reason
                if error.status is not None:
                    current['status_code'] = error.status
            result['error'] = ERROR
            result['failure'] = copy.deepcopy(current)
            result.pop('routing', None)
            raise DiagnosticFailure(finish()) from None
        finally:
            token = None


def _dependencies(repo, contract):
    result = metadata._dependencies(repo, contract)
    for name in ('redirect_diagnostic.py', 'test_redirect_diagnostic.py'):
        path = 'scripts/codex-qualification/' + name
        digest = sha(metadata.base._read(str(Path(repo) / path)))
        require(contract.get('source_references', {}).get(path, {}).get('sha256') == digest and
                sha(metadata.base.git(Path(repo), '-c', 'core.fsmonitor=false', 'show',
                    contract['identity']['source_sha'] + ':' + path)) == digest and
                sha(metadata.base._read(str(Path(__file__).absolute() if name == 'redirect_diagnostic.py'
                                             else Path(__file__).with_name(name)))) == digest,
                'Redirect diagnostic component differs from committed source')
        result[name] = digest
    return result


def check_retained_bindings(context, inputs):
    require(type(context) is dict and type(inputs) is dict and all(
        inputs[key] == context[key] for key in ('attempt', 'retained_manifest_sha256', 'image_refs')),
        'Diagnostic retained bindings differ')


def prepare_action(args):
    from operational import checked_contract
    contract, raw, inputs, inputs_sha, image, ca = metadata._source_inputs(args)
    checked_contract(contract)
    require(contract['identity']['source_sha'] == args.source_sha, 'Diagnostic source differs')
    dependencies = _dependencies(args.repo, contract)
    platform_raw = metadata.base._read(args.platform_file, 1024**2)
    projected = verified_platform(platform_raw, image)
    platform_evidence = {'path': args.platform_file, **projected}
    parent = metadata.base._parent(args.directory)
    directory = None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        observed = os.fstat(directory)
        manifest = action_manifest(retained_image=image, platform_evidence=platform_evidence,
            source_sha=args.source_sha, pairing_sha256=contract['pairing_sha256'],
            operational_sha256=contract['operational_sha256'],
            retained_manifest_sha256=inputs['retained_manifest_sha256'], image_refs=inputs['image_refs'],
            attempt=inputs['attempt'], timeout=inputs['total_timeout'], output_directory=args.directory,
            output_directory_fingerprint={'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid},
            ca_file=args.ca_file, ca_sha256=args.ca_sha256, bindings={
                'repo': args.repo, 'contract_path': args.contract, 'contract_sha256': sha(raw),
                'image_inputs_path': args.image_inputs, 'image_inputs_sha256': inputs_sha,
                'retained_manifest_path': inputs['retained_manifest_path'],
                'dependency_sha256': dependencies, 'local_files': inputs['local_files']})
        metadata.base._write_at(directory, MANIFEST, manifest)
    finally:
        if directory is not None:
            os.close(directory)
        os.close(parent)
    return sha(canonical(manifest))


def execute_action(args):
    from operational import checked_contract
    manifest = metadata.base._json(args.manifest)
    checked_manifest(manifest, args.manifest_sha256)
    context, bindings = manifest['context'], manifest['context']['bindings']
    metadata.base._digest(args.runner_sha256)
    require(sha(metadata.base._read(str(Path(__file__).absolute()))) == args.runner_sha256 and
            args.manifest == str(Path(context['output_directory']) / MANIFEST), 'Runner/manifest path differs')
    source_args = argparse.Namespace(repo=bindings['repo'], source_sha=context['source_sha'],
        contract=bindings['contract_path'], image_inputs=bindings['image_inputs_path'],
        ca_file=context['ca_file'], ca_sha256=context['ca_sha256'])
    contract, raw, inputs, inputs_sha, image, ca = metadata._source_inputs(source_args)
    checked_contract(contract)
    require(sha(raw) == bindings['contract_sha256'] and inputs_sha == bindings['image_inputs_sha256'] and
            contract['pairing_sha256'] == context['pairing_sha256'] and
            contract['operational_sha256'] == context['operational_sha256'] and
            _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and
            image == manifest['retained_image'] and inputs['local_files'] == bindings['local_files'] and
            inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and
            inputs['total_timeout'] == context['timeout'], 'Diagnostic retained bindings differ')
    check_retained_bindings(context, inputs)
    platform_raw = metadata.base._read(manifest['platform_evidence']['path'], 1024**2)
    projected = verified_platform(platform_raw, image)
    require(projected == {key: manifest['platform_evidence'][key]
            for key in ('sha256', 'bytes', 'config_descriptor')}, 'Pinned platform bytes changed')
    directory = metadata.base._parent(args.manifest)
    try:
        def output_binding():
            descriptor = metadata.base._parent(args.manifest)
            try:
                current, pinned = os.fstat(descriptor), os.fstat(directory)
                require((current.st_dev, current.st_ino) == (pinned.st_dev, pinned.st_ino) and
                        current.st_uid == os.getuid() and stat.S_IMODE(current.st_mode) == 0o700 and
                        {'dev': current.st_dev, 'ino': current.st_ino, 'uid': current.st_uid} ==
                        context['output_directory_fingerprint'], ERROR)
            finally:
                os.close(descriptor)
        output_binding()
        transport = HTTPSAdapter(manifest, ca, manifest_sha256=args.manifest_sha256)
        def consume():
            metadata.base._write_at(directory, MARKER, {'manifest_sha256': args.manifest_sha256})
        collector = RedirectDiagnostic(manifest, transport, consume,
            manifest_sha256=args.manifest_sha256, output_binding=output_binding)
        try:
            result = collector.collect()
        except DiagnosticFailure as error:
            metadata.base._write_at(directory, RECEIPT, error.receipt)
            raise Refused(ERROR) from None
        output_binding()
        metadata.base._write_at(directory, RECEIPT, result)
    finally:
        os.close(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'contract', 'image-inputs', 'ca-file', 'ca-sha256',
                 'platform-file', 'directory'):
        prepare.add_argument('--' + name, required=True)
    execute = commands.add_parser('execute')
    for name in ('manifest', 'manifest-sha256', 'runner-sha256'):
        execute.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            print('File-only redirect diagnostic manifest prepared; manifest_sha256=' + prepare_action(args))
        else:
            execute_action(args)
            print('Redirect headers projected; no destination request or local image admission')
    except Exception:
        parser.exit(1, ERROR + '\n')


if __name__ == '__main__':
    main()

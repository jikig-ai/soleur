"""Exactly three anonymous Mailpit registry metadata GETs; no layers or Docker.

Execution requires separate exact harness approval. A persistent marker prevents
replay but grants no authorization. TLS authenticates the approved host using
explicit CA bytes; neither registry metadata nor its digests authenticate a
publisher or establish a local image ID. DNS, parsing and fsync are cooperative;
the independently approved outer timeout remains necessary.
"""
import argparse
import copy
import http.client
import os
from pathlib import Path
import re
import ssl
import stat
import time
from urllib.parse import urlsplit

import reference_diagnostic as reference
from reference_diagnostic import base
from prepare import Refused, canonical, require, sha

ERROR = 'Registry metadata acquisition incomplete'
MANIFEST = 'registry-metadata-manifest.json'
MARKER = '.registry-metadata-consumed'
RECEIPT = 'registry-metadata-receipt.json'
PLATFORM_FILE = 'mailpit-platform-manifest.json'
CONFIG_FILE = 'mailpit-config.json'
STAGING = {PLATFORM_FILE: '.mailpit-platform.stage', CONFIG_FILE: '.mailpit-config.stage'}
TOKEN_URL = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository%3Aaxllent%2Fmailpit%3Apull'
REGISTRY = 'https://registry-1.docker.io/v2/axllent/mailpit/'
PLATFORM_MEDIA = ('application/vnd.oci.image.manifest.v1+json', 'application/vnd.docker.distribution.manifest.v2+json')
CONFIG_MEDIA = ('application/vnd.oci.image.config.v1+json', 'application/vnd.docker.container.image.v1+json')
MAX_TOTAL = 3 * 1024**2
FIELDS = {'source_sha', 'pairing_sha256', 'operational_sha256', 'retained_manifest_sha256', 'image_refs',
          'attempt', 'timeout', 'output_directory', 'output_directory_fingerprint', 'ca_file', 'ca_sha256', 'bindings'}


def _immutable(value):
    return type(value) is str and re.fullmatch('sha256:[0-9a-f]{64}', value)


def _token(value):
    return type(value) is str and 0 < len(value) <= 16384 and re.fullmatch(r'[A-Za-z0-9._~+/-]+={0,2}', value)


def action_manifest(*, retained_image, **context):
    """Pure exact public-host plan; secrets and synthetic Unix endpoints are absent."""
    require(set(context) == FIELDS and type(context['source_sha']) is str and
            re.fullmatch('[0-9a-f]{40}', context['source_sha']), 'Exact registry source bindings required')
    for key in ('pairing_sha256', 'operational_sha256', 'retained_manifest_sha256', 'ca_sha256'):
        base._digest(context[key])
    for key in ('ca_file', 'output_directory'):
        base._path(context[key])
    require(context['timeout'] == 60 and type(context['timeout']) in (int, float) and
            base._text(context['attempt'], 128) and re.fullmatch('[A-Za-z0-9_-]+', context['attempt']),
            'Fixed registry deadline and attempt required')
    fingerprint = context['output_directory_fingerprint']
    require(type(fingerprint) is dict and set(fingerprint) == {'dev', 'ino', 'uid'} and
            all(type(value) is int and value >= 0 for value in fingerprint.values()), 'Exact private output binding required')
    bindings = context['bindings']
    require(type(bindings) is dict and set(bindings) == {'repo', 'contract_path', 'contract_sha256',
            'image_inputs_path', 'image_inputs_sha256', 'retained_manifest_path', 'dependency_sha256', 'local_files'},
            'Exact retained registry files required')
    for key in ('repo', 'contract_path', 'image_inputs_path', 'retained_manifest_path'):
        base._path(bindings[key])
    for key in ('contract_sha256', 'image_inputs_sha256'):
        base._digest(bindings[key])
    for key in ('dependency_sha256', 'local_files'):
        require(type(bindings[key]) is dict and len(bindings[key]) <= 32, 'Bounded registry dependency census required')
        for name, digest in bindings[key].items():
            require(base._text(name), 'Bounded dependency name required')
            base._digest(digest)
    require(type(retained_image) is dict and set(retained_image) == {
        'source_repository', 'manifest_digest', 'image_id', 'platform'} and
        retained_image['source_repository'] == reference.REPOSITORY and retained_image['platform'] == 'linux/amd64' and
        _immutable(retained_image['manifest_digest']) and _immutable(retained_image['image_id']),
        'Exact retained Mailpit metadata digests required')
    require(type(context['image_refs']) is dict and set(context['image_refs']) == set(base.ROLES) and
            all(base._text(value, 512) for value in context['image_refs'].values()) and
            context['image_refs']['inbucket'] == reference.REPOSITORY + '@' + retained_image['manifest_digest'],
            'Retained role references differ')
    plan = [(TOKEN_URL, 16384, ('application/json',)),
            (REGISTRY + 'manifests/' + retained_image['manifest_digest'], 1024**2, PLATFORM_MEDIA),
            (REGISTRY + 'blobs/' + retained_image['image_id'], 1024**2,
             ('application/octet-stream', 'application/json') + CONFIG_MEDIA)]
    actions = [{'method': 'GET', 'url': url, 'headers': {'Host': urlsplit(url).hostname,
                'Accept': 'application/json' if index == 0 else ', '.join(PLATFORM_MEDIA) if index == 1 else 'application/octet-stream',
                'Accept-Encoding': 'identity', 'Connection': 'close'},
                'bearer': index != 0, 'maximum_bytes': maximum, 'permitted_media_types': list(media)}
               for index, (url, maximum, media) in enumerate(plan)]
    return {'version': 1, 'kind': 'anonymous-mailpit-registry-metadata', 'context': copy.deepcopy(context),
            'retained_image': copy.deepcopy(retained_image), 'actions': actions, 'maximum_total_bytes': MAX_TOTAL,
            'marker_name': MARKER, 'receipt_name': RECEIPT, 'artifacts': dict(STAGING),
            'execute_authorized': False, 'profile_admissible': False, 'issuer_verification': 'pending',
            'independent_review': 'pending', 'publisher_authentication': 'pending', 'local_image_observed': False}


def checked_manifest(manifest, digest):
    base._digest(digest)
    require(type(manifest) is dict and len(canonical(manifest)) <= 65536 and sha(canonical(manifest)) == digest and
            canonical(manifest) == canonical(action_manifest(retained_image=manifest['retained_image'], **manifest['context'])),
            'Registry manifest differs')


class BoundaryFailure(Refused):
    def __init__(self, reason, status=None):
        super().__init__(ERROR)
        require(reason in {'unexpected_failure', 'deadline', 'body_size', 'header_shape', 'body_encoding',
                          'publication', 'publication_cleanup'}, 'Fixed registry boundary reason required')
        self.reason = reason
        self.status = status if type(status) is int and 100 <= status <= 599 else None


class HTTPSAdapter:
    """No ambient trust, proxy, account credentials or connections at construction."""
    def __init__(self, manifest, ca_bytes, *, manifest_sha256, clock=time.monotonic):
        checked_manifest(manifest, manifest_sha256)
        require(type(ca_bytes) is bytes and 0 < len(ca_bytes) <= 1024**2 and
                sha(ca_bytes) == manifest['context']['ca_sha256'], 'Exact CA bundle bytes required')
        self.plan, self.clock = copy.deepcopy(manifest['actions']), clock
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self.context.check_hostname = True
        self.context.verify_mode = ssl.CERT_REQUIRED
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.context.load_verify_locations(cadata=ca_bytes.decode('ascii'))
        self.context.set_alpn_protocols(['http/1.1'])

    def request(self, url, headers, *, timeout, maximum_bytes):
        action = next((action for action in self.plan if action['url'] == url), None)
        require(action is not None and type(headers) is dict and base._finite(timeout) and 0 < timeout <= 10 and
                maximum_bytes == action['maximum_bytes'], 'Unapproved HTTPS request refused')
        expected = dict(action['headers'])
        if action['bearer']:
            value = headers.get('Authorization')
            require(type(value) is str and value.startswith('Bearer ') and _token(value[7:]), 'Exact anonymous bearer required')
            expected['Authorization'] = value
        require(headers == expected, 'HTTPS request headers differ')
        start, last, status = self.clock(), None, None
        require(base._finite(start), ERROR)
        deadline = start + timeout
        def remaining():
            nonlocal last
            now = self.clock()
            if not base._finite(now) or now < start or (last is not None and now < last) or now >= deadline:
                raise BoundaryFailure('deadline', status)
            last = now
            return deadline - now
        try:
            target = urlsplit(url)
            connection = http.client.HTTPSConnection(target.hostname, 443, context=self.context, timeout=remaining())
            response = None
            try:
                connection.set_debuglevel(0)
                connection.request('GET', target.path + ('?' + target.query if target.query else ''), body=None, headers=headers)
                stream = connection.sock
                stream.settimeout(remaining())
                response = connection.getresponse()
                status = response.status if type(response.status) is int and 100 <= response.status <= 599 else None
                remaining()
                if status != 200:
                    return status, None, b''
                pairs = response.getheaders()
                if len(pairs) > 128 or sum(len(key) + len(value) for key, value in pairs) > 32768:
                    raise BoundaryFailure('header_shape', status)
                selected = {}
                for key, value in pairs:
                    name = key.lower()
                    if name in ('content-length', 'content-type', 'content-encoding', 'transfer-encoding'):
                        if name in selected or not base._text(value, 8192):
                            raise BoundaryFailure('header_shape', status)
                        selected[name] = value
                if selected.get('content-encoding', 'identity').lower() != 'identity':
                    raise BoundaryFailure('body_encoding', status)
                length = selected.get('content-length')
                if length is not None and (not re.fullmatch('[0-9]{1,12}', length) or int(length) > maximum_bytes):
                    raise BoundaryFailure('body_size', status)
                if 'transfer-encoding' in selected and (selected['transfer-encoding'].lower() != 'chunked' or length is not None):
                    raise BoundaryFailure('header_shape', status)
                chunks, count = [], 0
                while True:
                    stream.settimeout(remaining())
                    chunk = response.read1(min(65536, maximum_bytes + 1 - count))
                    remaining()
                    if type(chunk) is not bytes or count + len(chunk) > maximum_bytes:
                        raise BoundaryFailure('body_size', status)
                    if not chunk:
                        break
                    chunks.append(chunk)
                    count += len(chunk)
                if length is not None and count != int(length):
                    raise BoundaryFailure('body_size', status)
                return status, selected.get('content-type'), b''.join(chunks)
            finally:
                try:
                    if response is not None:
                        response.close()
                finally:
                    connection.close()
        except BoundaryFailure:
            raise
        except Exception:
            raise BoundaryFailure('unexpected_failure', status) from None


class MetadataFailure(Refused):
    def __init__(self, receipt):
        super().__init__(ERROR)
        self.receipt = copy.deepcopy(receipt)


class RegistryMetadata:
    def __init__(self, manifest, transport, consume_gate, publish, *, manifest_sha256,
                 clock=time.monotonic, output_binding=None):
        checked_manifest(manifest, manifest_sha256)
        output_binding = (lambda: None) if output_binding is None else output_binding
        require(all(callable(value) for value in (getattr(transport, 'request', None), consume_gate, publish, clock, output_binding)),
                'Explicit registry interfaces required')
        self.manifest, self.digest = copy.deepcopy(manifest), manifest_sha256
        self.transport, self.gate, self.publish, self.clock = transport, consume_gate, publish, clock
        self.output_binding, self.attempted = output_binding, False

    def collect(self):
        require(not self.attempted, 'Registry metadata acquisition is one-use')
        checked_manifest(self.manifest, self.digest)
        self.attempted = True
        plan, context, image = (copy.deepcopy(self.manifest[key]) for key in ('actions', 'context', 'retained_image'))
        states = [{'action_index': index, 'url_sha256': sha(action['url'].encode()), 'phase': 'initialization',
                   'reason': 'not_attempted', 'status_code': None} for index, action in enumerate(plan, 1)]
        result = {'status': 'incomplete', 'manifest_sha256': self.digest, 'source_sha': context['source_sha'],
                  'pairing_sha256': context['pairing_sha256'], 'operational_sha256': context['operational_sha256'],
                  'retained_manifest_sha256': context['retained_manifest_sha256'], 'ca_sha256': context['ca_sha256'],
                  'attempt': context['attempt'], 'actions': states, 'metadata': {}, 'request_count': 0,
                  'started_at_monotonic': None, 'finished_at_monotonic': None,
                  'execute_authorized': False, 'profile_admissible': False, 'authentication_established': False,
                  'ownership_verified': False, 'quiescence_verified': False, 'local_image_observed': False,
                  'publisher_authentication': 'pending', 'issuer_verification': 'pending', 'independent_review': 'pending'}
        current = {'action_index': None, 'url_sha256': None, 'phase': 'initialization', 'reason': 'unexpected_failure', 'status_code': None}
        last, token, total, descriptor = None, None, 0, None
        def enter(phase, reason='unexpected_failure'):
            current.update(phase=phase, reason=reason)
        def check(condition, reason):
            if not condition:
                current['reason'] = reason
                raise Refused(ERROR)
        def finish():
            result['finished_at_monotonic'] = last
            result['receipt_sha256'] = sha(canonical(result))
            return result
        try:
            start = self.clock()
            require(base._finite(start), ERROR)
            deadline, last = start + 60, start
            require(base._finite(deadline) and deadline > start, ERROR)
            result['started_at_monotonic'] = start
            def remaining():
                nonlocal last
                enter('deadline')
                now = self.clock()
                require(base._finite(now) and now >= last and now < deadline, ERROR)
                last = now
                return min(10, deadline - now)
            def bindings():
                enter('binding', 'source_binding')
                checked_manifest(self.manifest, self.digest)
                enter('binding', 'output_binding')
                self.output_binding()
            def publication_checks():
                remaining()
                bindings()
                remaining()
            def publish_projection(name, raw, key, projected):
                rollback = self.publish(name, raw, publication_checks)
                try:
                    require(callable(rollback) and callable(getattr(rollback, 'accept', None)), ERROR)
                    publication_checks()
                    result['metadata'][key] = projected
                    rollback.accept()
                except Exception:
                    result['metadata'].pop(key, None)
                    if callable(rollback):
                        rollback()
                    raise
            enter('consume_gate', 'output_binding')
            self.output_binding()
            enter('consume_gate')
            self.gate()
            for index, (action, current) in enumerate(zip(plan, states)):
                bindings()
                headers = dict(action['headers'])
                if index:
                    headers['Authorization'] = 'Bearer ' + token
                timeout = remaining()
                enter('transport')
                result['request_count'] += 1
                response = self.transport.request(action['url'], headers, timeout=timeout, maximum_bytes=action['maximum_bytes'])
                if type(response) is tuple and len(response) == 3 and type(response[0]) is int and 100 <= response[0] <= 599:
                    current['status_code'] = response[0]
                remaining()
                bindings()
                enter('response_validation', 'receipt_shape')
                require(type(response) is tuple and len(response) == 3 and current['status_code'] is not None, ERROR)
                check(response[0] == 200, 'http_status')
                check(type(response[1]) is str and response[1].split(';', 1)[0].strip().lower() in action['permitted_media_types'], 'media_type')
                raw = response[2]
                check(type(raw) is bytes and len(raw) <= action['maximum_bytes'] and total + len(raw) <= MAX_TOTAL, 'body_size')
                total += len(raw)
                if index == 0:
                    enter('token_validation', 'token_shape')
                    payload = base._decode_json(raw)
                    require(type(payload) is dict, ERROR)
                    value = payload.get('token', payload.get('access_token'))
                    require(_token(value) and all(payload[key] == value for key in ('token', 'access_token') if key in payload), ERROR)
                    publication_checks()
                    token = value
                    payload = None
                elif index == 1:
                    enter('manifest_validation', 'digest_mismatch')
                    check('sha256:' + sha(raw) == image['manifest_digest'], 'digest_mismatch')
                    payload = base._decode_json(raw)
                    check(type(payload) is dict and type(payload.get('schemaVersion')) is int and payload['schemaVersion'] == 2 and
                          payload.get('mediaType') in PLATFORM_MEDIA, 'manifest_shape')
                    descriptor = payload.get('config')
                    check(type(descriptor) is dict and descriptor.get('mediaType') in CONFIG_MEDIA and
                          descriptor.get('digest') == image['image_id'] and type(descriptor.get('size')) is int and
                          0 < descriptor['size'] <= 1024**2, 'config_descriptor')
                    layers = payload.get('layers')
                    check(type(layers) is list and len(layers) <= 128 and all(type(layer) is dict and
                          _immutable(layer.get('digest')) and type(layer.get('size')) is int and
                          0 <= layer['size'] < 2**63 for layer in layers), 'layer_descriptors')
                    projected = {'sha256': sha(raw), 'bytes': len(raw), 'config_descriptor': {
                                     key: descriptor[key] for key in ('mediaType', 'digest', 'size')},
                                 'layer_count': len(layers), 'declared_layer_bytes': sum(layer['size'] for layer in layers)}
                    publication_checks()
                    enter('publication')
                    publish_projection(PLATFORM_FILE, raw, 'platform', projected)
                else:
                    enter('config_validation', 'digest_mismatch')
                    check('sha256:' + sha(raw) == image['image_id'], 'digest_mismatch')
                    check(len(raw) == descriptor['size'], 'config_size')
                    payload = base._decode_json(raw)
                    check(type(payload) is dict and payload.get('os') == 'linux' and payload.get('architecture') == 'amd64', 'platform')
                    projected = {'sha256': sha(raw), 'bytes': len(raw), 'platform': 'linux/amd64',
                                 'meaning': 'registry-config-blob-digest-not-a-local-image-ID'}
                    publication_checks()
                    enter('publication')
                    publish_projection(CONFIG_FILE, raw, 'config', projected)
                enter('response_validation', 'observed')
            result['status'] = 'registry-metadata-sequence-completed'
            return finish()
        except Exception as error:
            if isinstance(error, BoundaryFailure):
                current['reason'] = error.reason
                if error.status is not None:
                    current['status_code'] = error.status
            result['error'], result['failure'] = ERROR, copy.deepcopy(current)
            raise MetadataFailure(finish()) from None
        finally:
            token = None


def _dependencies(repo, contract):
    previous = reference._dependencies(repo, contract)
    name = 'registry_metadata.py'
    path = 'scripts/codex-qualification/' + name
    digest = sha(base._read(str(Path(repo) / path)))
    require(contract.get('source_references', {}).get(path, {}).get('sha256') == digest and
            sha(base.git(Path(repo), '-c', 'core.fsmonitor=false', 'show', contract['identity']['source_sha'] + ':' + path)) == digest and
            sha(base._read(str(Path(__file__).absolute()))) == digest, 'Registry runner differs from committed source')
    return {**previous, name: digest}


def _remove_owned(directory, name, identity):
    try:
        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if (current.st_dev, current.st_ino) == identity:
            os.unlink(name, dir_fd=directory)
        return True
    except FileNotFoundError:
        return True
    except OSError:
        return False


def publish_artifact(directory, name, raw, validate):
    require(name in STAGING and type(raw) is bytes and len(raw) <= 1024**2, ERROR)
    stage, identity, published, descriptor = STAGING[name], None, False, None
    def release():
        nonlocal descriptor
        closing, descriptor = descriptor, None
        if closing is not None:
            try:
                os.close(closing)
            except Exception:
                raise BoundaryFailure('publication_cleanup') from None
    def rollback():
        if identity is None and descriptor is None:
            return
        try:
            require(descriptor is not None and identity is not None, ERROR)
            held = os.fstat(descriptor)
            require((held.st_dev, held.st_ino) == identity, ERROR)
            candidates = (stage, name) if published else (stage,)
            outcomes = [_remove_owned(directory, candidate, identity) for candidate in candidates]
            os.fsync(directory)
            require(all(outcomes), ERROR)
        except Exception:
            raise BoundaryFailure('publication_cleanup') from None
        finally:
            release()
    rollback.accept = release
    try:
        validate()
        descriptor = os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
        with os.fdopen(descriptor, 'wb', closefd=False) as stream:
            observed = os.fstat(stream.fileno())
            identity = (observed.st_dev, observed.st_ino)
            require(stream.write(raw) == len(raw), ERROR)
            stream.flush()
            os.fsync(stream.fileno())
        validate()
        current = os.stat(stage, dir_fd=directory, follow_symlinks=False)
        require((current.st_dev, current.st_ino) == identity and current.st_uid == os.getuid() and
                stat.S_ISREG(current.st_mode) and stat.S_IMODE(current.st_mode) == 0o600, ERROR)
        os.link(stage, name, src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
        published = True
        os.fsync(directory)
        validate()
        require(_remove_owned(directory, stage, identity), ERROR)
        os.fsync(directory)
        validate()
        return rollback
    except Exception:
        rollback()
        raise BoundaryFailure('publication') from None


def _source_inputs(args):
    from operational import checked_contract
    base._source(args.repo, args.source_sha)
    raw = base._read(args.contract)
    contract = base._decode_json(raw)
    checked_contract(contract)
    require(contract['identity']['source_sha'] == args.source_sha, 'Registry contract source differs')
    inputs, inputs_sha256, image = reference._retained_inputs(args.image_inputs)
    ca = base._read(args.ca_file, 1024**2)
    require(sha(ca) == args.ca_sha256, 'Registry CA bundle bytes differ')
    return contract, raw, inputs, inputs_sha256, image, ca


def prepare_action(args):
    contract, raw, inputs, inputs_sha256, image, _ca = _source_inputs(args)
    dependencies = _dependencies(args.repo, contract)
    parent, directory = base._parent(args.directory), None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        observed = os.fstat(directory)
        manifest = action_manifest(retained_image=image, source_sha=args.source_sha,
            pairing_sha256=contract['pairing_sha256'], operational_sha256=contract['operational_sha256'],
            retained_manifest_sha256=inputs['retained_manifest_sha256'], image_refs=inputs['image_refs'],
            attempt=inputs['attempt'], timeout=inputs['total_timeout'], ca_file=args.ca_file, ca_sha256=args.ca_sha256,
            output_directory=args.directory, output_directory_fingerprint={
                'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid}, bindings={
                'repo': args.repo, 'contract_path': args.contract, 'contract_sha256': sha(raw),
                'image_inputs_path': args.image_inputs, 'image_inputs_sha256': inputs_sha256,
                'retained_manifest_path': inputs['retained_manifest_path'],
                'dependency_sha256': dependencies, 'local_files': inputs['local_files']})
        base._write_at(directory, MANIFEST, manifest)
    finally:
        if directory is not None:
            os.close(directory)
        os.close(parent)
    return sha(canonical(manifest))


def execute_action(args):
    manifest = base._json(args.manifest)
    checked_manifest(manifest, args.manifest_sha256)
    context, bindings = manifest['context'], manifest['context']['bindings']
    base._digest(args.runner_sha256)
    require(sha(base._read(str(Path(__file__).absolute()))) == args.runner_sha256 and
            args.manifest == str(Path(context['output_directory']) / MANIFEST), 'Registry runner or path differs')
    source_args = argparse.Namespace(repo=bindings['repo'], source_sha=context['source_sha'],
        contract=bindings['contract_path'], image_inputs=bindings['image_inputs_path'],
        ca_file=context['ca_file'], ca_sha256=context['ca_sha256'])
    contract, raw, inputs, inputs_sha256, image, ca = _source_inputs(source_args)
    require(sha(raw) == bindings['contract_sha256'] and inputs_sha256 == bindings['image_inputs_sha256'] and
            contract['pairing_sha256'] == context['pairing_sha256'] and contract['operational_sha256'] == context['operational_sha256'] and
            _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and image == manifest['retained_image'] and
            inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and inputs['local_files'] == bindings['local_files'] and
            inputs['total_timeout'] == context['timeout'] and all(inputs[key] == context[key] for key in
                ('image_refs', 'attempt', 'retained_manifest_sha256')), 'Registry retained bindings differ')
    directory = base._parent(args.manifest)
    try:
        def output_binding():
            descriptor = base._parent(args.manifest)
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
            base._write_at(directory, MARKER, {'manifest_sha256': args.manifest_sha256})
        def publish(name, raw, validate):
            return publish_artifact(directory, name, raw, validate)
        collector = RegistryMetadata(manifest, transport, consume, publish,
            manifest_sha256=args.manifest_sha256, output_binding=output_binding)
        try:
            result = collector.collect()
        except MetadataFailure as error:
            try:
                base._write_at(directory, RECEIPT, error.receipt)
            except OSError:
                raise Refused(ERROR) from None
            raise Refused(ERROR) from None
        output_binding()
        base._write_at(directory, RECEIPT, result)
    finally:
        os.close(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'contract', 'image-inputs', 'ca-file', 'ca-sha256', 'directory'):
        prepare.add_argument('--' + name, required=True)
    execute = commands.add_parser('execute')
    for name in ('manifest', 'manifest-sha256', 'runner-sha256'):
        execute.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            print('File-only registry metadata manifest prepared; manifest_sha256=' + prepare_action(args))
        else:
            execute_action(args)
            print('Private registry metadata recorded; no local image or admission established')
    except Exception:
        parser.exit(1, ERROR + '\n')


if __name__ == '__main__':
    main()

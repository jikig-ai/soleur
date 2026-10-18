"""Explicit one-use prebuild observations; no profile or execution authority.

The execute CLI requires separate harness approval. Its persistent marker only
prevents replay: neither a marker nor a manifest proves human authorization.
No pulls, discovery, builds, container operations or fallback paths exist here.
Config dictionaries retain exactly the returned fields; omissions receive no
defaults and establish no effective configuration or executable profile.
"""
import argparse
import copy
import json
import math
import os
from pathlib import Path
import re
import stat
import time
from urllib.parse import quote

from image_observations import MAX_CONFIG_BYTES
from prepare import Refused, canonical, git, require, sha

ROLES = ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage')
INPUT_FIELDS = ('source_sha', 'pairing_sha256', 'operational_sha256',
                'retained_manifest_sha256', 'endpoint', 'endpoint_fingerprint',
                'image_refs', 'output_directory', 'output_directory_fingerprint', 'attempt', 'timeout', 'bindings')
DEPENDENCIES = ('prebuild_acquisition.py', 'image_observations.py', 'prepare.py',
                'controller_transports.py', 'controller_inputs.py', 'operational.py',
                'candidate.py', 'role_profiles.py', 'retained_files.py')
VERSION_FIELDS = ('Version', 'ApiVersion', 'MinAPIVersion', 'Os', 'Arch',
                  'KernelVersion', 'GitCommit', 'GoVersion', 'BuildTime')
INFO_FIELDS = ('ID', 'ServerVersion', 'OSType', 'Architecture', 'NCPU',
               'MemTotal', 'SecurityOptions')
ERROR = 'Prebuild acquisition incomplete'
MARKER = '.acquisition-consumed'
MANIFEST = 'action-manifest.json'
RECEIPT = 'acquisition-receipt.json'


def _finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    except (ValueError, OverflowError):
        return False


def _text(value, maximum=1024):
    return type(value) is str and 0 < len(value) <= maximum and all(
        32 <= ord(character) <= 126 for character in value)


def _path(value, maximum=4096):
    require(_text(value, maximum) and value.startswith('/') and '//' not in value and
            not value.endswith('/') and all(part not in ('.', '..') for part in value.split('/')),
            'Explicit direct absolute path required')


def _digest(value):
    require(type(value) is str and re.fullmatch('[0-9a-f]{64}', value), 'SHA-256 binding required')


def action_manifest(**values):
    """Pure exact GET plan. Every input must be explicit; no files are read."""
    require(set(values) == set(INPUT_FIELDS), 'Exact acquisition inputs required')
    value = copy.deepcopy(values)
    require(type(value['source_sha']) is str and re.fullmatch('[0-9a-f]{40}', value['source_sha']),
            'Full source SHA required')
    for key in ('pairing_sha256', 'operational_sha256', 'retained_manifest_sha256'):
        _digest(value[key])
    _path(value['endpoint'], 100)
    _path(value['output_directory'])
    for key in ('endpoint_fingerprint', 'output_directory_fingerprint'):
        fingerprint = value[key]
        require(type(fingerprint) is dict and set(fingerprint) == {'dev', 'ino', 'uid'} and
                all(type(item) is int and item >= 0 for item in fingerprint.values()),
                'Exact filesystem fingerprint required')
    require(_text(value['attempt'], 128) and re.fullmatch('[A-Za-z0-9_-]+', value['attempt']),
            'Bounded attempt required')
    require(_finite(value['timeout']) and 0 < value['timeout'] <= 60, 'Total timeout exceeds bound')
    refs = value['image_refs']
    require(type(refs) is dict and set(refs) == set(ROLES), 'Six exact image references required')
    for ref in refs.values():
        require(_text(ref, 512) and re.fullmatch(
            r'[a-z0-9][a-z0-9.:-]*(?:/[a-z0-9][a-z0-9._-]*)+@sha256:[0-9a-f]{64}', ref),
            'Explicit immutable repository digest required')
    bindings = value['bindings']
    require(type(bindings) is dict and set(bindings) == {'repo', 'contract_path',
            'contract_sha256', 'image_inputs_path', 'image_inputs_sha256', 'retained_manifest_path',
            'dependency_sha256', 'local_files'},
            'Exact retained file bindings required')
    for key in ('repo', 'contract_path', 'image_inputs_path', 'retained_manifest_path'):
        _path(bindings[key])
    _digest(bindings['contract_sha256'])
    _digest(bindings['image_inputs_sha256'])
    for key in ('dependency_sha256', 'local_files'):
        require(type(bindings[key]) is dict and len(bindings[key]) <= 32, 'Bounded file census required')
        for path, digest in bindings[key].items():
            require(_text(path), 'Bounded file name required')
            _digest(digest)
    actions = [{'method': 'GET', 'path': path, 'payload_sha256': sha(b'')}
               for path in ['/version', '/info'] + [
                   '/images/' + quote(ref, safe='') + '/json' for ref in sorted(set(refs.values()))]]
    return {'version': 1, **value, 'platform': 'linux/amd64', 'actions': actions,
            'marker_name': MARKER, 'receipt_name': RECEIPT, 'execute_authorized': False,
            'profile_admissible': False, 'issuer_verification': 'pending', 'independent_review': 'pending'}


def checked_manifest(manifest, expected_sha256):
    _digest(expected_sha256)
    require(type(manifest) is dict and len(canonical(manifest)) <= 65536 and
            sha(canonical(manifest)) == expected_sha256, 'Acquisition manifest digest differs')
    require(all(key in manifest for key in INPUT_FIELDS) and manifest == action_manifest(
        **{key: manifest[key] for key in INPUT_FIELDS}), 'Acquisition manifest fields differ')


def _parent(path):
    """Pin every ancestor using descriptor-relative no-follow directory opens."""
    _path(str(path))
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for component in Path(path).parts[1:-1]:
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def socket_fingerprint(endpoint):
    descriptor = _parent(endpoint)
    try:
        observed = os.stat(Path(endpoint).name, dir_fd=descriptor, follow_symlinks=False)
        require(stat.S_ISSOCK(observed.st_mode), 'Explicit endpoint is not a direct socket')
        return {'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid}
    finally:
        os.close(descriptor)


class AcquisitionFailure(Refused):
    def __init__(self, receipt):
        super().__init__(ERROR)
        self.receipt = copy.deepcopy(receipt)


class PrebuildAcquisition:
    """One pass over an explicitly bound injected transport; construction has no I/O."""
    def __init__(self, manifest, transport, consume_gate, *, manifest_sha256,
                 clock=time.monotonic, endpoint_probe=None, output_binding=None):
        endpoint_probe = socket_fingerprint if endpoint_probe is None else endpoint_probe
        output_binding = (lambda: None) if output_binding is None else output_binding
        checked_manifest(manifest, manifest_sha256)
        require(getattr(transport, 'endpoint', None) == manifest['endpoint'] and
                callable(getattr(transport, 'request', None)) and callable(consume_gate) and
                callable(clock) and callable(endpoint_probe) and callable(output_binding),
                'Explicit bound acquisition interfaces required')
        self.manifest = copy.deepcopy(manifest)
        self.digest = manifest_sha256
        self.transport, self.gate, self.clock, self.probe = transport, consume_gate, clock, endpoint_probe
        self.output_binding = output_binding
        self.attempted = False

    def collect(self):
        require(not self.attempted, 'Acquisition is one-use')
        checked_manifest(self.manifest, self.digest)
        self.attempted = True
        result = {'status': 'incomplete', 'manifest_sha256': self.digest,
                  'source_sha': self.manifest['source_sha'],
                  'pairing_sha256': self.manifest['pairing_sha256'],
                  'operational_sha256': self.manifest['operational_sha256'],
                  'retained_manifest_sha256': self.manifest['retained_manifest_sha256'],
                  'endpoint': self.manifest['endpoint'],
                  'endpoint_fingerprint': copy.deepcopy(self.manifest['endpoint_fingerprint']),
                  'attempt': self.manifest['attempt'], 'daemon': {}, 'roles': {},
                  'request_count': 0, 'started_at_monotonic': None, 'finished_at_monotonic': None,
                  'execute_authorized': False, 'profile_admissible': False,
                  'authentication_established': False, 'ownership_verified': False,
                  'quiescence_verified': False, 'issuer_verification': 'pending',
                  'independent_review': 'pending', 'runtime_evidence': 'untrusted-prebuild-observations'}
        last = None
        failure = {'action_index': None, 'request_path_sha256': None, 'reference_sha256': None,
                   'phase': 'initialization', 'reason': 'unexpected_failure', 'status_code': None}
        actions = copy.deepcopy(self.manifest['actions'])
        references = {'/images/' + quote(ref, safe='') + '/json': ref
                      for ref in self.manifest['image_refs'].values()}
        def enter(phase, reason='unexpected_failure'):
            failure.update(phase=phase, reason=reason)
        def check(condition, reason):
            if not condition:
                failure['reason'] = reason
                raise Refused(ERROR)
        def finish():
            result['finished_at_monotonic'] = last
            result['receipt_sha256'] = sha(canonical(result))
            return result
        try:
            start = self.clock()
            require(_finite(start), ERROR)
            deadline, last = start + self.manifest['timeout'], start
            result['started_at_monotonic'] = start
            require(_finite(deadline) and deadline > start, ERROR)

            def remaining():
                nonlocal last
                enter('deadline')
                now = self.clock()
                require(_finite(now) and now >= last and now < deadline, ERROR)
                last = now
                return min(10, deadline - now)

            def bindings(phase):
                enter(phase, 'source_binding')
                checked_manifest(self.manifest, self.digest)
                enter(phase, 'endpoint_binding')
                require(self.transport.endpoint == self.manifest['endpoint'] and
                        self.probe(self.manifest['endpoint']) == self.manifest['endpoint_fingerprint'], ERROR)
                enter(phase, 'output_binding')
                self.output_binding()

            def publication_checks():
                remaining()
                bindings('post_request_binding')
                remaining()

            enter('consume_gate', 'output_binding')
            self.output_binding()
            enter('consume_gate')
            self.gate()
            for index, action in enumerate(actions, 1):
                ref = references.get(action['path'])
                failure.update(action_index=index, request_path_sha256=sha(action['path'].encode()),
                               reference_sha256=sha(ref.encode()) if ref is not None else None, status_code=None)
                bindings('pre_request_binding')
                timeout = remaining()
                result['request_count'] += 1
                enter('transport')
                response = self.transport.request('GET', action['path'], b'', timeout=timeout)
                if type(response) is tuple and len(response) == 2 and type(response[0]) is int and 100 <= response[0] <= 599:
                    failure['status_code'] = response[0]
                remaining()
                bindings('post_request_binding')
                enter('response_validation', 'receipt_shape')
                require(type(response) is tuple and len(response) == 2 and
                        failure['status_code'] is not None, ERROR)
                check(response[0] == 200, 'http_status')
                require(type(response[1]) is dict, ERROR)
                data = response[1]
                if action['path'] == '/version':
                    enter('version_validation', 'receipt_shape')
                    require(all(key in data for key in ('Version', 'ApiVersion', 'Os', 'Arch')) and
                            all(_text(data[key]) for key in VERSION_FIELDS if key in data), ERROR)
                    check(data['Os'] == 'linux' and data['Arch'] == 'amd64', 'platform')
                    projected = {key: data[key] for key in VERSION_FIELDS if key in data}
                    publication_checks()
                    result['daemon']['version'] = projected
                elif action['path'] == '/info':
                    enter('info_validation', 'receipt_shape')
                    require(all(_text(data.get(key)) for key in INFO_FIELDS[:4]) and
                            data['ServerVersion'] == result['daemon']['version']['Version'] and
                            all(type(data.get(key)) is int and 0 < data[key] < 2**63 for key in ('NCPU', 'MemTotal')) and
                            type(data.get('SecurityOptions')) is list and len(data['SecurityOptions']) <= 64 and
                            all(_text(item) for item in data['SecurityOptions']), ERROR)
                    check(data['OSType'] == 'linux' and data['Architecture'] in ('amd64', 'x86_64'), 'platform')
                    projected = copy.deepcopy({key: data[key] for key in INFO_FIELDS})
                    publication_checks()
                    result['daemon']['info'] = projected
                else:
                    enter('image_validation')
                    check(_text(data.get('Id')) and re.fullmatch('sha256:[0-9a-f]{64}', data['Id']), 'immutable_id')
                    check(type(data.get('RepoDigests')) is list and len(data['RepoDigests']) <= 128 and
                          all(_text(item, 512) for item in data['RepoDigests']) and ref in data['RepoDigests'],
                          'repository_digest_membership')
                    check(data.get('Os') == 'linux' and data.get('Architecture') == 'amd64' and
                          ('Variant' not in data or data['Variant'] == ''), 'platform')
                    enter('image_validation', 'config_shape')
                    check(type(data.get('Config')) is dict, 'config_shape')
                    config_bytes = canonical(data['Config'])
                    check(len(config_bytes) <= MAX_CONFIG_BYTES, 'config_size')
                    observation = {'requested_reference': ref, 'image_id': data['Id'],
                                   'config': copy.deepcopy(data['Config']),
                                   'repo_digests': copy.deepcopy(data['RepoDigests']),
                                   'config_sha256': sha(config_bytes),
                                   'platform': 'linux/amd64', 'daemon_id': result['daemon']['info']['ID']}
                    if 'Variant' in data:
                        observation['variant'] = data['Variant']
                    projected = {role: copy.deepcopy(observation)
                                 for role, selected in self.manifest['image_refs'].items() if selected == ref}
                    publication_checks()
                    result['roles'].update(projected)
            result['status'] = 'complete'
            return finish()
        except Exception:
            result['error'] = ERROR
            result['failure'] = failure
            raise AcquisitionFailure(finish()) from None


def _read(path, maximum=2 * 1024**2):
    parent = _parent(path)
    descriptor = None
    try:
        descriptor = os.open(Path(path).name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        observed = os.fstat(descriptor)
        require(stat.S_ISREG(observed.st_mode) and observed.st_size <= maximum, 'Bounded regular file required')
        with os.fdopen(descriptor, 'rb') as stream:
            descriptor = None
            data = stream.read(maximum + 1)
        require(len(data) <= maximum, 'File exceeds bound')
        return data
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent)


def _decode_json(data):
    def number(value):
        parsed = float(value)
        require(math.isfinite(parsed), 'Nonfinite JSON')
        return parsed
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=pairs, parse_float=number,
                      parse_constant=lambda _value: (_ for _ in ()).throw(Refused('Nonfinite JSON')))


def _json(path):
    return _decode_json(_read(path))


def _write_at(directory_fd, name, value):
    descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory_fd)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(canonical(value) + b'\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.fsync(directory_fd)


def _source(repo, source):
    require(git(Path(repo), '-c', 'core.fsmonitor=false', 'rev-parse', 'HEAD').decode().strip() == source and
            not git(Path(repo), '-c', 'core.fsmonitor=false', 'status', '--porcelain', '--untracked-files=no').strip(),
            'Exact clean source HEAD required')


def _dependencies(repo, contract):
    result = {}
    for name in DEPENDENCIES:
        path = 'scripts/codex-qualification/' + name
        digest = sha(_read(str(Path(repo) / path)))
        require(contract.get('source_references', {}).get(path, {}).get('sha256') == digest and
                sha(git(Path(repo), '-c', 'core.fsmonitor=false', 'show',
                        contract['identity']['source_sha'] + ':' + path)) == digest and
                sha(_read(str(Path(__file__).parent / name))) == digest,
                'Executing dependency differs from committed contract')
        result[name] = digest
    return result


def _inputs(path):
    raw = _read(path)
    value = _decode_json(raw)
    require(type(value) is dict and set(value) == {'attempt', 'image_refs', 'local_files',
            'total_timeout', 'retained_manifest_path', 'retained_manifest_sha256'}, 'Exact image inputs required')
    _digest(value['retained_manifest_sha256'])
    retained_raw = _read(value['retained_manifest_path'])
    require(sha(retained_raw) == value['retained_manifest_sha256'],
            'Retained manifest bytes differ')
    retained = _decode_json(retained_raw)
    require(type(retained) is dict and type(retained.get('images')) is list and
            len(retained['images']) == 6 and type(value['image_refs']) is dict and
            all(type(item) is dict and item.get('platform') == 'linux/amd64' and
                _text(item.get('source_repository'), 400) and _text(item.get('manifest_digest'), 80)
                for item in retained['images']) and
            {item['source_repository'] + '@' + item['manifest_digest'] for item in retained['images']} ==
            set(value['image_refs'].values()), 'Selected refs differ from retained platform manifest')
    require(type(value['local_files']) is dict and len(value['local_files']) <= 32, 'Bounded local files required')
    for path, digest in value['local_files'].items():
        _digest(digest)
        require(sha(_read(path, 128 * 1024**2)) == digest, 'Retained local file differs')
    return value, sha(raw)


def prepare_action(args):
    from operational import checked_contract
    _source(args.repo, args.source_sha)
    contract_raw = _read(args.contract)
    contract = _decode_json(contract_raw)
    inputs, inputs_sha256 = _inputs(args.image_inputs)
    checked_contract(contract)
    require(contract['identity'].get('source_sha') == args.source_sha, 'Contract source differs')
    parent = _parent(args.directory)
    directory = None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        observed = os.fstat(directory)
        manifest = action_manifest(source_sha=args.source_sha, pairing_sha256=contract['pairing_sha256'],
        operational_sha256=contract['operational_sha256'],
        retained_manifest_sha256=inputs['retained_manifest_sha256'], endpoint=args.endpoint,
        endpoint_fingerprint=socket_fingerprint(args.endpoint), image_refs=inputs['image_refs'],
        output_directory=args.directory,
        output_directory_fingerprint={'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid},
        attempt=inputs['attempt'], timeout=inputs['total_timeout'],
        bindings={'repo': args.repo, 'contract_path': args.contract,
                  'contract_sha256': sha(contract_raw), 'image_inputs_path': args.image_inputs,
                  'image_inputs_sha256': inputs_sha256,
                  'retained_manifest_path': inputs['retained_manifest_path'],
                  'dependency_sha256': _dependencies(args.repo, contract), 'local_files': inputs['local_files']})
        _write_at(directory, MANIFEST, manifest)
    finally:
        if directory is not None:
            os.close(directory)
        os.close(parent)
    return sha(canonical(manifest))


def execute_action(args):
    from controller_transports import UnixJsonTransport
    from operational import checked_contract
    manifest = _json(args.manifest)
    checked_manifest(manifest, args.manifest_sha256)
    _digest(args.runner_sha256)
    require(args.runner_sha256 == sha(_read(str(Path(__file__).absolute()))) and
            args.manifest == str(Path(manifest['output_directory']) / MANIFEST), 'Runner or manifest path differs')
    bindings = manifest['bindings']
    _source(bindings['repo'], manifest['source_sha'])
    contract_raw = _read(bindings['contract_path'])
    contract = _decode_json(contract_raw)
    inputs, inputs_sha256 = _inputs(bindings['image_inputs_path'])
    checked_contract(contract)
    require(sha(contract_raw) == bindings['contract_sha256'] and
            inputs_sha256 == bindings['image_inputs_sha256'] and
            inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and
            contract['identity']['source_sha'] == manifest['source_sha'] and
            contract['pairing_sha256'] == manifest['pairing_sha256'] and
            contract['operational_sha256'] == manifest['operational_sha256'] and
            _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and
            all(inputs[key] == manifest[key] for key in ('image_refs', 'attempt', 'retained_manifest_sha256')) and
            inputs['local_files'] == bindings['local_files'] and inputs['total_timeout'] == manifest['timeout'],
            'Retained acquisition bindings differ')
    output_parent = _parent(args.manifest)
    try:
        observed = os.fstat(output_parent)
        require(stat.S_IMODE(observed.st_mode) == 0o700 and observed.st_uid == os.getuid() and
                {'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid} ==
                manifest['output_directory_fingerprint'],
                'Private owned output directory required')
        transport = UnixJsonTransport(contract, manifest['endpoint'])
        def current_output():
            descriptor = _parent(args.manifest)
            try:
                current = os.fstat(descriptor)
                require((current.st_dev, current.st_ino, current.st_uid) ==
                        (observed.st_dev, observed.st_ino, observed.st_uid) and
                        stat.S_IMODE(current.st_mode) == 0o700, ERROR)
            finally:
                os.close(descriptor)
        class BoundTransport:
            endpoint = manifest['endpoint']
            request = staticmethod(transport.request)
        def consume():
            _write_at(output_parent, MARKER, {'manifest_sha256': args.manifest_sha256})
        collector = PrebuildAcquisition(manifest, BoundTransport(), consume,
                                       manifest_sha256=args.manifest_sha256, output_binding=current_output)
        try:
            result = collector.collect()
        except AcquisitionFailure as error:
            try:
                _write_at(output_parent, RECEIPT, error.receipt)
            except OSError:
                pass
            raise Refused(ERROR) from None
        current_output()
        _write_at(output_parent, RECEIPT, result)
    finally:
        os.close(output_parent)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'contract', 'image-inputs', 'endpoint', 'directory'):
        prepare.add_argument('--' + name, required=True)
    execute = commands.add_parser('execute')
    for name in ('manifest', 'manifest-sha256', 'runner-sha256'):
        execute.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            digest = prepare_action(args)
            print('File-only acquisition manifest prepared; manifest_sha256=' + digest)
        else:
            execute_action(args)
            print('Private acquisition receipt recorded; authority remains pending')
    except Exception:
        parser.exit(1, ERROR + '\n')


if __name__ == '__main__':
    main()

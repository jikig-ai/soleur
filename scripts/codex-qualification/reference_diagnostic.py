"""Finite Mailpit lookup observations, requiring separate exact harness approval.

Registry manifest/Config digests are lookup candidates, never asserted local IDs.
Only the three pre-enumerated candidate 404s advance. No tags, enumeration,
pulls, retry, profile admission or inference about stored layers exists here.
"""
import argparse
import copy
import os
from pathlib import Path
import re
import stat
import time
from urllib.parse import quote

import prebuild_acquisition as base
from prepare import Refused, canonical, require, sha

ERROR = 'Reference diagnostic incomplete'
MANIFEST = 'reference-diagnostic-manifest.json'
MARKER = '.reference-diagnostic-consumed'
RECEIPT = 'reference-diagnostic-receipt.json'
REPOSITORY = 'docker.io/axllent/mailpit'


def action_manifest(*, retained_image, **context):
    """Pure plan over explicit bindings and four fields projected from retained bytes."""
    base.action_manifest(**context)
    require(context['timeout'] == 60, 'Diagnostic total timeout must be 60 seconds')
    require(type(retained_image) is dict and set(retained_image) == {
        'source_repository', 'manifest_digest', 'image_id', 'platform'} and
        retained_image['source_repository'] == REPOSITORY and retained_image['platform'] == 'linux/amd64',
        'Exact retained Mailpit platform entry required')
    for field in ('manifest_digest', 'image_id'):
        require(type(retained_image[field]) is str and
                re.fullmatch('sha256:[0-9a-f]{64}', retained_image[field]), 'Immutable lookup digest required')
    require(retained_image['manifest_digest'] != retained_image['image_id'] and
            context['image_refs']['inbucket'] == REPOSITORY + '@' + retained_image['manifest_digest'],
            'Distinct retained Mailpit lookups and role pin required')
    candidates = [('repository-platform', REPOSITORY.removeprefix('docker.io/') + '@' + retained_image['manifest_digest']),
                  ('platform-digest', retained_image['manifest_digest']),
                  ('registry-config-digest', retained_image['image_id'])]
    actions = [{'kind': kind, 'lookup': lookup, 'method': 'GET', 'path': path, 'payload_sha256': sha(b'')}
               for kind, lookup, path in [('daemon-version', None, '/version'), ('daemon-info', None, '/info')] +
               [(kind, lookup, '/images/' + quote(lookup, safe='') + '/json') for kind, lookup in candidates]]
    return {'version': 1, 'kind': 'mailpit-reference-diagnostic', 'context': copy.deepcopy(context),
            'retained_image': copy.deepcopy(retained_image), 'actions': actions,
            'marker_name': MARKER, 'receipt_name': RECEIPT, 'execute_authorized': False,
            'profile_admissible': False, 'issuer_verification': 'pending', 'independent_review': 'pending'}


def checked_manifest(manifest, expected_sha256):
    base._digest(expected_sha256)
    require(type(manifest) is dict and len(canonical(manifest)) <= 65536 and
            sha(canonical(manifest)) == expected_sha256 and 'context' in manifest and 'retained_image' in manifest,
            'Diagnostic manifest digest differs')
    expected = action_manifest(retained_image=manifest['retained_image'], **manifest['context'])
    require(canonical(expected) == canonical(manifest), 'Diagnostic manifest fields differ')


class DiagnosticFailure(Refused):
    def __init__(self, receipt):
        super().__init__(ERROR)
        self.receipt = copy.deepcopy(receipt)


class ReferenceDiagnostic:
    """An injected one-pass transport. Construction performs no I/O."""
    def __init__(self, manifest, transport, consume_gate, *, manifest_sha256,
                 clock=time.monotonic, endpoint_probe=None, output_binding=None):
        checked_manifest(manifest, manifest_sha256)
        endpoint_probe = base.socket_fingerprint if endpoint_probe is None else endpoint_probe
        output_binding = (lambda: None) if output_binding is None else output_binding
        require(getattr(transport, 'endpoint', None) == manifest['context']['endpoint'] and
                all(callable(value) for value in (getattr(transport, 'request', None), consume_gate,
                                                  clock, endpoint_probe, output_binding)),
                'Explicit bound diagnostic interfaces required')
        self.manifest, self.digest = copy.deepcopy(manifest), manifest_sha256
        self.transport, self.gate, self.clock = transport, consume_gate, clock
        self.probe, self.output_binding, self.attempted = endpoint_probe, output_binding, False

    def collect(self):
        require(not self.attempted, 'Diagnostic is one-use')
        checked_manifest(self.manifest, self.digest)
        self.attempted = True
        context = copy.deepcopy(self.manifest['context'])
        plan = copy.deepcopy(self.manifest['actions'])
        states = [{'action_index': index, 'request_path_sha256': sha(action['path'].encode()),
                   'reference_sha256': sha(action['lookup'].encode()) if action['lookup'] is not None else None,
                   'phase': 'initialization', 'reason': 'not_attempted', 'status_code': None}
                  for index, action in enumerate(plan, 1)]
        result = {'status': 'incomplete', 'manifest_sha256': self.digest,
                  'source_sha': context['source_sha'], 'pairing_sha256': context['pairing_sha256'],
                  'operational_sha256': context['operational_sha256'],
                  'retained_manifest_sha256': context['retained_manifest_sha256'],
                  'attempt': context['attempt'], 'endpoint': context['endpoint'],
                  'endpoint_fingerprint': context['endpoint_fingerprint'], 'daemon': {},
                  'actions': states, 'observations': {}, 'request_count': 0,
                  'started_at_monotonic': None, 'finished_at_monotonic': None,
                  'execute_authorized': False, 'profile_admissible': False, 'authentication_established': False,
                  'ownership_verified': False, 'quiescence_verified': False,
                  'issuer_verification': 'pending', 'independent_review': 'pending',
                  'runtime_evidence': 'untrusted-reference-diagnostic-observations'}
        current = {'action_index': None, 'request_path_sha256': None, 'reference_sha256': None,
                   'phase': 'initialization', 'reason': 'unexpected_failure', 'status_code': None}
        last = None
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
            def bindings(phase):
                enter(phase, 'source_binding')
                checked_manifest(self.manifest, self.digest)
                enter(phase, 'endpoint_binding')
                require(self.transport.endpoint == context['endpoint'] and
                        self.probe(context['endpoint']) == context['endpoint_fingerprint'], ERROR)
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
            for action, current in zip(plan, states):
                bindings('pre_request_binding')
                timeout = remaining()
                enter('transport')
                result['request_count'] += 1
                response = self.transport.request('GET', action['path'], b'', timeout=timeout)
                if type(response) is tuple and len(response) == 2 and type(response[0]) is int and 100 <= response[0] <= 599:
                    current['status_code'] = response[0]
                remaining()
                bindings('post_request_binding')
                enter('response_validation', 'receipt_shape')
                require(type(response) is tuple and len(response) == 2 and current['status_code'] is not None, ERROR)
                if action['lookup'] is not None and response[0] == 404:
                    publication_checks()
                    enter('response_validation', 'expected_not_found')
                    continue
                check(response[0] == 200, 'http_status')
                require(type(response[1]) is dict, ERROR)
                data = response[1]
                if action['path'] == '/version':
                    enter('version_validation', 'receipt_shape')
                    require(all(key in data for key in ('Version', 'ApiVersion', 'Os', 'Arch')) and
                            all(base._text(data[key]) for key in base.VERSION_FIELDS if key in data), ERROR)
                    check(data['Os'] == 'linux' and data['Arch'] == 'amd64', 'platform')
                    projected = {key: data[key] for key in base.VERSION_FIELDS if key in data}
                    publication_checks()
                    result['daemon']['version'] = projected
                    enter('version_validation', 'observed')
                elif action['path'] == '/info':
                    enter('info_validation', 'receipt_shape')
                    require(all(base._text(data.get(key)) for key in base.INFO_FIELDS[:4]) and
                            data['ServerVersion'] == result['daemon']['version']['Version'] and
                            all(type(data.get(key)) is int and 0 < data[key] < 2**63 for key in ('NCPU', 'MemTotal')) and
                            type(data.get('SecurityOptions')) is list and len(data['SecurityOptions']) <= 64 and
                            all(base._text(item) for item in data['SecurityOptions']), ERROR)
                    check(data['OSType'] == 'linux' and data['Architecture'] in ('amd64', 'x86_64'), 'platform')
                    projected = copy.deepcopy({key: data[key] for key in base.INFO_FIELDS})
                    publication_checks()
                    result['daemon']['info'] = projected
                    enter('info_validation', 'observed')
                else:
                    enter('image_validation')
                    check(base._text(data.get('Id')) and re.fullmatch('sha256:[0-9a-f]{64}', data['Id']), 'immutable_id')
                    check(data.get('Os') == 'linux' and data.get('Architecture') == 'amd64' and
                          ('Variant' not in data or data['Variant'] == ''), 'platform')
                    enter('image_validation', 'config_shape')
                    check(type(data.get('Config')) is dict, 'config_shape')
                    encoded = canonical(data['Config'])
                    check(len(encoded) <= base.MAX_CONFIG_BYTES, 'config_size')
                    enter('image_validation', 'receipt_shape')
                    digests = data.get('RepoDigests')
                    require(digests is None or (type(digests) is list and len(digests) <= 128 and
                            all(base._text(item, 512) for item in digests)), ERROR)
                    original = REPOSITORY + '@' + self.manifest['retained_image']['manifest_digest']
                    short = original.removeprefix('docker.io/')
                    observed = {'lookup_kind': action['kind'], 'lookup_sha256': sha(action['lookup'].encode()),
                                'image_id': data['Id'], 'platform': 'linux/amd64',
                                'daemon_id': result['daemon']['info']['ID'],
                                'config': copy.deepcopy(data['Config']), 'config_sha256': sha(encoded),
                                'repo_digests_state': 'absent' if 'RepoDigests' not in data else
                                                      'null' if digests is None else 'present',
                                'exact_reference_matches': [ref for ref in (original, short) if ref in (digests or [])],
                                'reference_membership_verification': 'pending'}
                    if 'RepoDigests' in data:
                        observed['repo_digests'] = copy.deepcopy(digests)
                    if 'Variant' in data:
                        observed['variant'] = data['Variant']
                    publication_checks()
                    result['observations'][action['kind']] = observed
                    enter('image_validation', 'observed')
            result['status'] = 'diagnostic-sequence-completed'
            result['outcome'] = ('immutable-lookup-observations-recorded' if result['observations'] else
                                 'none-approved-immutable-lookup-forms-resolved')
            return finish()
        except Exception:
            result['error'] = ERROR
            result['failure'] = copy.deepcopy(current)
            raise DiagnosticFailure(finish()) from None


def _dependencies(repo, contract):
    result = base._dependencies(repo, contract)
    name = 'reference_diagnostic.py'
    path = 'scripts/codex-qualification/' + name
    digest = sha(base._read(str(Path(repo) / path)))
    require(contract.get('source_references', {}).get(path, {}).get('sha256') == digest and
            sha(base.git(Path(repo), '-c', 'core.fsmonitor=false', 'show', contract['identity']['source_sha'] + ':' + path)) == digest and
            sha(base._read(str(Path(__file__).absolute()))) == digest, 'Executing diagnostic source differs')
    return {**result, name: digest}


def _retained_inputs(path):
    inputs, digest = base._inputs(path)
    raw = base._read(inputs['retained_manifest_path'])
    require(sha(raw) == inputs['retained_manifest_sha256'], 'Retained diagnostic bytes differ')
    images = base._decode_json(raw)['images']
    selected = [image for image in images if image.get('source_repository') == REPOSITORY]
    require(len(selected) == 1 and all(key in selected[0] for key in
            ('source_repository', 'manifest_digest', 'image_id', 'platform')), 'One retained Mailpit entry required')
    image = {key: selected[0][key] for key in ('source_repository', 'manifest_digest', 'image_id', 'platform')}
    return inputs, digest, image


def prepare_action(args):
    from operational import checked_contract
    base._source(args.repo, args.source_sha)
    raw = base._read(args.contract)
    contract = base._decode_json(raw)
    inputs, inputs_sha256, image = _retained_inputs(args.image_inputs)
    checked_contract(contract)
    require(contract['identity'].get('source_sha') == args.source_sha, 'Diagnostic contract source differs')
    dependencies = _dependencies(args.repo, contract)
    parent = base._parent(args.directory)
    directory = None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        observed = os.fstat(directory)
        manifest = action_manifest(retained_image=image, source_sha=args.source_sha,
            pairing_sha256=contract['pairing_sha256'], operational_sha256=contract['operational_sha256'],
            retained_manifest_sha256=inputs['retained_manifest_sha256'], endpoint=args.endpoint,
            endpoint_fingerprint=base.socket_fingerprint(args.endpoint), image_refs=inputs['image_refs'],
            output_directory=args.directory, output_directory_fingerprint={
                'dev': observed.st_dev, 'ino': observed.st_ino, 'uid': observed.st_uid},
            attempt=inputs['attempt'], timeout=inputs['total_timeout'], bindings={
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
    from controller_transports import UnixJsonTransport
    from operational import checked_contract
    manifest = base._json(args.manifest)
    checked_manifest(manifest, args.manifest_sha256)
    context, bindings = manifest['context'], manifest['context']['bindings']
    base._digest(args.runner_sha256)
    require(sha(base._read(str(Path(__file__).absolute()))) == args.runner_sha256 and
            args.manifest == str(Path(context['output_directory']) / MANIFEST), 'Diagnostic runner or path differs')
    base._source(bindings['repo'], context['source_sha'])
    raw = base._read(bindings['contract_path'])
    contract = base._decode_json(raw)
    inputs, inputs_sha256, image = _retained_inputs(bindings['image_inputs_path'])
    checked_contract(contract)
    require(sha(raw) == bindings['contract_sha256'] and inputs_sha256 == bindings['image_inputs_sha256'] and
            inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and
            contract['identity']['source_sha'] == context['source_sha'] and
            contract['pairing_sha256'] == context['pairing_sha256'] and
            contract['operational_sha256'] == context['operational_sha256'] and
            _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and
            image == manifest['retained_image'] and inputs['local_files'] == bindings['local_files'] and
            inputs['total_timeout'] == context['timeout'] and all(inputs[key] == context[key] for key in
                ('image_refs', 'attempt', 'retained_manifest_sha256')), 'Diagnostic retained bindings differ')
    directory = base._parent(args.manifest)
    try:
        def current_output():
            descriptor = base._parent(args.manifest)
            try:
                current, pinned = os.fstat(descriptor), os.fstat(directory)
                require((current.st_dev, current.st_ino) == (pinned.st_dev, pinned.st_ino) and
                        current.st_uid == os.getuid() and stat.S_IMODE(current.st_mode) == 0o700 and
                        {'dev': current.st_dev, 'ino': current.st_ino, 'uid': current.st_uid} ==
                        context['output_directory_fingerprint'], ERROR)
            finally:
                os.close(descriptor)
        current_output()
        transport = UnixJsonTransport(contract, context['endpoint'])
        class BoundTransport:
            endpoint = context['endpoint']
            request = staticmethod(transport.request)
        def consume():
            base._write_at(directory, MARKER, {'manifest_sha256': args.manifest_sha256})
        collector = ReferenceDiagnostic(manifest, BoundTransport(), consume,
            manifest_sha256=args.manifest_sha256, output_binding=current_output)
        try:
            result = collector.collect()
        except DiagnosticFailure as error:
            try:
                base._write_at(directory, RECEIPT, error.receipt)
            except OSError:
                raise Refused(ERROR) from None
            raise Refused(ERROR) from None
        current_output()
        base._write_at(directory, RECEIPT, result)
    finally:
        os.close(directory)


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
            print('File-only reference diagnostic prepared; manifest_sha256=' + prepare_action(args))
        else:
            execute_action(args)
            print('Private diagnostic sequence recorded; qualification remains pending')
    except Exception:
        parser.exit(1, ERROR + '\n')


if __name__ == '__main__':
    main()

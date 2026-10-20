"""Dormant, one-use Config acquisition source; every operational action needs approval.

Preparation and execution are separate entry points. This module was implemented
under source/offline-test authority only. Neither a manifest nor a replay marker
is permission. No Config, token or signed Location is ever published.
"""
import argparse
import copy
import os
from pathlib import Path
import resource
import ssl
import stat
import sys
import time

import config_https as https
import config_schema
import redirect_diagnostic as diagnostic
import registry_metadata as metadata
from prepare import Refused, canonical, require, sha

ERROR = 'Config acquisition incomplete'
MANIFEST = 'config-acquisition-manifest.json'
MARKER = '.config-acquisition-consumed'
RECEIPT = 'config-acquisition-receipt.json'
CONFIG_DIGEST = https.CONFIG_DIGEST
CONFIG_SIZE = 2646
PLATFORM_SHA256 = '168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f'
ROLES = ('token', 'registry', 'destination')
AUTHORITY = ('destination_ownership', 'publisher_verified', 'issuer_verified', 'profile_admitted',
             'runtime_authorized', 'recovery_authorized', 'hosted_auth_cleared', 'qualified')
PRECONSUMPTION_STAGES = ('startup', 'manifest', 'source_binding', 'private_output',
                         'tls_setup', 'preconsume', 'gate_write')
DEPENDENCIES = ('config_acquisition.py', 'config_https.py', 'config_resolver.py', 'config_schema.py',
                'test_config_acquisition.py', 'test_config_https.py', 'test_config_schema.py',
                'test_config_execution.py')


def _ensure(value, code='binding'):
    if not value:
        raise https.TransportRefused(code)


def _integer(value, maximum):
    return type(value) is int and 0 <= value <= maximum


def runtime_identity():
    return {'interpreter': str(Path(sys.executable).absolute()),
            'python': list(sys.version_info[:3]), 'openssl': ssl.OPENSSL_VERSION}


def config_descriptor():
    return {'mediaType': https.CONFIG_MEDIA, 'digest': CONFIG_DIGEST, 'size': CONFIG_SIZE}


def action_manifest(*, retained_image, platform_evidence, schema_reference_closure,
                    runtime=None, **context):
    """In-memory plan constructor. It reads/writes no files and contacts nothing."""
    common = diagnostic.action_manifest(retained_image=retained_image,
        platform_evidence={k: v for k, v in platform_evidence.items() if k != 'layer_count'}, **context)
    _ensure(retained_image['image_id'] == CONFIG_DIGEST and
            retained_image['manifest_digest'] == 'sha256:' + PLATFORM_SHA256)
    _ensure(type(platform_evidence) is dict and set(platform_evidence) == {
        'path', 'sha256', 'bytes', 'config_descriptor', 'layer_count'} and
        platform_evidence['sha256'] == PLATFORM_SHA256 and
        type(platform_evidence['bytes']) is int and platform_evidence['bytes'] == 864 and
        platform_evidence['config_descriptor'] == config_descriptor() and
        _integer(platform_evidence['layer_count'], 128))
    metadata.base._digest(schema_reference_closure)
    _ensure('config_acquisition.py' in context['bindings']['dependency_sha256'])
    identity = context['output_directory_fingerprint']
    _ensure(all(_integer(identity[key], 2**(32 if key == 'uid' else 64) - 1) for key in identity))
    runtime = runtime_identity() if runtime is None else copy.deepcopy(runtime)
    _ensure(type(runtime) is dict and set(runtime) == {'interpreter', 'python', 'openssl'} and
        type(runtime['python']) is list and len(runtime['python']) == 3 and
        all(_integer(value, 1000) for value in runtime['python']) and
        metadata.base._text(runtime['openssl'], 256))
    metadata.base._path(runtime['interpreter'])
    actions = [copy.deepcopy(common['actions'][0]), copy.deepcopy(common['actions'][1]), {
        'method': 'GET', 'url_from': 'fresh-registry-location',
        'hostname': https.DESTINATION, 'port': 443,
        'headers': {'Host': https.DESTINATION, 'Accept': 'application/octet-stream',
                    'Accept-Encoding': 'identity', 'Connection': 'close'},
        'bearer': False, 'maximum_bytes': CONFIG_SIZE, 'permitted_status': 200,
        'framing': 'single-content-length-2646-only'}]
    return {'version': 1, 'kind': 'mailpit-config-only-acquisition',
        'context': copy.deepcopy(context), 'retained_image': copy.deepcopy(retained_image),
        'platform_evidence': copy.deepcopy(platform_evidence),
        'schema_contract': config_schema.CONTRACT,
        'schema_reference_closure': schema_reference_closure, 'runtime': runtime,
        'actions': actions, 'total_timeout': 60, 'request_timeout_max': 10,
        'maximum_header_bytes': 16384, 'maximum_header_count': 100,
        'maximum_location_bytes': 4096, 'maximum_addresses': 16,
        'marker_name': MARKER, 'receipt_name': RECEIPT,
        'authority': dict.fromkeys(AUTHORITY, False), 'review': 'pending'}


def checked_manifest(manifest, expected_sha256):
    try:
        metadata.base._digest(expected_sha256)
        _ensure(type(manifest) is dict and len(canonical(manifest)) <= 65536 and
                sha(canonical(manifest)) == expected_sha256)
        expected = action_manifest(retained_image=manifest['retained_image'],
            platform_evidence=manifest['platform_evidence'],
            schema_reference_closure=manifest['schema_reference_closure'],
            runtime=manifest['runtime'], **manifest['context'])
        _ensure(canonical(expected) == canonical(manifest))
    except Exception:
        raise Refused(ERROR) from None


def _receipt_bindings(manifest, digest, marker):
    context = manifest['context']
    return {'source_head': context['source_sha'], 'manifest_canonical': digest,
        'runner': context['bindings']['dependency_sha256']['config_acquisition.py'],
        'operational': context['operational_sha256'],
        'image_inputs': context['bindings']['image_inputs_sha256'],
        'retained_manifest': context['retained_manifest_sha256'], 'ca': context['ca_sha256'],
        'platform': PLATFORM_SHA256, 'schema_reference_closure': manifest['schema_reference_closure'],
        'marker': marker}


def _output_identity(manifest):
    identity = manifest['context']['output_directory_fingerprint']
    return {'device': identity['dev'], 'inode': identity['ino'], 'uid': identity['uid'], 'mode': '0700'}


def checked_receipt(value, manifest, digest, marker):
    """Reject even rehashed receipts with unlisted fields or contradictory outcomes."""
    try:
        checked_manifest(manifest, digest)
        metadata.base._digest(marker)
        _ensure(type(value) is dict and set(value) == {'schema', 'schema_contract', 'bindings',
            'expected_config', 'output_identity', 'status', 'stage', 'failure', 'request_count',
            'actions', 'config_checks', 'authority', 'review', 'receipt_sha256'})
        _ensure(value['schema'] == 'config-acquisition-receipt-v1' and
            value['schema_contract'] == config_schema.CONTRACT and value['review'] == 'pending')
        _ensure(type(value['bindings']) is dict and
                value['bindings'] == _receipt_bindings(manifest, digest, marker))
        _ensure(type(value['expected_config']) is dict and value['expected_config'] == {
            'media_type': https.CONFIG_MEDIA, 'size': CONFIG_SIZE, 'digest': CONFIG_DIGEST} and
            type(value['expected_config']['size']) is int)
        _ensure(type(value['output_identity']) is dict and
                value['output_identity'] == _output_identity(manifest) and
                all(type(value['output_identity'][key]) is int for key in ('device', 'inode', 'uid')))
        _ensure(type(value['authority']) is dict and set(value['authority']) == set(AUTHORITY) and
                all(item is False for item in value['authority'].values()))
        count, rows, checks = value['request_count'], value['actions'], value['config_checks']
        _ensure(_integer(count, 3) and type(rows) is list and len(rows) == 3)
        for index, row in enumerate(rows):
            _ensure(type(row) is dict and set(row) == {'role', 'http_status', 'peer_ok', 'tls_ok'} and
                row['role'] == ROLES[index] and all(item is None or type(item) is bool for item in
                (row['peer_ok'], row['tls_ok'])) and (row['http_status'] is None or
                type(row['http_status']) is int and 100 <= row['http_status'] <= 599))
            _ensure(index < count or row['http_status'] is None)
            _ensure(row['http_status'] is None or row['peer_ok'] is True and row['tls_ok'] is True)
        _ensure(type(checks) is dict and set(checks) == {'bytes_read', 'length_ok', 'digest_ok', 'schema_ok'} and
            _integer(checks['bytes_read'], CONFIG_SIZE) and all(checks[k] is None or type(checks[k]) is bool
                for k in ('length_ok', 'digest_ok', 'schema_ok')))
        _ensure(checks['length_ok'] is not True or checks['bytes_read'] == CONFIG_SIZE)
        _ensure(checks['digest_ok'] is None or checks['length_ok'] is True)
        _ensure(checks['schema_ok'] is None or checks['digest_ok'] is True)
        has_config = checks['bytes_read'] != 0 or any(checks[k] is not None for k in
                                                   ('length_ok', 'digest_ok', 'schema_ok'))
        _ensure(not has_config or (count == 3 and rows[2]['http_status'] == 200 and
                rows[2]['peer_ok'] is True and rows[2]['tls_ok'] is True))
        _ensure(checks['schema_ok'] is None or value['stage'] in ('validation', 'complete'))
        _ensure(value['stage'] != 'validation' or (checks['bytes_read'] == CONFIG_SIZE and
                checks['length_ok'] is True and checks['digest_ok'] is True))
        _ensure(value['status'] in ('complete', 'refused') and value['stage'] in
                ('preflight', *ROLES, 'validation', 'complete'))
        if value['status'] == 'complete':
            _ensure(value['stage'] == 'complete' and value['failure'] is None and count == 3 and
                [row['http_status'] for row in rows] == [200, 307, 200] and all(
                    row['peer_ok'] is True and row['tls_ok'] is True for row in rows) and
                checks['bytes_read'] == CONFIG_SIZE and all(checks[k] is True for k in
                    ('length_ok', 'digest_ok', 'schema_ok')))
        else:
            _ensure(type(value['failure']) is str and value['failure'] in https.FAILURES and
                    value['stage'] != 'complete')
            stage_index = ('preflight', *ROLES, 'validation').index(value['stage']) - 1
            _ensure(count <= min(3, stage_index + 1))
            for index, row in enumerate(rows):
                if index < stage_index:
                    _ensure(row['http_status'] == (307 if index == 1 else 200) and
                            row['peer_ok'] is True and row['tls_ok'] is True)
                elif index > stage_index:
                    _ensure(all(row[k] is None for k in ('http_status', 'peer_ok', 'tls_ok')))
            _ensure(stage_index >= 2 or checks == {
                'bytes_read': 0, 'length_ok': None, 'digest_ok': None, 'schema_ok': None})
        metadata.base._digest(value['receipt_sha256'])
        _ensure(value['receipt_sha256'] == sha(canonical({key: item for key, item in value.items()
                                                        if key != 'receipt_sha256'})))
    except Exception:
        raise Refused(ERROR) from None


class AcquisitionFailure(Refused):
    def __init__(self, receipt):
        super().__init__(ERROR)
        self.receipt = copy.deepcopy(receipt)


class PreconsumeFailure(Refused):
    """A fixed diagnostic checkpoint; never carries an underlying exception."""
    def __init__(self, stage):
        _ensure(stage in PRECONSUMPTION_STAGES)
        super().__init__(ERROR)
        self.stage = stage


def _config_sha256(raw):
    return sha(raw)


class ConfigAcquisition:
    def __init__(self, manifest, transport, consume_gate, *, manifest_sha256,
                 clock=time.monotonic, output_binding, overall_deadline=None):
        checked_manifest(manifest, manifest_sha256)
        _ensure(callable(getattr(transport, 'request', None)) and callable(consume_gate) and
                callable(output_binding) and callable(clock))
        self.manifest, self.digest = copy.deepcopy(manifest), manifest_sha256
        self.transport, self.consume, self.output = transport, consume_gate, output_binding
        self.clock, self.attempted = clock, False
        self.overall_deadline = overall_deadline

    def collect(self):
        _ensure(not self.attempted, 'replay')
        self.attempted = True
        checked_manifest(self.manifest, self.digest)
        start = self.clock()
        _ensure(metadata.base._finite(start), 'deadline')
        deadline = start + 60 if self.overall_deadline is None else self.overall_deadline
        _ensure(metadata.base._finite(deadline) and start < deadline <= start + 60, 'deadline')
        self.output()
        before_gate = self.clock()
        _ensure(metadata.base._finite(before_gate) and start <= before_gate < deadline, 'deadline')
        marker = self.consume()
        metadata.base._digest(marker)
        receipt = {'schema': 'config-acquisition-receipt-v1', 'schema_contract': config_schema.CONTRACT,
            'bindings': _receipt_bindings(self.manifest, self.digest, marker),
            'expected_config': {'media_type': https.CONFIG_MEDIA, 'size': CONFIG_SIZE, 'digest': CONFIG_DIGEST},
            'output_identity': _output_identity(self.manifest), 'status': 'refused', 'stage': 'preflight',
            'failure': 'internal', 'request_count': 0,
            'actions': [{'role': role, 'http_status': None, 'peer_ok': None, 'tls_ok': None} for role in ROLES],
            'config_checks': {'bytes_read': 0, 'length_ok': None, 'digest_ok': None, 'schema_ok': None},
            'authority': dict.fromkeys(AUTHORITY, False), 'review': 'pending'}
        token, location, payload, response, value, last = None, None, None, None, None, start
        failed_receipt = None

        def remaining(limit):
            nonlocal last
            now = self.clock()
            _ensure(metadata.base._finite(now) and (last is None or now >= last) and
                    now < limit, 'deadline')
            last = now
            return now

        def output_check():
            try:
                self.output()
            except https.TransportRefused:
                raise
            except Exception:
                raise https.TransportRefused('output') from None

        def seal():
            receipt['receipt_sha256'] = sha(canonical(receipt))
            checked_receipt(receipt, self.manifest, self.digest, marker)
            return receipt

        try:
            remaining(deadline)
            output_check()
            for index, role in enumerate(ROLES):
                receipt['stage'] = role
                checked_manifest(self.manifest, self.digest)
                output_check()
                now = remaining(deadline)
                request_deadline = min(deadline, now + 10)
                row = receipt['actions'][index]
                sent = False

                def observe(event, value):
                    nonlocal sent
                    remaining(request_deadline)
                    if event in ('peer_ok', 'tls_ok'):
                        _ensure(type(value) is bool)
                        if event == 'tls_ok':
                            _ensure(row['peer_ok'] is True)
                        row[event] = value
                    elif event == 'send':
                        _ensure(value is None and not sent and row['peer_ok'] is True and
                                row['tls_ok'] is True and receipt['request_count'] == index)
                        output_check()
                        sent = True
                        receipt['request_count'] += 1
                    elif event == 'http_status':
                        _ensure(sent and row['http_status'] is None and type(value) is int and
                                100 <= value <= 599)
                        row['http_status'] = value
                    elif event == 'body_bytes':
                        _ensure(role == 'destination' and sent and row['http_status'] == 200 and
                            _integer(value, CONFIG_SIZE) and value >= receipt['config_checks']['bytes_read'])
                        receipt['config_checks']['bytes_read'] = value
                    else:
                        raise https.TransportRefused('binding')

                response = self.transport.request(role, location=location if index == 2 else None,
                    bearer=token if index == 1 else None, deadline=request_deadline, observe=observe)
                remaining(request_deadline)
                output_check()
                _ensure(type(response) is tuple and len(response) == 2 and sent and
                        type(response[0]) is int and response[0] == row['http_status'])
                status, payload = response
                _ensure(status == (307 if index == 1 else 200), 'status')
                if index == 0:
                    try:
                        _ensure(type(payload) is bytes and len(payload) <= 16384, 'token')
                        value = metadata.base._decode_json(payload)
                        _ensure(type(value) is dict, 'token')
                        token = value.get('token', value.get('access_token'))
                        _ensure(metadata._token(token) and all(value[k] == token for k in
                            ('token', 'access_token') if k in value), 'token')
                    except Exception:
                        raise https.TransportRefused('token') from None
                    finally:
                        payload, value = None, None
                elif index == 1:
                    https.checked_location(payload)
                    location, payload = payload, None
                else:
                    checks = receipt['config_checks']
                    _ensure(type(payload) is bytes, 'body')
                    checks['length_ok'] = len(payload) == CONFIG_SIZE
                    _ensure(checks['length_ok'] and checks['bytes_read'] == len(payload), 'body')
                    checks['digest_ok'] = 'sha256:' + _config_sha256(payload) == CONFIG_DIGEST
                    _ensure(checks['digest_ok'], 'digest')
                    receipt['stage'] = 'validation'
                    try:
                        config_schema.validate_config(payload,
                            layer_count=self.manifest['platform_evidence']['layer_count'])
                    except Exception:
                        checks['schema_ok'] = False
                        raise https.TransportRefused('schema') from None
                    checks['schema_ok'] = True
                    payload = None
                    remaining(deadline)
                    output_check()
            receipt.update(status='complete', stage='complete', failure=None)
            return seal()
        except Exception as error:
            receipt['failure'] = error.code if isinstance(error, https.TransportRefused) else 'internal'
            failed_receipt = seal()
        finally:
            token, location, payload, response, value = None, None, None, None, None
        # Raise outside the handler: no decoder/socket exception context can carry
        # private token JSON, Config data or the signed Location to a caller.
        raise AcquisitionFailure(failed_receipt) from None


class PrivateOutput:
    """Descriptor-relative private output identity and persistent exclusive replay gate."""
    def __init__(self, path, identity):
        self.path, self.identity, self.fd = path, copy.deepcopy(identity), None

    def __enter__(self):
        self.fd = metadata.base._parent(self.path + '/sentinel')
        try:
            self.check()
        except Exception:
            os.close(self.fd)
            self.fd = None
            raise
        return self

    def __exit__(self, *_args):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def check(self):
        descriptor = metadata.base._parent(self.path + '/sentinel')
        try:
            current, pinned = os.fstat(descriptor), os.fstat(self.fd)
            require((current.st_dev, current.st_ino) == (pinned.st_dev, pinned.st_ino) and
                current.st_uid == os.getuid() and stat.S_IMODE(current.st_mode) == 0o700 and
                {'dev': current.st_dev, 'ino': current.st_ino, 'uid': current.st_uid} == self.identity, ERROR)
        finally:
            os.close(descriptor)

    def read(self, name, maximum=65536):
        self.check()
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600 and
                    info.st_uid == os.getuid() and info.st_size <= maximum, ERROR)
            with os.fdopen(fd, 'rb') as stream:
                fd = None
                result = stream.read(maximum + 1)
            require(len(result) <= maximum, ERROR)
            self.check()
            return result
        finally:
            if fd is not None:
                os.close(fd)

    def consume(self, digest):
        try:
            self.check()
            require(set(os.listdir(self.fd)) <= {MANIFEST}, ERROR)
            metadata.base._write_at(self.fd, MARKER, {'manifest_sha256': digest})
            return sha(self.read(MARKER))
        except Exception:
            raise Refused(ERROR) from None

    def publish(self, result, manifest, digest, marker):
        self.check()
        require(set(os.listdir(self.fd)) <= {MANIFEST, MARKER} and sha(self.read(MARKER)) == marker, ERROR)
        checked_receipt(result, manifest, digest, marker)
        metadata.base._write_at(self.fd, RECEIPT, result)
        self.check()


def _dependencies(repo, contract):
    result = diagnostic._dependencies(repo, contract)
    for name in DEPENDENCIES:
        path = 'scripts/codex-qualification/' + name
        raw = metadata.base._read(str(Path(repo) / path))
        digest = sha(raw)
        require(contract.get('source_references', {}).get(path, {}).get('sha256') == digest and
            sha(metadata.base.git(Path(repo), '-c', 'core.fsmonitor=false', 'show',
                contract['identity']['source_sha'] + ':' + path)) == digest and
            sha(metadata.base._read(str(Path(__file__).with_name(name).absolute()))) == digest, ERROR)
        result[name] = digest
    return result


def _platform(raw, image):
    value = diagnostic.verified_platform(raw, image)
    decoded = metadata.base._decode_json(raw)
    layers = decoded.get('layers')
    require(type(layers) is list and len(layers) <= 128, ERROR)
    return {**value, 'layer_count': len(layers)}


def prepare_action(args):
    """File-only source, never invoked for an operational artifact under source authority."""
    contract, raw, inputs, inputs_sha, image, _ca = metadata._source_inputs(args)
    dependencies = _dependencies(args.repo, contract)
    platform = _platform(metadata.base._read(args.platform_file, 1024**2), image)
    parent, directory = metadata.base._parent(args.directory), None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        info = os.fstat(directory)
        manifest = action_manifest(retained_image=image, platform_evidence={'path': args.platform_file, **platform},
            schema_reference_closure=config_schema.reference_closure_sha256(),
            source_sha=args.source_sha, pairing_sha256=contract['pairing_sha256'],
            operational_sha256=contract['operational_sha256'], retained_manifest_sha256=inputs['retained_manifest_sha256'],
            image_refs=inputs['image_refs'], attempt=inputs['attempt'], timeout=inputs['total_timeout'],
            output_directory=args.directory, output_directory_fingerprint={
                'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid},
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


def _verify_inputs(manifest, args):
    context, bindings = manifest['context'], manifest['context']['bindings']
    require(manifest['runtime'] == runtime_identity() and
            manifest['schema_reference_closure'] == config_schema.reference_closure_sha256(), ERROR)
    source = argparse.Namespace(repo=bindings['repo'], source_sha=context['source_sha'],
        contract=bindings['contract_path'], image_inputs=bindings['image_inputs_path'],
        ca_file=context['ca_file'], ca_sha256=context['ca_sha256'])
    contract, raw, inputs, inputs_sha, image, ca = metadata._source_inputs(source)
    require(sha(raw) == bindings['contract_sha256'] and inputs_sha == bindings['image_inputs_sha256'] and
        contract['pairing_sha256'] == context['pairing_sha256'] and
        contract['operational_sha256'] == context['operational_sha256'] and
        _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and
        image == manifest['retained_image'] and inputs['local_files'] == bindings['local_files'] and
        inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and
        inputs['total_timeout'] == context['timeout'], ERROR)
    diagnostic.check_retained_bindings(context, inputs)
    platform = _platform(metadata.base._read(manifest['platform_evidence']['path'], 1024**2), image)
    require(platform == {k: v for k, v in manifest['platform_evidence'].items() if k != 'path'}, ERROR)
    require(args.runner_sha256 == bindings['dependency_sha256']['config_acquisition.py'] and
            sha(metadata.base._read(str(Path(__file__).absolute()))) == args.runner_sha256, ERROR)
    return ca


def _execute_action(args, *, clock, report_stage):
    """Dormant operational source; separate exact-command approval remains mandatory."""
    report_stage('startup')
    started = clock()
    require(metadata.base._finite(started), ERROR)
    deadline, last = started + 60, started
    def remaining():
        nonlocal last
        now = clock()
        _ensure(metadata.base._finite(now) and last <= now < deadline, 'deadline')
        last = now
    report_stage('manifest')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    manifest = metadata.base._json(args.manifest)
    checked_manifest(manifest, args.manifest_sha256)
    context = manifest['context']
    require(args.manifest == str(Path(context['output_directory']) / MANIFEST), ERROR)
    report_stage('source_binding')
    _verify_inputs(manifest, args)
    remaining()
    report_stage('private_output')
    with PrivateOutput(context['output_directory'], context['output_directory_fingerprint']) as store:
        require(store.read(MANIFEST) == canonical(manifest) + b'\n', ERROR)
        report_stage('source_binding')
        ca = _verify_inputs(manifest, args)
        remaining()
        report_stage('tls_setup')
        transport = https.BoundedHTTPS(ca, context['ca_sha256'], clock=clock)
        marker = None
        def consume():
            nonlocal marker
            report_stage('gate_write')
            marker = store.consume(args.manifest_sha256)
            report_stage('post_gate')
            return marker
        def binding():
            store.check()
            _ensure(store.read(MANIFEST) == canonical(manifest) + b'\n', 'binding')
            try:
                _verify_inputs(manifest, args)
            except Exception:
                raise https.TransportRefused('binding') from None
            remaining()
        collector = ConfigAcquisition(manifest, transport, consume,
            manifest_sha256=args.manifest_sha256, output_binding=binding,
            clock=clock, overall_deadline=deadline)
        report_stage('preconsume')
        try:
            result = collector.collect()
        except AcquisitionFailure as failure:
            store.publish(failure.receipt, manifest, args.manifest_sha256, marker)
            raise Refused(ERROR) from None
        report_stage('post_gate')
        binding()
        store.publish(result, manifest, args.manifest_sha256, marker)


def execute_action(args, *, clock=time.monotonic):
    """Sanitize every operational failure, including filesystem publication errors."""
    current = ['startup']
    def report_stage(value):
        current[0] = value if value in (*PRECONSUMPTION_STAGES, 'post_gate') else 'startup'
    failed = False
    try:
        _execute_action(args, clock=clock, report_stage=report_stage)
    except Exception:
        failed = True
    if failed:
        # Outside the handler, so exception context cannot retain private errors.
        if current[0] in PRECONSUMPTION_STAGES:
            raise PreconsumeFailure(current[0]) from None
        raise Refused(ERROR) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    preparation = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'contract', 'image-inputs', 'ca-file', 'ca-sha256', 'platform-file', 'directory'):
        preparation.add_argument('--' + name, required=True)
    execution = commands.add_parser('execute')
    for name in ('manifest', 'manifest-sha256', 'runner-sha256'):
        execution.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            print('File-only Config manifest prepared; manifest_sha256=' + prepare_action(args))
        else:
            execute_action(args)
            print('Config integrity/schema observed; no profile or qualification authority')
    except PreconsumeFailure as error:
        parser.exit(1, ERROR + '; preconsume_stage=' + error.stage + '\n')
    except Exception:
        parser.exit(1, ERROR + '\n')


if __name__ == '__main__':
    main()

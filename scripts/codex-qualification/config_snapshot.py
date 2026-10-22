"""Dormant inert Config snapshot v1; local consistency never grants execution authority.

Use only the separately reviewed outer timeout commands. Directory flock is a
cooperating-writer protocol, not protection against an uncooperative same-UID
writer, root, or changed executing code. Identity-check then unlink is not an
atomic conditional deletion. No payload is printed, evaluated, or executed.
"""
import argparse
import copy
from contextlib import contextmanager, nullcontext
import fcntl
import functools
import os
from pathlib import Path
import resource
import signal
import stat
import sys
import time

# Fixed sibling imports work with the reviewed -I -S command, without PYTHONPATH.
sys.path.insert(0, str(Path(__file__).absolute().parent))
import config_acquisition as acquisition
from config_acquisition import https, metadata
import config_schema
from prepare import Refused, canonical, sha

ERROR = 'Config snapshot incomplete'
SUCCESS = 'Config snapshot integrity/schema observed; inert inspection pending'
MANIFEST = 'snapshot-manifest.json'
MARKER = 'snapshot-marker.json'
PAYLOAD = 'config.bin'
RECEIPT = 'snapshot-receipt.json'
REVIEW = 'snapshot-review.json'
REPORT = 'field-report.json'
CLEANUP = 'snapshot-cleanup-receipt.json'
LEAVES = (MANIFEST, MARKER, PAYLOAD, RECEIPT, REVIEW, REPORT, CLEANUP)
DEPENDENCIES = (*acquisition.DEPENDENCIES, 'config_snapshot.py', 'test_config_snapshot.py', 'test_registry_metadata.py')
FULL_DEPENDENCIES = (*metadata.base.DEPENDENCIES, 'reference_diagnostic.py',
    'registry_metadata.py', 'redirect_diagnostic.py', 'test_redirect_diagnostic.py', *DEPENDENCIES)
AUTHORITY = dict.fromkeys(acquisition.AUTHORITY, False)
BUDGETS = {'acquisition': 60, 'request': 10, 'execution_outer': 90, 'inspect': 5,
           'cleanup': 10, 'local_outer': 15, 'kill_grace': 5, 'retention': 259200,
           'report_bytes': 32768, 'artifact_leaves': 7}
LOCAL_FAILURES = ('expiry', 'payload_output', 'receipt_output', 'cleanup')


class SnapshotFailure(Refused):
    def __init__(self, code='binding', stage='preconsume'):
        super().__init__(ERROR)
        self.code = code if code in (*https.FAILURES, *LOCAL_FAILURES) else 'internal'
        self.stage = stage if stage in ('preconsume', 'spent', 'recovery', 'inspection', 'cleanup') else 'preconsume'


def ensure(condition, code='binding'):
    if not condition:
        raise SnapshotFailure(code)


def sealed(value):
    result = copy.deepcopy(value)
    result['self_sha256'] = sha(canonical(result))
    return result


def check_seal(value, fields):
    ensure(type(value) is dict and set(value) == set(fields) | {'self_sha256'})
    metadata.base._digest(value['self_sha256'])
    ensure(value['self_sha256'] == sha(canonical({k: v for k, v in value.items() if k != 'self_sha256'})))


def integer(value):
    return type(value) is int and 0 <= value <= 2**63 - 1


def action_manifest(*, acquisition_plan, prepared_at, expires_at, browser_contract_expiry):
    """The embedded legacy-shaped object is a network plan, never its file protocol.

    No embedded legacy marker/receipt leaf is created. The distinct outer schema,
    manifest hash and new spent marker govern every retained artifact.
    """
    acquisition.checked_manifest(acquisition_plan, sha(canonical(acquisition_plan)))
    ensure(acquisition_plan['platform_evidence']['layer_count'] == 3 and
           acquisition_plan['platform_evidence']['bytes'] == 864)
    ensure(all(integer(v) for v in (prepared_at, expires_at, browser_contract_expiry)) and
           prepared_at < expires_at <= min(prepared_at + 259200, browser_contract_expiry), 'expiry')
    deps = acquisition_plan['context']['bindings']['dependency_sha256']
    ensure(set(deps) == set(FULL_DEPENDENCIES))
    return {'schema': 'config-snapshot-manifest-v1', 'acquisition_plan': copy.deepcopy(acquisition_plan),
            'prepared_at': prepared_at, 'expires_at': expires_at,
            'browser_contract_expiry': browser_contract_expiry, 'leaves': list(LEAVES),
            'budgets': dict(BUDGETS), 'observer_kind': 'local-unattested', 'authority': dict(AUTHORITY)}


def checked_manifest(value, digest):
    try:
        metadata.base._digest(digest)
        ensure(type(value) is dict and len(canonical(value)) <= 65536 and sha(canonical(value)) == digest)
        expected = action_manifest(**{k: value[k] for k in
            ('acquisition_plan', 'prepared_at', 'expires_at', 'browser_contract_expiry')})
        ensure(canonical(expected) == canonical(value))
    except Exception:
        raise SnapshotFailure() from None


class Budget:
    def __init__(self, seconds, *, clock=time.monotonic, utc=time.time, manifest=None, expiry=True):
        self.clock, self.utc, self.manifest, self.expiry = clock, utc, manifest, expiry
        self.last = clock()
        ensure(metadata.base._finite(self.last), 'deadline')
        self.deadline = self.last + seconds

    def check(self):
        now = self.clock()
        ensure(metadata.base._finite(now) and self.last <= now < self.deadline, 'deadline')
        self.last = now
        if self.expiry:
            stamp = self.utc()
            ensure(type(stamp) in (int, float) and metadata.base._finite(stamp) and
                   self.manifest['prepared_at'] <= stamp < self.manifest['expires_at'], 'expiry')


def identity(info, raw, *, payload=False):
    return {'leaf': PAYLOAD if payload else REPORT, 'device': info.st_dev, 'inode': info.st_ino,
            'uid': info.st_uid, 'mode': '0600', 'links': info.st_nlink, 'size': len(raw),
            'sha256': acquisition._config_sha256(raw) if payload else sha(raw), 'durably_verified': True}


def checked_identity(value, *, payload, complete=True):
    ensure(type(value) is dict and set(value) == {'leaf', 'device', 'inode', 'uid', 'mode', 'links',
                                                'size', 'sha256', 'durably_verified'})
    ensure(value['leaf'] == (PAYLOAD if payload else REPORT) and value['mode'] == '0600' and
           type(value['links']) is int and value['links'] == 1 and type(value['durably_verified']) is bool and
           all(integer(value[k]) for k in ('device', 'inode', 'uid', 'size')))
    metadata.base._digest(value['sha256'])
    ensure(value['size'] <= (2646 if payload else 32768))
    if complete:
        ensure(value['durably_verified'] is True)
        if payload:
            ensure(value['size'] == 2646 and value['sha256'] == acquisition.CONFIG_DIGEST[7:])


class Store:
    """Private no-follow access under a pinned exclusive advisory directory lock."""
    def __init__(self, manifest, budget, *, descriptor=None):
        self.manifest, self.budget, self.fd = manifest, budget, None
        self.context = manifest['acquisition_plan']['context']
        self.path = self.context['output_directory']
        self.created = {}
        self.locked_descriptor = descriptor

    def __enter__(self):
        try:
            self.fd = (os.dup(self.locked_descriptor) if self.locked_descriptor is not None else
                       metadata.base._parent(self.path + '/sentinel'))
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.check()
            return self
        except Exception:
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
            raise SnapshotFailure() from None

    def __exit__(self, *_args):
        if self.fd is not None:
            descriptor, self.fd = self.fd, None
            os.close(descriptor)  # Closing releases flock, including every failure path.

    def check(self):
        self.budget.check()
        descriptor = metadata.base._parent(self.path + '/sentinel')
        try:
            actual, pinned = os.fstat(descriptor), os.fstat(self.fd)
            ensure(actual.st_uid == os.getuid() and stat.S_IMODE(actual.st_mode) == 0o700 and
                (actual.st_dev, actual.st_ino) == (pinned.st_dev, pinned.st_ino) and
                {'dev': actual.st_dev, 'ino': actual.st_ino, 'uid': actual.st_uid} ==
                    self.context['output_directory_fingerprint'])
        finally:
            os.close(descriptor)

    def census(self):
        self.check()
        names = set()
        with os.scandir(self.fd) as entries:
            for entry in entries:
                self.budget.check()
                ensure(len(names) < 7 and entry.name in LEAVES)
                info = os.stat(entry.name, dir_fd=self.fd, follow_symlinks=False)
                ensure(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600 and
                       info.st_uid == os.getuid() and info.st_nlink == 1)
                names.add(entry.name)
        return names

    def named(self, name, info):
        self.check()
        actual = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
        ensure((actual.st_dev, actual.st_ino) == (info.st_dev, info.st_ino) and
               actual.st_nlink == info.st_nlink == 1 and actual.st_uid == info.st_uid == os.getuid() and
               stat.S_ISREG(actual.st_mode) and stat.S_IMODE(actual.st_mode) == 0o600)

    def read(self, name, maximum=65536):
        ensure(name in LEAVES)
        self.check()
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            before = os.fstat(fd)
            ensure(stat.S_ISREG(before.st_mode) and stat.S_IMODE(before.st_mode) == 0o600 and
                   before.st_nlink == 1 and before.st_uid == os.getuid() and before.st_size <= maximum)
            self.named(name, before)
            parts, length = [], 0
            while True:
                self.budget.check()
                data = os.read(fd, min(8192, maximum + 1 - length))
                if not data:
                    break
                parts.append(data)
                length += len(data)
                ensure(length <= maximum)
            after = os.fstat(fd)
            ensure((before.st_size, before.st_mtime_ns, before.st_ctime_ns) ==
                   (after.st_size, after.st_mtime_ns, after.st_ctime_ns) and length == after.st_size)
            self.named(name, after)
            return b''.join(parts), after
        finally:
            os.close(fd)

    def write(self, name, raw):
        ensure(name in LEAVES and type(raw) is bytes and len(raw) <= (32768 if name == REPORT else 65536))
        self.check()
        fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        # O_EXCL creation is already durable ownership intent for this action,
        # even if the first fstat fails. None means created but not safely
        # identified, so rollback must preserve it rather than unlink by name.
        self.created[name] = None
        try:
            info = os.fstat(fd)
            self.created[name] = info
            offset = 0
            while offset < len(raw):
                self.budget.check()
                count = os.write(fd, raw[offset:])
                ensure(type(count) is int and 0 < count <= len(raw) - offset)
                offset += count
            os.fsync(fd)
            self.named(name, os.fstat(fd))
            os.lseek(fd, 0, os.SEEK_SET)
            ensure(os.read(fd, len(raw) + 1) == raw)
            self.budget.check()
        finally:
            os.close(fd)
        os.fsync(self.fd)
        reread, info = self.read(name, len(raw))
        ensure(reread == raw)
        return info

    def remove_created(self, names):
        # Check+unlink is safe only under the documented quiescent writer model.
        for name in names:
            if name in self.created:
                ensure(self.created[name] is not None, 'cleanup')
                self.named(name, self.created[name])
                os.unlink(name, dir_fd=self.fd)
        os.fsync(self.fd)

    def publish(self, name, raw, code):
        try:
            return self.write(name, raw)
        except Exception as error:
            if isinstance(error, SnapshotFailure) and error.code in ('expiry', 'deadline'):
                code = error.code
        raise SnapshotFailure(code) from None


def _dependencies(repo, contract):
    result = acquisition._dependencies(repo, contract)
    for name in ('config_snapshot.py', 'test_config_snapshot.py', 'test_registry_metadata.py'):
        relative = 'scripts/codex-qualification/' + name
        digest = sha(metadata.base._read(str(Path(repo) / relative)))
        ensure(contract['source_references'][relative]['sha256'] == digest and
               sha(metadata.base.git(Path(repo), '-c', 'core.fsmonitor=false', 'show',
                                    contract['identity']['source_sha'] + ':' + relative)) == digest and
               sha(metadata.base._read(str(Path(__file__).with_name(name)))) == digest)
        result[name] = digest
    return result


def _verify_source(manifest, args, *, historical=False, cleanup=False):
    plan = manifest['acquisition_plan']
    context, bindings = plan['context'], plan['context']['bindings']
    if cleanup:
        # Cleanup is current-source reviewed separately; historical CA/expiry/HEAD
        # are deliberately not admission conditions for positively owned deletion.
        metadata.base._source(bindings['repo'], args.cleanup_source_sha)
        current = {}
        for name in FULL_DEPENDENCIES:
            relative = 'scripts/codex-qualification/' + name
            raw = metadata.base._read(str(Path(__file__).with_name(name)))
            ensure(raw == metadata.base.git(Path(bindings['repo']), '-c', 'core.fsmonitor=false',
                                           'show', args.cleanup_source_sha + ':' + relative))
            current[name] = sha(raw)
        ensure(sha(canonical(current)) == args.cleanup_closure_sha256 and
               args.runner_sha256 == current['config_snapshot.py'])
        return None
    ensure(plan['runtime'] == acquisition.runtime_identity() and
           plan['schema_reference_closure'] == config_schema.reference_closure_sha256())
    ensure(args.runner_sha256 == bindings['dependency_sha256']['config_snapshot.py'])
    if historical:
        # An evidence/docs commit may advance HEAD; only historical committed
        # dependency bytes and the actual executing inspector closure are checked.
        for name, digest in bindings['dependency_sha256'].items():
            ensure(Path(name).name == name and name.endswith('.py'))
            relative = 'scripts/codex-qualification/' + name
            ensure(sha(metadata.base.git(Path(bindings['repo']), '-c', 'core.fsmonitor=false',
                                         'show', context['source_sha'] + ':' + relative)) == digest and
                   sha(metadata.base._read(str(Path(__file__).with_name(name)))) == digest)
        return None
    source = argparse.Namespace(repo=bindings['repo'], source_sha=context['source_sha'],
        contract=bindings['contract_path'], image_inputs=bindings['image_inputs_path'],
        ca_file=context['ca_file'], ca_sha256=context['ca_sha256'])
    contract, raw, inputs, inputs_sha, image, ca = metadata._source_inputs(source)
    ensure(sha(raw) == bindings['contract_sha256'] and inputs_sha == bindings['image_inputs_sha256'] and
           contract['pairing_sha256'] == context['pairing_sha256'] and
           contract['operational_sha256'] == context['operational_sha256'] and
           contract['browser']['expires_at'] == manifest['browser_contract_expiry'] and
           _dependencies(bindings['repo'], contract) == bindings['dependency_sha256'] and
           image == plan['retained_image'] and inputs['local_files'] == bindings['local_files'] and
           inputs['retained_manifest_path'] == bindings['retained_manifest_path'] and
           inputs['total_timeout'] == context['timeout'])
    acquisition.diagnostic.check_retained_bindings(context, inputs)
    platform = acquisition._platform(metadata.base._read(plan['platform_evidence']['path'], 1024**2), image)
    ensure(platform == {k: v for k, v in plan['platform_evidence'].items() if k != 'path'})
    return ca


def prepare_action(args, *, utc=time.time):
    contract, raw, inputs, inputs_sha, image, _ca = metadata._source_inputs(args)
    dependencies = _dependencies(args.repo, contract)
    platform = acquisition._platform(metadata.base._read(args.platform_file, 1024**2), image)
    parent, directory = metadata.base._parent(args.directory), None
    try:
        os.mkdir(Path(args.directory).name, mode=0o700, dir_fd=parent)
        directory = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        fcntl.flock(directory, fcntl.LOCK_EX | fcntl.LOCK_NB)
        info = os.fstat(directory)
        ensure(stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == os.getuid())
        plan = acquisition.action_manifest(retained_image=image,
            platform_evidence={'path': args.platform_file, **platform},
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
        manifest = action_manifest(acquisition_plan=plan, prepared_at=int(utc()),
            expires_at=args.expires_at, browser_contract_expiry=contract['browser']['expires_at'])
        # The same locked, durable private writer handles preparation too.
        budget = Budget(5, manifest=manifest, utc=utc)
        store = Store(manifest, budget)
        store.fd = directory
        store.write(MANIFEST, canonical(manifest) + b'\n')
        return sha(canonical(manifest))
    finally:
        if directory is not None:
            os.close(directory)
        os.close(parent)


def _receipt(manifest, digest, marker, network, snapshot, failure, observed_at):
    return sealed({'schema': 'config-snapshot-receipt-v1', 'schema_contract': config_schema.CONTRACT,
        'bindings': {**acquisition._receipt_bindings(manifest['acquisition_plan'], digest, marker),
            'runner': manifest['acquisition_plan']['context']['bindings']['dependency_sha256']['config_snapshot.py']},
        'expected_config': {'media_type': https.CONFIG_MEDIA, 'size': 2646, 'digest': acquisition.CONFIG_DIGEST},
        'output_identity': acquisition._output_identity(manifest['acquisition_plan']),
        'status': 'complete' if failure is None else 'refused',
        'stage': 'complete' if failure is None else network.get('stage', 'preflight'), 'failure': failure,
        'request_count': network['request_count'], 'actions': network['actions'],
        'config_checks': network['config_checks'], 'review': 'pending', 'authority': dict(AUTHORITY),
        'prepared_at': manifest['prepared_at'], 'expires_at': manifest['expires_at'],
        'observed_at': observed_at, 'observer_kind': 'local-unattested', 'snapshot': snapshot})


def checked_receipt(value, manifest, digest, marker):
    try:
        checked_manifest(manifest, digest)
        fields = {'schema', 'schema_contract', 'bindings', 'expected_config', 'output_identity', 'status',
            'stage', 'failure', 'request_count', 'actions', 'config_checks', 'review', 'authority',
            'prepared_at', 'expires_at', 'observed_at', 'observer_kind', 'snapshot'}
        check_seal(value, fields)
        ensure(value['schema'] == 'config-snapshot-receipt-v1' and value['authority'] == AUTHORITY and
               all(v is False for v in value['authority'].values()) and value['review'] == 'pending')
        ensure(value['prepared_at'] == manifest['prepared_at'] and value['expires_at'] == manifest['expires_at'] and
               integer(value['observed_at']) and manifest['prepared_at'] <= value['observed_at'] < manifest['expires_at'] and
               value['observer_kind'] == 'local-unattested')
        expected = _receipt(manifest, digest, marker, value, value['snapshot'], value['failure'], value['observed_at'])
        ensure(value == expected)
        # The shared legacy validator checks the fixed action/check/status shape,
        # with an explicitly reconstructed IN-MEMORY receipt, not legacy files.
        plan = manifest['acquisition_plan']
        old_digest = sha(canonical(plan))
        network = {k: copy.deepcopy(value[k]) for k in ('schema_contract', 'expected_config', 'output_identity',
            'request_count', 'actions', 'config_checks', 'review', 'authority')}
        network.update(schema='config-acquisition-receipt-v1',
            bindings=acquisition._receipt_bindings(plan, old_digest, marker))
        validated = value['config_checks'] == {'bytes_read': 2646, 'length_ok': True,
                                               'digest_ok': True, 'schema_ok': True}
        if value['stage'] == 'complete' and validated:
            network.update(status='complete', stage='complete', failure=None)
        else:
            network.update(status='refused', stage=value['stage'],
                           failure='internal' if value['failure'] in LOCAL_FAILURES else value['failure'])
        network['receipt_sha256'] = sha(canonical(network))
        acquisition.checked_receipt(network, plan, old_digest, marker)
        if value['status'] == 'complete':
            checked_identity(value['snapshot'], payload=True)
        else:
            ensure(value['snapshot'] is None and value['failure'] in (*https.FAILURES, *LOCAL_FAILURES))
    except Exception:
        raise SnapshotFailure() from None


class SnapshotCollector(acquisition.ConfigAcquisition):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.validated = None

    def _validated_payload(self, payload):
        self.validated = payload


class Handlers:
    def __enter__(self):
        self.previous = {}
        def interrupted(_signal, _frame):
            raise SnapshotFailure('cleanup', 'spent')
        try:
            for sig in (signal.SIGTERM, signal.SIGINT):
                self.previous[sig] = signal.signal(sig, interrupted)
        except Exception:
            self.__exit__()
            raise
        return self

    def __exit__(self, *_args):
        failed = False
        for sig, handler in self.previous.items():
            try:
                signal.signal(sig, handler)
                ensure(signal.getsignal(sig) == handler, 'cleanup')
            except Exception:
                failed = True
        if failed:
            raise SnapshotFailure('cleanup', 'spent')


def locked_action(seconds):
    """Hold one lock from the first manifest read through final close/fsync."""
    def decorate(function):
        @functools.wraps(function)
        def run(args, *, clock=time.monotonic, utc=time.time):
            descriptor = None
            arguments = None
            failed = False
            code, stage = 'binding', 'preconsume'
            try:
                started = clock()
                ensure(metadata.base._finite(started), 'deadline')
                descriptor = metadata.base._parent(args.manifest)
                info = os.fstat(descriptor)
                ensure(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700)
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                arguments = copy.copy(args)
                arguments._snapshot_directory_fd = descriptor
                arguments._snapshot_started = started
                result = function(arguments, clock=clock, utc=utc)
                finished = clock()
                ensure(metadata.base._finite(finished) and started <= finished < started + seconds, 'deadline')
            except Exception as error:
                failed = True
                if isinstance(error, SnapshotFailure):
                    code, stage = error.code, error.stage
            finally:
                if descriptor is not None:
                    try:
                        os.close(descriptor)
                    except OSError:
                        failed, code = True, 'cleanup'
            if failed:
                if arguments is not None and getattr(arguments, '_snapshot_spent', False):
                    stage = 'spent'
                raise SnapshotFailure(code, stage) from None
            return result
        return run
    return decorate


def _load(args):
    ensure(Path(args.manifest).name == MANIFEST)
    fd = os.open(MANIFEST, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                 dir_fd=args._snapshot_directory_fd)
    try:
        info = os.fstat(fd)
        ensure(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600 and
               info.st_uid == os.getuid() and info.st_nlink == 1 and info.st_size <= 65536)
        raw = os.read(fd, 65537)
        named = os.stat(MANIFEST, dir_fd=args._snapshot_directory_fd, follow_symlinks=False)
        ensure(len(raw) == info.st_size and (named.st_dev, named.st_ino, named.st_size, named.st_mtime_ns) ==
               (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns))
        manifest = metadata.base._decode_json(raw)
    finally:
        os.close(fd)
    checked_manifest(manifest, args.manifest_sha256)
    ensure(args.manifest == str(Path(manifest['acquisition_plan']['context']['output_directory']) / MANIFEST))
    return manifest


def _budget(args, manifest, seconds, clock, utc, *, expiry=True):
    budget = Budget(seconds, clock=clock, utc=utc, manifest=manifest, expiry=expiry)
    budget.deadline = args._snapshot_started + seconds
    budget.check()
    return budget


def _empty_network():
    return {'stage': 'preflight', 'request_count': 0, 'actions': [{'role': role, 'http_status': None, 'peer_ok': None,
             'tls_ok': None} for role in acquisition.ROLES], 'config_checks': {
             'bytes_read': 0, 'length_ok': None, 'digest_ok': None, 'schema_ok': None}}


@locked_action(60)
def execute_action(args, *, clock=time.monotonic, utc=time.time):
    failed, consumed, code, collector, stage = False, False, 'binding', None, 'preconsume'
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        manifest = _load(args)
        budget = _budget(args, manifest, 60, clock, utc)
        budget.check()
        with Store(manifest, budget, descriptor=args._snapshot_directory_fd) as store:
            if store.census() != {MANIFEST}:
                raise SnapshotFailure('replay', 'recovery')
            ensure(store.read(MANIFEST)[0] == canonical(manifest) + b'\n')
            ca = _verify_source(manifest, args)
            network, marker, payload_id, boundary_failure = _empty_network(), None, None, None
            def binding():
                nonlocal boundary_failure
                boundary_failure = None
                try:
                    store.check()
                    ensure(store.read(MANIFEST)[0] == canonical(manifest) + b'\n')
                    _verify_source(manifest, args)
                    budget.check()
                except Exception as error:
                    boundary_failure = error.code if isinstance(error, SnapshotFailure) else 'binding'
                    raise https.TransportRefused(boundary_failure if boundary_failure in https.FAILURES else 'binding') from None
            def consume():
                nonlocal consumed, marker
                binding()
                ensure(store.census() == {MANIFEST})
                # An exclusive created marker spends the attempt even if fsync
                # or close fails. It is never removed on rollback.
                try:
                    store.write(MARKER, canonical({'manifest_sha256': args.manifest_sha256}) + b'\n')
                finally:
                    consumed = MARKER in store.created
                    args._snapshot_spent = consumed
                marker = sha(store.read(MARKER)[0])
                return marker
            plan = manifest['acquisition_plan']
            transport = https.BoundedHTTPS(ca, plan['context']['ca_sha256'], clock=clock)
            collector = SnapshotCollector(plan, transport, consume,
                manifest_sha256=sha(canonical(plan)), output_binding=binding,
                clock=clock, overall_deadline=budget.deadline)
            try:
                with Handlers():
                    network = collector.collect()
                    binding()
                    code = 'payload_output'
                    info = store.publish(PAYLOAD, collector.validated, 'payload_output')
                    payload_id = identity(info, collector.validated, payload=True)
                    checked_identity(payload_id, payload=True)
                    collector.validated = None
                    binding()
                    result = _receipt(manifest, args.manifest_sha256, marker, network, payload_id, None, int(utc()))
                    checked_receipt(result, manifest, args.manifest_sha256, marker)
                    code = 'receipt_output'
                    store.publish(RECEIPT, canonical(result) + b'\n', 'receipt_output')
                    binding()
                    raw, info = store.read(PAYLOAD, 2646)
                    ensure(identity(info, raw, payload=True) == payload_id)
                    ensure(store.read(RECEIPT)[0] == canonical(result) + b'\n')
                    store.census()
            except Exception as error:
                code = error.code if isinstance(error, (SnapshotFailure, https.TransportRefused)) else code
                if isinstance(error, acquisition.AcquisitionFailure):
                    network, code = error.receipt, boundary_failure or error.receipt['failure']
                if boundary_failure is not None:
                    code = boundary_failure
                failed = True
                if consumed:
                    # Deadline/expiry failure must not itself prevent bounded
                    # local rollback of positively owned newly created bytes.
                    store.budget = Budget(10, clock=clock, utc=utc, manifest=manifest, expiry=False)
                    try:
                        preserve = False
                        if RECEIPT in store.created:
                            try:
                                existing = metadata.base._decode_json(store.read(RECEIPT)[0])
                                checked_receipt(existing, manifest, args.manifest_sha256, marker)
                                preserve = existing['status'] == 'complete'
                            except Exception:
                                preserve = False
                        store.remove_created([PAYLOAD] + ([] if preserve else [RECEIPT]))
                        if (marker is not None and not preserve and code != 'receipt_output' and
                                manifest['prepared_at'] <= utc() < manifest['expires_at']):
                            failure = _receipt(manifest, args.manifest_sha256, marker, network, None,
                                               code, int(utc()))
                            checked_receipt(failure, manifest, args.manifest_sha256, marker)
                            store.write(RECEIPT, canonical(failure) + b'\n')
                    except Exception:
                        code = 'cleanup'
            if failed:
                raise SnapshotFailure(code, 'spent' if consumed else 'preconsume')
    except Exception as error:
        failed = True
        if isinstance(error, SnapshotFailure):
            code, stage = error.code, error.stage
    finally:
        if collector is not None:
            collector.validated = None
    if failed:
        raise SnapshotFailure(code, 'spent' if consumed else stage) from None


def inspect_fields(raw):
    """Pure complete decoded structure, with absence/null/type/unknown data intact."""
    try:
        config_schema.validate_config(raw, layer_count=3)
        return metadata.base._decode_json(raw)
    except Exception:
        raise SnapshotFailure('schema', 'inspection') from None


def action_command(manifest, digest, verb, *, tool_result=None):
    ensure(verb in ('execute', 'verify', 'inspect', 'cleanup'))
    plan = manifest['acquisition_plan']
    root = Path(plan['context']['bindings']['repo']) / 'scripts/codex-qualification'
    command = ['/usr/bin/env', '-i', 'PATH=/usr/bin:/bin', 'LC_ALL=C', '/usr/bin/timeout',
               '-k', '5', '90' if verb == 'execute' else '15', plan['runtime']['interpreter'],
               '-I', '-S', '-B', str(root / 'config_snapshot.py'), verb,
               '--manifest', str(Path(plan['context']['output_directory']) / MANIFEST),
               '--manifest-sha256', digest, '--runner-sha256',
               plan['context']['bindings']['dependency_sha256']['config_snapshot.py']]
    if tool_result is not None:
        command.extend(['--tool-result', tool_result])
    return command


def cleanup_command(manifest, digest, *, source_sha, closure_sha256, runner_sha256,
                    expected_payload, expected_report=None, recovery_directory=None):
    """Full currently reviewed cleanup argv; no payload values enter arguments."""
    ensure(type(source_sha) is str and len(source_sha) == 40 and all(c in '0123456789abcdef' for c in source_sha))
    for digest_value in (digest, closure_sha256, runner_sha256):
        metadata.base._digest(digest_value)
    checked_identity(expected_payload, payload=True, complete=False)
    if expected_report is not None:
        checked_identity(expected_report, payload=False, complete=False)
    command = action_command(manifest, digest, 'cleanup')
    command[8] = acquisition.runtime_identity()['interpreter']
    command[-1] = runner_sha256
    command += ['--cleanup-source-sha', source_sha, '--cleanup-closure-sha256', closure_sha256,
                '--expected-payload', canonical(expected_payload).decode('ascii')]
    if expected_report is not None:
        command += ['--expected-report', canonical(expected_report).decode('ascii')]
    if recovery_directory is not None:
        metadata.base._path(recovery_directory)
        command += ['--recovery-directory', recovery_directory]
    return command


def tool_record(*, command_sha256, exit_code, stdout_sha256, stderr_sha256, reference):
    for digest in (command_sha256, stdout_sha256, stderr_sha256):
        metadata.base._digest(digest)
    ensure(type(exit_code) is int and -255 <= exit_code <= 255 and
           type(reference) is str and 0 < len(reference) <= 256 and
           all(32 <= ord(c) <= 126 for c in reference))
    return sealed({'schema': 'config-snapshot-tool-result-v1', 'command_sha256': command_sha256,
        'exit_code': exit_code, 'stdout_sha256': stdout_sha256, 'stderr_sha256': stderr_sha256,
        'reference': reference, 'observer_kind': 'local-unattested'})


def checked_tool(value, manifest, digest):
    check_seal(value, {'schema', 'command_sha256', 'exit_code', 'stdout_sha256', 'stderr_sha256',
                       'reference', 'observer_kind'})
    expected = tool_record(**{k: value[k] for k in ('command_sha256', 'exit_code', 'stdout_sha256',
                                                   'stderr_sha256', 'reference')})
    ensure(value == expected and value['exit_code'] == 0 and
           value['command_sha256'] == sha(canonical(action_command(manifest, digest, 'execute'))) and
           value['stdout_sha256'] == sha(SUCCESS.encode() + b'\n') and value['stderr_sha256'] == sha(b''))


def review_record(manifest, digest, *, marker_sha256, receipt, tool_result, engineering, security, reviewed_at):
    """Pure supplied-consistency constructor; never called by acquisition.

    Only the coordinator may separately write this input after observing the
    original result and receiving independent evidence verdicts. This function
    cannot authenticate reviewers, independence, or a tool result.
    """
    checked_receipt(receipt, manifest, digest, marker_sha256)
    checked_tool(tool_result, manifest, digest)
    ensure(receipt['status'] == 'complete' and engineering == security == 'pass' and
           integer(reviewed_at) and receipt['observed_at'] <= reviewed_at < manifest['expires_at'])
    return sealed({'schema': 'config-snapshot-review-v1', 'state': 'accepted-for-inert-inspection',
        'manifest_sha256': digest, 'command_sha256': tool_result['command_sha256'],
        'marker_sha256': marker_sha256, 'receipt_sha256': receipt['self_sha256'],
        'snapshot': copy.deepcopy(receipt['snapshot']), 'execution_exit': 0,
        'execution_record_sha256': sha(canonical(tool_result) + b'\n'), 'engineering': engineering, 'security': security,
        'prepared_at': manifest['prepared_at'], 'reviewed_at': reviewed_at, 'expires_at': manifest['expires_at'],
        'observer_kind': 'local-unattested', 'authority': dict(AUTHORITY)})


def _private_tool(path):
    parent = metadata.base._parent(path)
    fd = None
    try:
        directory = os.fstat(parent)
        ensure(directory.st_uid == os.getuid() and stat.S_IMODE(directory.st_mode) == 0o700)
        fd = os.open(Path(path).name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        info = os.fstat(fd)
        ensure(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600 and
               info.st_nlink == 1 and info.st_uid == os.getuid() and info.st_size <= 8192)
        raw = os.read(fd, 8193)
        named = os.stat(Path(path).name, dir_fd=parent, follow_symlinks=False)
        ensure(len(raw) == info.st_size and (named.st_dev, named.st_ino, named.st_size, named.st_mtime_ns) ==
               (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns))
        value = metadata.base._decode_json(raw)
        ensure(raw == canonical(value) + b'\n')
        return value
    finally:
        if fd is not None:
            os.close(fd)
        os.close(parent)


def _pair(store, manifest, digest):
    ensure(store.read(MANIFEST)[0] == canonical(manifest) + b'\n')
    marker_raw = store.read(MARKER)[0]
    ensure(marker_raw == canonical({'manifest_sha256': digest}) + b'\n')
    marker = sha(marker_raw)
    receipt = metadata.base._decode_json(store.read(RECEIPT)[0])
    checked_receipt(receipt, manifest, digest, marker)
    ensure(receipt['status'] == 'complete')
    raw, info = store.read(PAYLOAD, 2646)
    observed = identity(info, raw, payload=True)
    checked_identity(observed, payload=True)
    ensure(observed == receipt['snapshot'])
    inspect_fields(raw)
    store.budget.check()
    return receipt, marker, raw


@locked_action(5)
def verify_action(args, *, clock=time.monotonic, utc=time.time):
    """Read-only joint consistency check; does not write or accept its own review."""
    try:
        manifest = _load(args)
        budget = _budget(args, manifest, 5, clock, utc, expiry=False)
        with Store(manifest, budget, descriptor=args._snapshot_directory_fd) as store:
            names = store.census()
            if not {MANIFEST, MARKER, PAYLOAD, RECEIPT} <= names:
                return {'outcome': 'recovery-incomplete', 'artifacts': sorted(names),
                        'evidence_accepted': False, 'authority': dict(AUTHORITY)}
            budget.expiry = True
            budget.check()
            _verify_source(manifest, args)
            receipt, marker, _raw = _pair(store, manifest, args.manifest_sha256)
            tool = _private_tool(args.tool_result)
            checked_tool(tool, manifest, args.manifest_sha256)
            budget.check()
            return {'outcome': 'joint-local-consistency-only', 'receipt_sha256': receipt['self_sha256'],
                    'marker_sha256': marker, 'execution_record_sha256': sha(canonical(tool) + b'\n'),
                    'authority': dict(AUTHORITY)}
    except Exception:
        raise SnapshotFailure('binding', 'recovery') from None


@locked_action(5)
def inspect_action(args, *, clock=time.monotonic, utc=time.time):
    try:
        manifest = _load(args)
        budget = _budget(args, manifest, 5, clock, utc)
        _verify_source(manifest, args, historical=True)
        with Store(manifest, budget, descriptor=args._snapshot_directory_fd) as store:
            store.census()
            receipt, marker, raw = _pair(store, manifest, args.manifest_sha256)
            tool = _private_tool(args.tool_result)
            review_raw, _review_info = store.read(REVIEW)
            review = metadata.base._decode_json(review_raw)
            fields = {'schema', 'state', 'manifest_sha256', 'command_sha256', 'marker_sha256',
                'receipt_sha256', 'snapshot', 'execution_exit', 'execution_record_sha256',
                'engineering', 'security', 'prepared_at', 'reviewed_at', 'expires_at',
                'observer_kind', 'authority'}
            check_seal(review, fields)
            expected = review_record(manifest, args.manifest_sha256, marker_sha256=marker,
                receipt=receipt, tool_result=tool, engineering=review['engineering'],
                security=review['security'], reviewed_at=review['reviewed_at'])
            ensure(review_raw == canonical(expected) + b'\n')
            fields = inspect_fields(raw)
            report = {'schema': 'config-snapshot-fields-v1', 'manifest_sha256': args.manifest_sha256,
                'payload_sha256': receipt['snapshot']['sha256'], 'expires_at': manifest['expires_at'],
                'fields': fields, 'authority': dict(AUTHORITY)}
            serialized = canonical(report) + b'\n'
            ensure(len(serialized) <= 32768)
            try:
                info = store.write(REPORT, serialized)
                budget.check()
            except Exception as error:
                store.budget = Budget(10, clock=clock, utc=utc, manifest=manifest, expiry=False)
                try:
                    store.remove_created([REPORT])
                except Exception:
                    raise SnapshotFailure('cleanup', 'inspection') from None
                code = error.code if isinstance(error, SnapshotFailure) and error.code in ('expiry', 'deadline') else 'payload_output'
                raise SnapshotFailure(code, 'inspection') from None
            return {'outcome': 'private-field-report-written', 'report': identity(info, serialized),
                    'authority': dict(AUTHORITY)}
    except Exception as error:
        if isinstance(error, SnapshotFailure):
            raise SnapshotFailure(error.code, error.stage) from None
        raise SnapshotFailure('binding', 'inspection') from None


@contextmanager
def fresh_record_directory(path, manifest, budget):
    """Admit one fresh separate private record directory, never extra action leaves."""
    metadata.base._path(path)
    parent, descriptor = metadata.base._parent(path), None
    try:
        os.mkdir(Path(path).name, mode=0o700, dir_fd=parent)
        descriptor = os.open(Path(path).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        info = os.fstat(descriptor)
        named = os.stat(Path(path).name, dir_fd=parent, follow_symlinks=False)
        ensure((info.st_dev, info.st_ino) == (named.st_dev, named.st_ino) and info.st_uid == os.getuid() and
               stat.S_IMODE(info.st_mode) == 0o700)
        os.fsync(parent)
        local = copy.deepcopy(manifest)
        local['acquisition_plan']['context'].update(output_directory=path, output_directory_fingerprint={
            'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid})
        with Store(local, budget, descriptor=descriptor) as output:
            ensure(output.census() == set())
            yield output
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent)


def _cleanup_receipt(manifest, digest, marker, expected, remaining):
    return sealed({'schema': 'config-snapshot-cleanup-v1', 'manifest_sha256': digest,
        'marker_sha256': marker, 'expected_artifacts': expected,
        'outcome': 'cleanup-incomplete' if remaining else 'owned-retained-data-absent',
        'remaining_retained_data': remaining, 'observer_kind': 'local-unattested', 'authority': dict(AUTHORITY)})


def checked_cleanup(value, manifest, digest, marker):
    check_seal(value, {'schema', 'manifest_sha256', 'marker_sha256', 'expected_artifacts', 'outcome',
                       'remaining_retained_data', 'observer_kind', 'authority'})
    ensure(type(value['expected_artifacts']) is dict and
           set(value['expected_artifacts']) in ({PAYLOAD}, {PAYLOAD, REPORT}) and
           type(value['remaining_retained_data']) is list and
           value['remaining_retained_data'] in ([], [PAYLOAD], [REPORT], [PAYLOAD, REPORT]))
    for leaf, observed in value['expected_artifacts'].items():
        checked_identity(observed, payload=leaf == PAYLOAD, complete=False)
    ensure(value == _cleanup_receipt(manifest, digest, marker, value['expected_artifacts'],
                                     value['remaining_retained_data']))


@locked_action(10)
def cleanup_action(args, *, clock=time.monotonic, utc=time.time):
    try:
        manifest = _load(args)
        budget = _budget(args, manifest, 10, clock, utc, expiry=False)
        _verify_source(manifest, args, cleanup=True)
        expected = {PAYLOAD: metadata.base._decode_json(args.expected_payload.encode())}
        if args.expected_report is not None:
            expected[REPORT] = metadata.base._decode_json(args.expected_report.encode())
        for leaf, value in expected.items():
            checked_identity(value, payload=leaf == PAYLOAD, complete=False)
        with Store(manifest, budget, descriptor=args._snapshot_directory_fd) as store:
            names = store.census()
            ensure(store.read(MANIFEST)[0] == canonical(manifest) + b'\n')
            ensure(store.read(MARKER)[0] == canonical({'manifest_sha256': args.manifest_sha256}) + b'\n')
            recovery = getattr(args, 'recovery_directory', None)
            marker = sha(store.read(MARKER)[0])
            if CLEANUP in names:
                checked_cleanup(metadata.base._decode_json(store.read(CLEANUP)[0]),
                                manifest, args.manifest_sha256, marker)
                ensure(recovery is not None)
            ensure(REPORT not in names or REPORT in expected)
            # Validate the WHOLE deletion set before deleting the first member.
            pinned = {}
            for leaf, wanted in expected.items():
                if leaf in names:
                    raw, info = store.read(leaf, 2646 if leaf == PAYLOAD else 32768)
                    actual = identity(info, raw, payload=leaf == PAYLOAD)
                    actual['durably_verified'] = wanted['durably_verified']
                    ensure(actual == wanted)
                    pinned[leaf] = info
            recording = fresh_record_directory(recovery, manifest, budget) if recovery else nullcontext(store)
            with recording as output:
                failed = False
                try:
                    for leaf, info in pinned.items():
                        store.named(leaf, info)
                        os.unlink(leaf, dir_fd=store.fd)
                        os.fsync(store.fd)
                        ensure(leaf not in store.census(), 'cleanup')
                    ensure(not ({PAYLOAD, REPORT} & store.census()), 'cleanup')
                except Exception:
                    failed = True
                remaining = [leaf for leaf in (PAYLOAD, REPORT) if leaf in store.census()]
                result = _cleanup_receipt(manifest, args.manifest_sha256, marker, expected, remaining)
                checked_cleanup(result, manifest, args.manifest_sha256, marker)
                output.publish(CLEANUP, canonical(result) + b'\n', 'cleanup')
                budget.check()
                ensure(not failed and not remaining, 'cleanup')
                return result
    except Exception:
        raise SnapshotFailure('cleanup', 'cleanup') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    preparation = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'contract', 'image-inputs', 'ca-file', 'ca-sha256', 'platform-file', 'directory'):
        preparation.add_argument('--' + name, required=True)
    preparation.add_argument('--expires-at', required=True, type=int)
    for verb in ('execute', 'verify', 'inspect', 'cleanup'):
        command = commands.add_parser(verb)
        for name in ('manifest', 'manifest-sha256', 'runner-sha256'):
            command.add_argument('--' + name, required=True)
        if verb in ('verify', 'inspect'):
            command.add_argument('--tool-result', required=True)
        if verb == 'cleanup':
            command.add_argument('--expected-payload', required=True)
            command.add_argument('--expected-report')
            command.add_argument('--cleanup-source-sha', required=True)
            command.add_argument('--cleanup-closure-sha256', required=True)
            command.add_argument('--recovery-directory')
    args = parser.parse_args()
    failed = None
    try:
        if args.command == 'prepare':
            digest = prepare_action(args)
            print('File-only snapshot manifest prepared; manifest_sha256=' + digest)
        else:
            ensure(dict(os.environ) == {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
            if args.command == 'execute':
                execute_action(args)
                print(SUCCESS)
            else:
                result = {'verify': verify_action, 'inspect': inspect_action, 'cleanup': cleanup_action}[args.command](args)
                print(canonical(result).decode('ascii'))
    except Exception as error:
        failed = error if isinstance(error, SnapshotFailure) else SnapshotFailure()
    if failed is not None:
        parser.exit(1, ERROR + '; stage=' + failed.stage + '; failure=' + failed.code + '\n')


if __name__ == '__main__':
    # A fixed sibling import path supports -I -S without ambient Python paths.
    main()

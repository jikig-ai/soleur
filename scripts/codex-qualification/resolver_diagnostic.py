"""Dormant one-use resolver diagnostic; preparation and execution need new approval.

Only the separate supervisor may invoke the coordinator. An admitted answer is
not image admission, provenance, acquisition, qualification or retry authority.
No operational artifact has been prepared by implementing this source.
"""
import argparse
import ast
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import select
import stat
import subprocess
import sys
import time

if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).absolute().parent))

import config_https as policy
from prepare import Refused, canonical, sha

ERROR = 'Resolver diagnostic refused'
MANIFEST = 'resolver-diagnostic-manifest.json'
MARKER = '.resolver-diagnostic-consumed'
RECEIPT = 'resolver-diagnostic-receipt.json'
SOURCE_ROOTS = ('resolver_diagnostic.py', 'resolver_probe.py', 'resolver_supervisor.py',
                'test_resolver_diagnostic.py', 'test_resolver_lifecycle.py', 'config_https.py')
AUTHORITY = ('acquisition', 'publisher_verified', 'image_admitted', 'profile_admitted',
             'runtime_authorized', 'recovery_authorized', 'qualified', 'retry_authorized')
OUTCOMES = frozenset((
    ('local_refusal', 'prelaunch', 0, 'not_started'),
    ('launch_refusal', 'launch', 0, 'not_started'),
    ('resolution_refusal', 'resolution', 1, 'reaped'),
    ('answer_refusal', 'answers', 1, 'reaped'),
    ('protocol_refusal', 'protocol', 1, 'reaped'),
    ('address_refusal', 'address_policy', 1, 'reaped'),
    ('deadline_refusal', 'prelaunch', 0, 'not_started'),
    ('deadline_refusal', 'helper', 1, 'reaped'),
    ('cleanup_uncertain', 'cleanup', 1, 'uncertain'),
    ('admitted', 'complete', 1, 'reaped'),
    ('internal_refusal', 'prelaunch', 0, 'not_started'),
    ('internal_refusal', 'helper', 1, 'reaped')))
CATEGORIES = frozenset(row[0] for row in OUTCOMES)
STAGES = frozenset(row[1] for row in OUTCOMES)


def ensure(value):
    if not value:
        raise Refused(ERROR)


def _hex(value, length=64):
    ensure(type(value) is str and re.fullmatch('[0-9a-f]{' + str(length) + '}', value))


def _path(value):
    policy.metadata.base._path(value)


def _identity(value):
    ensure(type(value) is dict and set(value) == {'dev', 'ino', 'uid'} and
           all(type(item) is int and 0 <= item < 2**64 for item in value.values()))


def action_manifest(*, source_sha, repo, attempt, directory, identity, files, runtime):
    """Pure closed constructor; no source reads, directories or runtime operations."""
    _hex(source_sha, 40)
    _path(repo)
    _path(directory)
    ensure(type(attempt) is str and re.fullmatch('[a-zA-Z0-9_-]{1,64}', attempt))
    _identity(identity)
    ensure(type(files) is dict and set(SOURCE_ROOTS) <= set(files) and len(files) <= 64)
    for name, digest in files.items():
        ensure(type(name) is str and re.fullmatch(r'[a-zA-Z0-9_]+\.py', name))
        _hex(digest)
    ensure(type(runtime) is dict and set(runtime) == {'executable', 'sha256', 'version', 'platform'})
    _path(runtime['executable'])
    _hex(runtime['sha256'])
    ensure(runtime['platform'] == 'linux' and type(runtime['version']) is list and
           len(runtime['version']) == 3 and all(type(v) is int and 0 <= v < 1000 for v in runtime['version']))
    return {'version': 1, 'kind': 'fixed-auth-resolver-diagnostic', 'source_sha': source_sha,
        'repo': repo, 'attempt': attempt, 'directory': directory, 'identity': copy.deepcopy(identity),
        'files': copy.deepcopy(files), 'runtime': copy.deepcopy(runtime),
        'host': 'auth.docker.io', 'port': 443, 'body_timeout': 10, 'cancel_reserve': .25,
        'outer_timeout': 12, 'kill_grace': 1, 'maximum_rows': 16, 'maximum_output_bytes': 4096,
        'marker_name': MARKER, 'receipt_name': RECEIPT,
        'authority': dict.fromkeys(AUTHORITY, False), 'review': 'pending'}


def checked_manifest(value, digest):
    try:
        _hex(digest)
        ensure(type(value) is dict and len(canonical(value)) <= 32768 and sha(canonical(value)) == digest)
        expected = action_manifest(**{key: value[key] for key in (
            'source_sha', 'repo', 'attempt', 'directory', 'identity', 'files', 'runtime')})
        ensure(canonical(expected) == canonical(value))
    except Exception:
        raise Refused(ERROR) from None


def _bindings(manifest, digest, marker):
    return {'manifest_sha256': digest, 'marker_sha256': marker, 'source_sha': manifest['source_sha'],
        'files': copy.deepcopy(manifest['files']), 'runtime': copy.deepcopy(manifest['runtime']),
        'output_directory': manifest['directory'], 'output_identity': copy.deepcopy(manifest['identity']),
        'host': manifest['host'], 'port': manifest['port'],
        'body_timeout': 10, 'outer_timeout': 12, 'kill_grace': 1, 'cancel_reserve': .25,
        'maximum_rows': 16, 'maximum_output_bytes': 4096}


def receipt(manifest, digest, marker, category, stage, launches, cleanup):
    checked_manifest(manifest, digest)
    _hex(marker)
    ensure(type(launches) is int and (category, stage, launches, cleanup) in OUTCOMES)
    result = {'schema': 'resolver-diagnostic-receipt-v1', 'bindings': _bindings(manifest, digest, marker),
        'category': category, 'stage': stage, 'helper_launches': launches, 'cleanup': cleanup,
        'authority': dict.fromkeys(AUTHORITY, False), 'review': 'pending',
        'finalization': 'provisional', 'action_accepted': False}
    result['receipt_sha256'] = sha(canonical(result))
    return result


def checked_receipt(value, manifest, digest, marker):
    try:
        ensure(type(value) is dict)
        expected = receipt(manifest, digest, marker, value['category'], value['stage'],
                           value['helper_launches'], value['cleanup'])
        ensure(canonical(value) == canonical(expected))
    except Exception:
        raise Refused(ERROR) from None


def checked_completed_action(value, completion, manifest, digest, marker, *, supervisor_exit):
    try:
        checked_receipt(value, manifest, digest, marker)
        ensure((value['category'], value['stage'], value['helper_launches'], value['cleanup']) ==
               ('admitted', 'complete', 1, 'reaped'))
        ensure(type(supervisor_exit) is int and supervisor_exit == 0)
        import resolver_supervisor
        resolver_supervisor.checked_completion(completion, manifest_sha256=digest,
            source_sha=manifest['source_sha'], supervisor_sha256=manifest['files']['resolver_supervisor.py'],
            receipt_sha256=value['receipt_sha256'], supervisor_exit=supervisor_exit)
    except Exception:
        raise Refused(ERROR) from None


def decode(raw):
    ensure(type(raw) is bytes and len(raw) <= 32768)
    def pairs(values):
        result = {}
        for key, value in values:
            ensure(key not in result)
            result[key] = value
        return result
    return json.loads(raw.decode('ascii'), object_pairs_hook=pairs,
        parse_constant=lambda _value: ensure(False))


def classify(raw, code):
    """Classify only an observed protocol boundary; never retain answers/errors."""
    try:
        ensure(type(raw) is bytes and 0 < len(raw) <= 4096 and type(code) is int)
        value = decode(raw)
        ensure(type(value) is dict and type(value.get('version')) is int and value['version'] == 1)
        outcome = value.get('outcome')
        if outcome in ('resolution_refusal', 'answer_refusal'):
            ensure(set(value) == {'version', 'outcome'} and
                   code == (4 if outcome == 'resolution_refusal' else 5))
            return outcome, 'resolution' if code == 4 else 'answers'
        ensure(code == 0 and outcome == 'answers' and set(value) == {'version', 'outcome', 'rows'})
    except Exception:
        return 'protocol_refusal', 'protocol'
    try:
        # config_https.py › selected_address() validates the WHOLE set unchanged.
        # No BoundedHTTPS, connection, TLS or acquisition path is called here.
        policy.selected_address(value['rows'])
    except Exception:
        return 'address_refusal', 'address_policy'
    return 'admitted', 'complete'


class Deadline(Refused):
    pass


class ClosedParser(argparse.ArgumentParser):
    def error(self, _message):
        print(ERROR + '; preconsume_stage=startup')
        raise SystemExit(1)


class Budget:
    def __init__(self, clock, deadline):
        self.clock, self.deadline, self.last = clock, deadline, -math.inf

    def remaining(self, reserve=0.):
        now = self.clock()
        if (type(now) not in (int, float) or not math.isfinite(now) or now < self.last or
                type(self.deadline) not in (int, float) or not math.isfinite(self.deadline) or
                now >= self.deadline - reserve):
            raise Deadline(ERROR)
        self.last = now
        return self.deadline - reserve - now


def read_helper(process, deadline, clock):
    budget = Budget(clock, deadline)
    os.set_blocking(process.stdout.fileno(), False)
    raw = bytearray()
    while True:
        readable, _, _ = select.select([process.stdout], [], [], budget.remaining())
        budget.remaining()
        if not readable:
            raise Deadline(ERROR)
        part = os.read(process.stdout.fileno(), min(4097 - len(raw), 4096))
        if not part:
            return bytes(raw)
        raw.extend(part)
        if len(raw) > 4096:
            return bytes(raw)


def run_helper(*, deadline, clock=time.monotonic, launch=None, reader=read_helper):
    """Exactly one fresh helper, same group/session, one bounded memory-only pipe."""
    budget = Budget(clock, deadline)
    launch = subprocess.Popen if launch is None else launch
    process, raw, launched = None, None, 0
    result = ('internal_refusal', 'prelaunch', 0, 'not_started')
    try:
        budget.remaining(.25)
        try:
            process = launch([sys.executable, '-I', '-S', '-B',
                str(Path(__file__).with_name('resolver_probe.py').absolute()), 'auth.docker.io', str(os.getpid())],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                env={}, close_fds=True, cwd='/')
        except Exception:
            return 'launch_refusal', 'launch', 0, 'not_started'
        launched = 1
        budget.remaining(.25)
        raw = reader(process, deadline - .25, clock)
        code = process.wait(timeout=budget.remaining(.25))
        budget.remaining(.25)
        category, stage = classify(raw, code)
        result = category, stage, 1, 'reaped'
    except (Deadline, subprocess.TimeoutExpired):
        result = ('deadline_refusal', 'helper', 1, 'reaped') if launched else (
            'deadline_refusal', 'prelaunch', 0, 'not_started')
    except Exception:
        result = ('internal_refusal', 'helper', 1, 'reaped') if launched else result
    finally:
        raw = None
        if process is not None:
            try:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=budget.remaining())
            except Exception:
                result = 'cleanup_uncertain', 'cleanup', 1, 'uncertain'
            finally:
                if process.stdout is not None:
                    try:
                        process.stdout.close()
                    except Exception:
                        result = 'cleanup_uncertain', 'cleanup', 1, 'uncertain'
    return result


class Diagnostic:
    """One-use injected coordinator; construction neither consumes nor launches."""
    def __init__(self, manifest, digest, consume, binding, *, helper=run_helper,
                 clock=time.monotonic, deadline):
        checked_manifest(manifest, digest)
        ensure(all(callable(value) for value in (consume, binding, helper, clock)))
        self.manifest, self.digest = copy.deepcopy(manifest), digest
        self.consume, self.binding, self.helper = consume, binding, helper
        self.clock, self.deadline, self.attempted = clock, deadline, False

    def collect(self):
        ensure(not self.attempted)
        self.attempted = True
        budget = Budget(self.clock, self.deadline)
        failed, marker = False, None
        try:
            checked_manifest(self.manifest, self.digest)
            budget.remaining(.5)
            self.binding()
            budget.remaining(.5)
            marker = self.consume()
            _hex(marker)
        except Exception:
            failed = True
        if failed:
            # Outside the exception handler: no private underlying context survives.
            raise Refused(ERROR)
        outcome = None
        try:
            budget.remaining(.5)
            self.binding()
            budget.remaining(.5)
        except Deadline:
            outcome = 'deadline_refusal', 'prelaunch', 0, 'not_started'
        except Exception:
            outcome = 'local_refusal', 'prelaunch', 0, 'not_started'
        if outcome is None:
            try:
                outcome = self.helper(deadline=self.deadline - .25, clock=self.clock)
                ensure(type(outcome) is tuple and len(outcome) == 4 and
                       type(outcome[2]) is int and outcome in OUTCOMES)
            except Exception:
                # A helper adapter failure cannot establish a zero-launch claim.
                outcome = 'cleanup_uncertain', 'cleanup', 1, 'uncertain'
        return receipt(self.manifest, self.digest, marker, *outcome)


class PrivateOutput:
    """No-follow descriptor-relative output; exclusive marker is never removed."""
    def __init__(self, directory, identity):
        _path(directory)
        _identity(identity)
        self.directory, self.identity, self.fd = directory, copy.deepcopy(identity), None

    def __enter__(self):
        self.fd = policy.metadata.base._parent(self.directory + '/sentinel')
        try:
            self.check()
        except Exception:
            descriptor, self.fd = self.fd, None
            os.close(descriptor)
            raise Refused(ERROR) from None
        return self

    def __exit__(self, *_args):
        if self.fd is not None:
            descriptor, self.fd = self.fd, None
            os.close(descriptor)

    def check(self):
        current = policy.metadata.base._parent(self.directory + '/sentinel')
        try:
            info, pinned = os.fstat(current), os.fstat(self.fd)
            ensure((info.st_dev, info.st_ino) == (pinned.st_dev, pinned.st_ino) and
                   info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700 and
                   {'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid} == self.identity)
        finally:
            os.close(current)

    def read(self, name, maximum=32768):
        self.check()
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
        try:
            info = os.fstat(fd)
            ensure(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and
                stat.S_IMODE(info.st_mode) == 0o600 and info.st_uid == os.getuid() and info.st_size <= maximum)
            result = bytearray()
            while len(result) <= maximum:
                part = os.read(fd, min(4096, maximum - len(result) + 1))
                if not part:
                    break
                result.extend(part)
            ensure(len(result) <= maximum and os.fstat(fd) == info)
            self.check()
            return bytes(result)
        finally:
            os.close(fd)

    def write(self, name, value, *, rollback, retain=False):
        descriptor, pin, owned = None, None, None
        try:
            self.check()
            descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=self.fd)
            owned = os.fstat(descriptor)
            pin = os.dup(descriptor)
            raw = canonical(value) + b'\n'
            while raw:
                size = os.write(descriptor, raw)
                ensure(size > 0)
                raw = raw[size:]
            os.fsync(descriptor)
            os.fsync(self.fd)
            writer, descriptor = descriptor, None
            os.close(writer)
            self.check()
            ensure(os.stat(name, dir_fd=self.fd, follow_symlinks=False) == os.fstat(pin) and
                   os.fstat(pin).st_nlink == 1)
            if retain:
                retained, pin = pin, None
                return retained
        except Exception:
            if rollback and owned is not None:
                try:
                    current = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
                    if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                        os.unlink(name, dir_fd=self.fd)
                except OSError:
                    raise Refused(ERROR) from None
            raise Refused(ERROR) from None
        finally:
            for value in (descriptor, pin):
                if value is not None:
                    try:
                        os.close(value)
                    except OSError:
                        raise Refused(ERROR) from None

    def consume(self, digest):
        try:
            _hex(digest)
            self.check()
            ensure(set(os.listdir(self.fd)) == {MANIFEST})
            self.write(MARKER, {'kind': 'resolver-diagnostic-consumed-v1', 'manifest_sha256': digest}, rollback=False)
            return sha(self.read(MARKER))
        except Exception:
            raise Refused(ERROR) from None

    def publish(self, result, manifest, digest, marker):
        try:
            self.check()
            ensure(set(os.listdir(self.fd)) == {MANIFEST, MARKER} and sha(self.read(MARKER)) == marker)
            ensure(self.read(MANIFEST) == canonical(manifest) + b'\n')
            checked_receipt(result, manifest, digest, marker)
            pin = self.write(RECEIPT, result, rollback=True, retain=True)
            return [pin, os.dup(self.fd)]
        except Exception:
            raise Refused(ERROR) from None

    @staticmethod
    def rollback_published(name, receipt_fd, directory_fd):
        """Unlink only while both the created inode and directory remain pinned."""
        if receipt_fd is None or directory_fd is None:
            return
        try:
            owned = os.fstat(receipt_fd)
            current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                os.unlink(name, dir_fd=directory_fd)
                os.fsync(directory_fd)
        except OSError:
            raise Refused(ERROR) from None


def source_census(root):
    """Read source only, recursively binding every statically imported local file."""
    pending, files = list(SOURCE_ROOTS), {}
    while pending:
        name = pending.pop()
        if name in files:
            continue
        ensure(len(files) < 64)
        raw = policy.metadata.base._read(str(root / name))
        files[name] = sha(raw)
        tree = ast.parse(raw)
        for node in ast.walk(tree):
            modules = [alias.name for alias in node.names] if isinstance(node, ast.Import) else (
                [node.module] if isinstance(node, ast.ImportFrom) and node.module else [])
            for module in modules:
                local = module.split('.')[0] + '.py'
                if (root / local).is_file() and local not in files:
                    pending.append(local)
    return files


def runtime_identity():
    executable = str(Path(sys.executable).resolve())
    ensure(sys.platform == 'linux')
    # Hash the interpreter without importing site or consulting a network service.
    digest = hashlib.sha256()
    with open(executable, 'rb') as stream:
        for block in iter(lambda: stream.read(65536), b''):
            digest.update(block)
    return {'executable': executable, 'sha256': digest.hexdigest(),
            'version': list(sys.version_info[:3]), 'platform': 'linux'}


def _git(repo, *arguments, timeout):
    # Inherited GIT_* can redirect a child into an unrelated repository.
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    return subprocess.run(['git', '-C', repo, '-c', 'core.fsmonitor=false', *arguments],
        env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, close_fds=True, check=True, timeout=timeout).stdout


def verify_sources(manifest, budget):
    root = Path(manifest['repo']) / 'scripts/codex-qualification'
    ensure(root == Path(__file__).absolute().parent and runtime_identity() == manifest['runtime'])
    files = source_census(root)
    ensure(files == manifest['files'])
    ensure(_git(manifest['repo'], 'rev-parse', 'HEAD', timeout=budget.remaining(.25)).decode().strip() == manifest['source_sha'])
    ensure(not _git(manifest['repo'], 'status', '--porcelain', '--untracked-files=no',
                    timeout=budget.remaining(.25)).strip())
    for name, digest in files.items():
        budget.remaining(.25)
        ensure(sha(_git(manifest['repo'], 'show', manifest['source_sha'] +
            ':scripts/codex-qualification/' + name, timeout=budget.remaining(.25))) == digest)
    budget.remaining(.25)


def prepare_action(args):
    """Dormant file-only preparation; offline coverage fabricates every binding."""
    root = Path(args.repo) / 'scripts/codex-qualification'
    context = {'source_sha': args.source_sha, 'repo': args.repo, 'attempt': args.attempt,
        'files': source_census(root), 'runtime': runtime_identity()}
    # Verify clean committed source before creating a new private action directory.
    provisional = action_manifest(directory=args.directory,
        identity={'dev': 0, 'ino': 0, 'uid': os.getuid()}, **context)
    verify_sources(provisional, Budget(time.monotonic, time.monotonic() + 10.))
    parent = policy.metadata.base._parent(args.directory)
    owned, descriptor = None, None
    try:
        os.mkdir(Path(args.directory).name, 0o700, dir_fd=parent)
        descriptor = os.open(Path(args.directory).name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        owned = os.fstat(descriptor)
        identity = {'dev': owned.st_dev, 'ino': owned.st_ino, 'uid': owned.st_uid}
        manifest = action_manifest(directory=args.directory, identity=identity, **context)
        with PrivateOutput(args.directory, identity) as store:
            ensure(not os.listdir(store.fd))
            store.write(MANIFEST, manifest, rollback=True)
        return sha(canonical(manifest))
    except Exception:
        if owned is not None:
            try:
                current = os.stat(Path(args.directory).name, dir_fd=parent, follow_symlinks=False)
                if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                    os.rmdir(Path(args.directory).name, dir_fd=parent)
            except OSError:
                raise Refused(ERROR) from None
        raise Refused(ERROR) from None
    finally:
        # Keep the created directory inode alive through acceptance AND rollback.
        # A close error consumes its slot; never retry an ambiguously closed FD.
        values, descriptor, parent = (descriptor, parent), None, None
        failed = False
        for value in values:
            if value is not None:
                try:
                    os.close(value)
                except OSError:
                    failed = True
        if failed:
            raise Refused(ERROR)


def coordinate(args, *, clock=time.monotonic):
    """Dormant coordinator; all startup/publication failures remain sanitized."""
    from resolver_supervisor import arm_parent_death
    started = clock()
    budget = Budget(clock, started + 10.)
    stage, consumed, publication = 'startup', False, None
    try:
        arm_parent_death(args.parent_pid)
        ensure(os.getpid() == os.getpgrp() == os.getsid(0))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        stage = 'manifest'
        raw = policy.metadata.base._read(args.manifest, 32768)
        manifest = decode(raw)
        checked_manifest(manifest, args.manifest_sha256)
        ensure(args.manifest == manifest['directory'] + '/' + MANIFEST)
        # Bind the actual parent invocation to the dedicated outer supervisor.
        expected_parent = [manifest['runtime']['executable'], '-I', '-S', '-B',
            str(Path(__file__).with_name('resolver_supervisor.py').absolute()), 'execute',
            '--manifest', args.manifest, '--manifest-sha256', args.manifest_sha256,
            '--supervisor-sha256', manifest['files']['resolver_supervisor.py']]
        actual_parent = Path('/proc/' + str(args.parent_pid) + '/cmdline').read_bytes().split(b'\0')[:-1]
        ensure(actual_parent == [value.encode() for value in expected_parent])
        stage = 'source_binding'
        verify_sources(manifest, budget)
        stage = 'private_output'
        with PrivateOutput(manifest['directory'], manifest['identity']) as store:
            ensure(store.read(MANIFEST) == canonical(manifest) + b'\n')
            budget.remaining(.5)
            stage = 'gate_publication'
            def consume():
                nonlocal consumed, stage
                marker = store.consume(args.manifest_sha256)
                consumed, stage = True, 'post_gate'
                return marker
            def binding():
                store.check()
                ensure(store.read(MANIFEST) == canonical(manifest) + b'\n')
                verify_sources(manifest, budget)
            result = Diagnostic(manifest, args.manifest_sha256, consume, binding,
                clock=clock, deadline=started + 10.).collect()
            budget.remaining()
            stage = 'receipt_publication'
            publication = store.publish(result, manifest, args.manifest_sha256,
                                        result['bindings']['marker_sha256'])
            budget.remaining()
        budget.remaining()
        for index in range(len(publication)):
            descriptor = publication[index]
            publication[index] = None
            os.close(descriptor)
            budget.remaining()
        publication = None
        if result['category'] != 'admitted':
            return 1
        candidate = {'schema': 'resolver-coordinator-completion-v1',
            'manifest_sha256': args.manifest_sha256, 'source_sha': manifest['source_sha'],
            'supervisor_sha256': manifest['files']['resolver_supervisor.py'],
            'receipt_sha256': result['receipt_sha256']}
        print('Resolver diagnostic candidate=' + json.dumps(candidate, sort_keys=True, separators=(',', ':')))
        return 0
    except Exception:
        cleanup_uncertain = False
        if publication is not None:
            try:
                if all(descriptor is not None for descriptor in publication):
                    PrivateOutput.rollback_published(RECEIPT, *publication)
            except Exception:
                cleanup_uncertain = True
            for descriptor in publication:
                if descriptor is None:
                    continue
                try:
                    os.close(descriptor)
                except Exception:
                    cleanup_uncertain = True
        # A failed marker write may already have consumed the action. Never remove
        # it, fabricate a receipt, claim absence, or infer permission to retry.
        print('Resolver diagnostic publication refused' if consumed or cleanup_uncertain else
              'Resolver diagnostic refused; preconsume_stage=' + stage)
        return 1


def main():
    parser = ClosedParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    for name in ('repo', 'source-sha', 'attempt', 'directory'):
        prepare.add_argument('--' + name, required=True)
    execute = commands.add_parser('_coordinate')
    execute.add_argument('--manifest', required=True)
    execute.add_argument('--manifest-sha256', required=True)
    execute.add_argument('--parent-pid', type=int, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            print('File-only resolver manifest prepared; manifest_sha256=' + prepare_action(args))
            return 0
        return coordinate(args)
    except Exception:
        print(ERROR)
        return 1


if __name__ == '__main__':
    sys.exit(main())

"""Synthesized offline resolver contract tests; never invoke the real helper."""
import copy
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import resolver_diagnostic as diagnostic
import resolver_probe as probe
import resolver_supervisor as supervisor


ROWS = [[int(socket.AF_INET), '8.8.8.8', 443, 0, 0]]
CANARY = 'SYNTHETIC_SECRET_DO_NOT_RETAIN'
_OFFLINE_GUARDS = []


def setUpModule():
    # Guard even broken source: these tests may only use injected resolvers and
    # injected process doubles. Never let a regression launch the real helper.
    for target in ('socket.getaddrinfo', 'socket.socket', 'socket.create_connection', 'subprocess.Popen'):
        guard = patch(target, side_effect=AssertionError('Offline test boundary refused'))
        guard.start()
        _OFFLINE_GUARDS.append(guard)


def tearDownModule():
    for guard in reversed(_OFFLINE_GUARDS):
        guard.stop()
    _OFFLINE_GUARDS.clear()


def plan(directory='/synthetic/output', identity=None):
    return diagnostic.action_manifest(source_sha='a' * 40, repo='/synthetic/repo',
        attempt='synthetic-only', directory=directory,
        identity=identity or {'dev': 1, 'ino': 2, 'uid': os.getuid()},
        files={name: 'b' * 64 for name in diagnostic.SOURCE_ROOTS},
        runtime={'executable': '/synthetic/python', 'sha256': 'c' * 64,
                 'version': [3, 12, 0], 'platform': 'linux'})


def answer(rows=ROWS):
    return diagnostic.canonical({'version': 1, 'outcome': 'answers', 'rows': rows})


class Contracts(unittest.TestCase):
    def setUp(self):
        self.plan = plan()
        self.digest = diagnostic.sha(diagnostic.canonical(self.plan))
        self.marker = 'd' * 64

    def receipt(self, category='admitted', stage='complete', launches=1, cleanup='reaped'):
        return diagnostic.receipt(self.plan, self.digest, self.marker,
                                  category, stage, launches, cleanup)

    def test_manifest_closed_fixed_action_and_no_authority(self):
        diagnostic.checked_manifest(self.plan, self.digest)
        self.assertEqual(self.plan['host'], 'auth.docker.io')
        self.assertEqual(self.plan['port'], 443)
        self.assertEqual(self.plan['body_timeout'], 10)
        self.assertEqual(self.plan['outer_timeout'], 12)
        self.assertEqual(self.plan['kill_grace'], 1)
        self.assertEqual(self.plan['cancel_reserve'], .25)
        self.assertEqual(self.plan['maximum_rows'], 16)
        self.assertEqual(self.plan['maximum_output_bytes'], 4096)
        self.assertTrue(all(value is False for value in self.plan['authority'].values()))
        for key, value in [('host', 'synthetic.invalid'), ('port', 80),
                           ('body_timeout', 11), ('outer_timeout', 13),
                           ('authority', {'acquisition': True}), ('unknown', 1)]:
            forged = copy.deepcopy(self.plan)
            forged[key] = value
            with self.subTest(key=key), self.assertRaises(diagnostic.Refused):
                diagnostic.checked_manifest(forged, diagnostic.sha(diagnostic.canonical(forged)))

    def test_manifest_requires_all_new_source_tests_and_policy(self):
        for missing in diagnostic.SOURCE_ROOTS:
            forged = copy.deepcopy(self.plan)
            del forged['files'][missing]
            with self.subTest(missing=missing), self.assertRaises(diagnostic.Refused):
                diagnostic.checked_manifest(forged, diagnostic.sha(diagnostic.canonical(forged)))

    def test_every_permitted_category_is_explicit_and_closed(self):
        outcomes = [('local_refusal', 'prelaunch', 0, 'not_started'),
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
                    ('internal_refusal', 'helper', 1, 'reaped')]
        self.assertEqual(set(row[0] for row in outcomes), set(diagnostic.CATEGORIES))
        for values in outcomes:
            with self.subTest(values=values):
                result = self.receipt(*values)
                diagnostic.checked_receipt(result, self.plan, self.digest, self.marker)
                self.assertEqual(set(result), {'schema', 'bindings', 'category', 'stage',
                    'helper_launches', 'cleanup', 'authority', 'review', 'receipt_sha256'})
                self.assertTrue(all(value is False for value in result['authority'].values()))

    def test_rehashed_forgery_and_every_invalid_outcome_combination_fail_closed(self):
        valid = self.receipt()
        for key, value in [('category', 'dns'), ('stage', 'resolution'),
                           ('helper_launches', 0), ('helper_launches', True),
                           ('cleanup', 'uncertain'), ('unknown', CANARY),
                           ('review', 'passed'), ('authority', {'qualified': True}),
                           ('bindings', {'marker': 'f' * 64})]:
            forged = copy.deepcopy(valid)
            forged[key] = value
            forged['receipt_sha256'] = diagnostic.sha(diagnostic.canonical(
                {k: v for k, v in forged.items() if k != 'receipt_sha256'}))
            with self.subTest(key=key, value=value), self.assertRaises(diagnostic.Refused):
                diagnostic.checked_receipt(forged, self.plan, self.digest, self.marker)
        for category in diagnostic.CATEGORIES:
            for stage in diagnostic.STAGES:
                for launches in (0, 1):
                    for cleanup in ('not_started', 'reaped', 'uncertain'):
                        values = (category, stage, launches, cleanup)
                        if values not in diagnostic.OUTCOMES:
                            with self.subTest(values=values), self.assertRaises(diagnostic.Refused):
                                self.receipt(*values)

    def test_hash_mismatch_and_manifest_substitution_refused(self):
        result = self.receipt()
        result['receipt_sha256'] = '0' * 64
        with self.assertRaises(diagnostic.Refused):
            diagnostic.checked_receipt(result, self.plan, self.digest, self.marker)
        with self.assertRaises(diagnostic.Refused):
            diagnostic.checked_manifest(self.plan, '0' * 64)


class HelperProtocol(unittest.TestCase):
    def resolve(self, *args, **kwargs):
        self.assertEqual(args, ('auth.docker.io', 443))
        self.assertEqual(kwargs, {'type': socket.SOCK_STREAM, 'proto': socket.IPPROTO_TCP})
        return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', 443))]

    def test_injected_resolver_called_exactly_once_and_no_transport(self):
        resolver = Mock(side_effect=self.resolve)
        with patch('socket.socket', side_effect=AssertionError('transport reached')):
            raw, code = probe.probe('auth.docker.io', resolver)
        self.assertEqual(code, 0)
        self.assertEqual(raw, answer())
        resolver.assert_called_once()

    def test_unexpected_host_does_not_call_resolver(self):
        resolver = Mock(side_effect=AssertionError('resolver reached'))
        raw, code = probe.probe('synthetic.invalid', resolver)
        self.assertEqual(code, 3)
        self.assertEqual(json.loads(raw)['outcome'], 'local_refusal')
        resolver.assert_not_called()

    def test_resolution_exception_retains_no_raw_exception(self):
        resolver = Mock(side_effect=RuntimeError(CANARY))
        raw, code = probe.probe('auth.docker.io', resolver)
        self.assertEqual((json.loads(raw)['outcome'], code), ('resolution_refusal', 4))
        self.assertNotIn(CANARY.encode(), raw)
        resolver.assert_called_once()

    def test_malformed_mixed_empty_oversized_and_serialization_answers(self):
        good = (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('8.8.8.8', 443))
        for rows in ([], [good] * 17, [good, (999, 1, 6, '', ('x', 443))],
                     [good, (2, 1, 6, '', (CANARY, 443, 0))],
                     [(2, 1, 6, '', ('x' * 4096, 443))], [object()]):
            with self.subTest(rows=str(rows)[:50]):
                raw, code = probe.probe('auth.docker.io', Mock(return_value=rows))
                self.assertEqual((json.loads(raw)['outcome'], code), ('answer_refusal', 5))
                self.assertNotIn(CANARY.encode(), raw)

    def test_protocol_exit_consistency_duplicates_and_size(self):
        self.assertEqual(diagnostic.classify(answer(), 0), ('admitted', 'complete'))
        for outcome, code, category, stage in [
                ('resolution_refusal', 4, 'resolution_refusal', 'resolution'),
                ('answer_refusal', 5, 'answer_refusal', 'answers')]:
            raw = diagnostic.canonical({'version': 1, 'outcome': outcome})
            self.assertEqual(diagnostic.classify(raw, code), (category, stage))
            self.assertEqual(diagnostic.classify(raw, 0), ('protocol_refusal', 'protocol'))
        for raw, code in [(answer(), 4), (b'x' * 4097, 0), (b'[]', 0),
                          (b'{"version":1,"version":1,"outcome":"answers","rows":[]}', 0),
                          (answer() + CANARY.encode(), 0),
                          (diagnostic.canonical({'version': True, 'outcome': 'answers', 'rows': ROWS}), 0)]:
            self.assertEqual(diagnostic.classify(raw, code), ('protocol_refusal', 'protocol'))

    def test_complete_set_address_policy_unchanged_and_no_raw_answer_retained(self):
        for rows in (ROWS + [[2, '127.0.0.1', 443, 0, 0]],
                     [[2, '192.0.2.1', 443, 0, 0]], [[2, '8.8.8.8', 80, 0, 0]],
                     [[10, '::ffff:8.8.8.8', 443, 0, 0]],
                     [[10, '2001:db8::1', 443, 0, 0]]):
            with self.subTest(rows=rows):
                self.assertEqual(diagnostic.classify(answer(rows), 0), ('address_refusal', 'address_policy'))


class FakeProcess:
    def __init__(self, raw=None, *, timeout=False, cleanup_error=False):
        self.stdout = io.BytesIO(answer() if raw is None else raw)
        self.returncode = None
        self.timeout = timeout
        self.cleanup_error = cleanup_error
        self.killed = False
        self.waits = []

    def poll(self):
        return self.returncode

    def kill(self):
        self.killed = True

    def wait(self, timeout):
        self.waits.append(timeout)
        if self.cleanup_error or self.timeout and not self.killed:
            raise subprocess.TimeoutExpired('synthetic', timeout)
        self.returncode = -9 if self.killed else 0
        return self.returncode


class Runner(unittest.TestCase):
    def run_fake(self, process=None, clock=lambda: 0., launch=None, reader=None):
        process = process or FakeProcess()
        launch = launch or Mock(return_value=process)
        reader = reader or (lambda child, deadline, clock: child.stdout.read(4097))
        return diagnostic.run_helper(deadline=10., clock=clock, launch=launch, reader=reader), process, launch

    def test_fixed_launch_isolated_interpreter_no_detached_session(self):
        result, child, launch = self.run_fake()
        self.assertEqual(result, ('admitted', 'complete', 1, 'reaped'))
        args, kwargs = launch.call_args
        self.assertEqual(args[0][1:4], ['-I', '-S', '-B'])
        self.assertTrue(args[0][4].endswith('/resolver_probe.py'))
        self.assertEqual(args[0][5:], ['auth.docker.io', str(os.getpid())])
        self.assertEqual(kwargs['env'], {})
        self.assertEqual(kwargs['cwd'], '/')
        self.assertTrue(kwargs['close_fds'])
        self.assertFalse(kwargs.get('start_new_session', False))
        self.assertEqual(kwargs['stdin'], subprocess.DEVNULL)
        self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
        self.assertTrue(child.stdout.closed)
        self.assertEqual(launch.call_count, 1)

    def test_local_launch_deadline_protocol_and_cleanup_categories(self):
        result, _, launch = self.run_fake(clock=lambda: 9.8)
        self.assertEqual(result, ('deadline_refusal', 'prelaunch', 0, 'not_started'))
        launch.assert_not_called()
        result, _, _ = self.run_fake(launch=Mock(side_effect=OSError(CANARY)))
        self.assertEqual(result, ('launch_refusal', 'launch', 0, 'not_started'))
        result, child, _ = self.run_fake(FakeProcess(timeout=True))
        self.assertEqual(result, ('deadline_refusal', 'helper', 1, 'reaped'))
        self.assertTrue(child.killed)
        result, _, _ = self.run_fake(FakeProcess(cleanup_error=True))
        self.assertEqual(result, ('cleanup_uncertain', 'cleanup', 1, 'uncertain'))
        result, _, _ = self.run_fake(FakeProcess(raw=CANARY.encode()))
        self.assertEqual(result, ('protocol_refusal', 'protocol', 1, 'reaped'))

    def test_shrinking_backwards_nonfinite_and_exhausted_clock(self):
        for clock in (lambda: float('nan'), lambda: float('inf'), lambda: 11.):
            result, _, launch = self.run_fake(clock=clock)
            self.assertEqual(result, ('deadline_refusal', 'prelaunch', 0, 'not_started'))
            launch.assert_not_called()
        readings = iter((0., 1., .5, .5))
        result, child, _ = self.run_fake(clock=lambda: next(readings, .5))
        self.assertEqual(result, ('cleanup_uncertain', 'cleanup', 1, 'uncertain'))
        self.assertTrue(child.killed)

    def test_reader_failure_does_not_leak_or_retry(self):
        result, child, launch = self.run_fake(reader=Mock(side_effect=RuntimeError(CANARY)))
        self.assertEqual(result, ('internal_refusal', 'helper', 1, 'reaped'))
        self.assertNotIn(CANARY, repr(result))
        self.assertTrue(child.killed)
        launch.assert_called_once()

    def test_stdout_close_failure_is_cleanup_uncertain_after_one_launch(self):
        class CloseFailure(io.BytesIO):
            def close(self):
                super().close()
                raise OSError(CANARY)
        child = FakeProcess()
        child.stdout = CloseFailure(answer())
        result, _, launch = self.run_fake(child)
        self.assertEqual(result, ('cleanup_uncertain', 'cleanup', 1, 'uncertain'))
        launch.assert_called_once()


class Collector(unittest.TestCase):
    def setUp(self):
        self.plan = plan()
        self.digest = diagnostic.sha(diagnostic.canonical(self.plan))
        self.events = []
        self.binding = Mock(side_effect=lambda: self.events.append('binding'))
        self.gate = Mock(side_effect=lambda: (self.events.append('gate') or 'd' * 64))
        self.helper = Mock(side_effect=lambda **kwargs: (self.events.append('helper') or (
            'admitted', 'complete', 1, 'reaped')))

    def collector(self):
        return diagnostic.Diagnostic(self.plan, self.digest, self.gate, self.binding,
            helper=self.helper, clock=lambda: 0., deadline=10.)

    def test_one_use_gate_precedes_single_helper_and_success_has_no_continuation(self):
        collector = self.collector()
        self.assertEqual(self.events, [])
        with (patch('socket.socket', side_effect=AssertionError('connection reached')),
              patch.object(diagnostic.policy, 'BoundedHTTPS', side_effect=AssertionError('HTTPS reached'))):
            result = collector.collect()
        self.assertEqual(self.events, ['binding', 'gate', 'binding', 'helper'])
        self.assertEqual(result['category'], 'admitted')
        self.assertNotIn(b'8.8.8.8', diagnostic.canonical(result))
        diagnostic.checked_receipt(result, self.plan, self.digest, 'd' * 64)
        with self.assertRaises(diagnostic.Refused):
            collector.collect()
        self.helper.assert_called_once()
        self.gate.assert_called_once()

    def test_preconsume_binding_or_gate_failure_has_no_receipt_or_helper(self):
        for failing in (self.binding, self.gate):
            failing.side_effect = RuntimeError(CANARY)
            with self.assertRaises(diagnostic.Refused) as raised:
                self.collector().collect()
            self.assertNotIn(CANARY, str(raised.exception))
            self.helper.assert_not_called()
            failing.side_effect = None

    def test_postconsume_binding_failure_is_local_refusal_without_launch(self):
        self.binding.side_effect = [None, RuntimeError(CANARY)]
        result = self.collector().collect()
        self.assertEqual((result['category'], result['helper_launches']), ('local_refusal', 0))
        self.helper.assert_not_called()
        self.gate.assert_called_once()


class SourceAndCLI(unittest.TestCase):
    def test_synthetic_directory_failure_keeps_owned_inode_pinned_during_rollback(self):
        # Every source/runtime prerequisite is fabricated. Only a fresh scratch
        # directory is written; no repo census or operational binding is read.
        manifest = plan()
        with tempfile.TemporaryDirectory(prefix='resolver-directory-test-') as scratch:
            directory = scratch + '/synthetic-action'
            args = Namespace(repo='/synthetic/repo', source_sha='a' * 40,
                             attempt='synthetic-only', directory=directory)
            real_stat = os.stat
            observed = []
            def check_pin(path, *args, **kwargs):
                info = real_stat(path, *args, **kwargs)
                if path == 'synthetic-action' and kwargs.get('dir_fd') is not None:
                    matching = []
                    for entry in Path('/proc/self/fd').iterdir():
                        try:
                            current = os.fstat(int(entry.name))
                            if (current.st_dev, current.st_ino) == (info.st_dev, info.st_ino):
                                matching.append(int(entry.name))
                        except OSError:
                            current = None
                    observed.append(bool(matching))
                return info
            with (patch.object(diagnostic, 'source_census', return_value=manifest['files']),
                  patch.object(diagnostic, 'runtime_identity', return_value=manifest['runtime']),
                  patch.object(diagnostic, 'verify_sources'),
                  patch.object(diagnostic.PrivateOutput, 'write', side_effect=OSError(CANARY)),
                  patch.object(diagnostic.os, 'stat', side_effect=check_pin)):
                with self.assertRaises(diagnostic.Refused):
                    diagnostic.prepare_action(args)
            self.assertEqual(observed, [True])
            self.assertFalse(Path(directory).exists())

    def test_offline_guard_refuses_real_resolution_and_production_helper_launch(self):
        with self.assertRaises(AssertionError):
            socket.getaddrinfo('must-never-resolve.invalid', 443)
        with self.assertRaises(AssertionError):
            subprocess.Popen(['/synthetic/python', '-I', '-S', '-B',
                str(Path(diagnostic.__file__).with_name('resolver_probe.py')), 'auth.docker.io', str(os.getpid())])

    def test_runtime_source_head_dirty_tree_and_committed_bytes_are_all_bound(self):
        manifest = plan()
        raw = b'synthetic-source-only'
        manifest['files'] = dict.fromkeys(diagnostic.SOURCE_ROOTS, diagnostic.sha(raw))
        def committed(_repo, *args, timeout):
            self.assertGreater(timeout, 0)
            if args[0] == 'rev-parse':
                return b'a' * 40 + b'\n'
            if args[0] == 'status':
                return b''
            return raw
        budget = diagnostic.Budget(lambda: 0., 10.)
        with (patch.object(diagnostic, '__file__', '/synthetic/repo/scripts/codex-qualification/resolver_diagnostic.py'),
              patch.object(diagnostic, 'runtime_identity', return_value=manifest['runtime']) as runtime,
              patch.object(diagnostic, 'source_census', return_value=manifest['files']) as census,
              patch.object(diagnostic, '_git', side_effect=committed) as git):
            diagnostic.verify_sources(manifest, budget)
            runtime.return_value = {**manifest['runtime'], 'sha256': 'f' * 64}
            with self.assertRaises(diagnostic.Refused):
                diagnostic.verify_sources(manifest, budget)
            runtime.return_value = manifest['runtime']
            census.return_value = {**manifest['files'], 'unreviewed.py': 'e' * 64}
            with self.assertRaises(diagnostic.Refused):
                diagnostic.verify_sources(manifest, budget)
            census.return_value = manifest['files']
            for response in (b'c' * 40, b' M synthetic.py\n', b'changed-source'):
                git.side_effect = [b'a' * 40 + b'\n', b'', raw]
                index = 0 if len(response) == 40 else 1 if response.startswith(b' M') else 2
                values = [b'a' * 40 + b'\n', b'', raw]
                values[index] = response
                git.side_effect = values
                with self.subTest(response=response), self.assertRaises(diagnostic.Refused):
                    diagnostic.verify_sources(manifest, budget)

    def test_source_census_binds_transitive_local_imports_and_tests(self):
        with tempfile.TemporaryDirectory(prefix='resolver-source-test-') as scratch:
            root = Path(scratch)
            (root / 'root.py').write_text('import dependency\n')
            (root / 'dependency.py').write_text('from leaf import value\n')
            (root / 'leaf.py').write_text('value=1\n')
            with patch.object(diagnostic, 'SOURCE_ROOTS', ('root.py',)):
                census = diagnostic.source_census(root)
            self.assertEqual(set(census), {'root.py', 'dependency.py', 'leaf.py'})
            self.assertEqual(census['leaf.py'], diagnostic.sha(b'value=1\n'))

    def test_unknown_cli_arguments_cannot_echo_secret_canaries(self):
        for module in (diagnostic, supervisor):
            output, error = io.StringIO(), io.StringIO()
            with patch('sys.argv', ['synthetic', CANARY]), redirect_stdout(output), redirect_stderr(error):
                with self.assertRaises(SystemExit) as raised:
                    module.main()
            self.assertEqual(raised.exception.code, 1)
            self.assertNotIn(CANARY, output.getvalue() + error.getvalue())
            self.assertIn('Resolver diagnostic refused', output.getvalue())


class Output(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='resolver-offline-test-')
        self.addCleanup(self.scratch.cleanup)
        self.directory = self.scratch.name + '/synthetic-action'
        os.mkdir(self.directory, 0o700)
        info = os.stat(self.directory)
        self.plan = plan(self.directory, {'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid})
        self.digest = diagnostic.sha(diagnostic.canonical(self.plan))
        target = Path(self.directory) / diagnostic.MANIFEST
        target.write_bytes(diagnostic.canonical(self.plan) + b'\n')
        target.chmod(0o600)

    def store(self):
        return diagnostic.PrivateOutput(self.directory, self.plan['identity'])

    def test_exclusive_marker_and_owned_receipt_no_retry(self):
        with self.store() as store:
            marker = store.consume(self.digest)
            result = diagnostic.receipt(self.plan, self.digest, marker, 'admitted', 'complete', 1, 'reaped')
            store.publish(result, self.plan, self.digest, marker)
            with self.assertRaises(diagnostic.Refused):
                store.consume(self.digest)
            with self.assertRaises(diagnostic.Refused):
                store.publish(result, self.plan, self.digest, marker)
        for name in (diagnostic.MANIFEST, diagnostic.MARKER, diagnostic.RECEIPT):
            self.assertEqual((Path(self.directory) / name).stat().st_mode & 0o777, 0o600)

    def test_publication_failure_preserves_marker_and_foreign_file(self):
        with self.store() as store:
            marker = store.consume(self.digest)
            target = Path(self.directory) / diagnostic.RECEIPT
            target.write_bytes(CANARY.encode())
            result = diagnostic.receipt(self.plan, self.digest, marker, 'admitted', 'complete', 1, 'reaped')
            with self.assertRaises(diagnostic.Refused):
                store.publish(result, self.plan, self.digest, marker)
            self.assertEqual(target.read_bytes(), CANARY.encode())
            self.assertTrue((Path(self.directory) / diagnostic.MARKER).exists())

    def test_owned_failed_publication_rolls_back_only_its_inode(self):
        with self.store() as store:
            marker = store.consume(self.digest)
            result = diagnostic.receipt(self.plan, self.digest, marker, 'admitted', 'complete', 1, 'reaped')
            with patch.object(diagnostic.os, 'fsync', side_effect=OSError(CANARY)):
                with self.assertRaises(diagnostic.Refused):
                    store.publish(result, self.plan, self.digest, marker)
            self.assertFalse((Path(self.directory) / diagnostic.RECEIPT).exists())
            self.assertTrue((Path(self.directory) / diagnostic.MARKER).exists())

    def test_marker_write_failure_never_rolls_back_consumption(self):
        with self.store() as store:
            with patch.object(diagnostic.os, 'fsync', side_effect=OSError(CANARY)):
                with self.assertRaises(diagnostic.Refused):
                    store.consume(self.digest)
            self.assertTrue((Path(self.directory) / diagnostic.MARKER).exists())
            with self.assertRaises(diagnostic.Refused):
                store.consume(self.digest)

    def test_publication_close_failure_rolls_back_owned_file_and_never_retries_fd(self):
        real_close = os.close
        with self.store() as store:
            marker = store.consume(self.digest)
            result = diagnostic.receipt(self.plan, self.digest, marker, 'admitted', 'complete', 1, 'reaped')
            closed = []
            def fail_writer_close(fd):
                target = os.readlink('/proc/self/fd/' + str(fd))
                real_close(fd)
                if target.endswith('/' + diagnostic.RECEIPT) and not closed:
                    closed.append(fd)
                    raise OSError(CANARY)
                self.assertNotIn(fd, closed, 'Uncertain closed fd was retried')
            with patch.object(diagnostic.os, 'close', side_effect=fail_writer_close):
                with self.assertRaises(diagnostic.Refused):
                    store.publish(result, self.plan, self.digest, marker)
            self.assertFalse((Path(self.directory) / diagnostic.RECEIPT).exists())
            self.assertTrue((Path(self.directory) / diagnostic.MARKER).exists())

    def test_failed_publication_never_rolls_back_foreign_replacement(self):
        with self.store() as store:
            marker = store.consume(self.digest)
            target = Path(self.directory) / diagnostic.RECEIPT
            result = diagnostic.receipt(self.plan, self.digest, marker, 'admitted', 'complete', 1, 'reaped')
            def replace_and_fail(_fd):
                target.unlink()
                target.write_bytes(CANARY.encode())
                raise OSError('synthetic fsync failure')
            with patch.object(diagnostic.os, 'fsync', side_effect=replace_and_fail):
                with self.assertRaises(diagnostic.Refused):
                    store.publish(result, self.plan, self.digest, marker)
            self.assertEqual(target.read_bytes(), CANARY.encode())

    def test_symlink_hardlink_permission_and_directory_replacement_refused(self):
        with self.store() as store:
            source = Path(self.directory) / diagnostic.MANIFEST
            os.link(source, Path(self.directory) / 'foreign-link')
            with self.assertRaises(diagnostic.Refused):
                store.read(diagnostic.MANIFEST)
            os.unlink(Path(self.directory) / 'foreign-link')
            source.chmod(0o644)
            with self.assertRaises(diagnostic.Refused):
                store.read(diagnostic.MANIFEST)
            source.chmod(0o600)
            renamed = self.directory + '-moved'
            os.rename(self.directory, renamed)
            os.mkdir(self.directory, 0o700)
            with self.assertRaises(diagnostic.Refused):
                store.check()


if __name__ == '__main__':
    unittest.main()

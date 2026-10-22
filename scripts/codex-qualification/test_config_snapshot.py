"""Synthesized private snapshot lifecycle; transport is fake, files are real."""
from argparse import Namespace
import copy
import errno
import fcntl
import io
import json
import os
from pathlib import Path
import signal
import select
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from unittest.mock import Mock, patch

import config_acquisition as acquisition
import config_snapshot as snapshot
from prepare import Refused, canonical, sha
import test_config_acquisition as old

REAL_VERIFY_SOURCE = snapshot._verify_source


VALUE = {'os': 'linux', 'architecture': 'amd64',
         'rootfs': {'type': 'layers', 'diff_ids': ['sha256:' + 'a' * 64] * 3},
         'config': {'Env': ['SYNTHETIC_CANARY=private'], 'Cmd': None},
         'x-unknown': {'never-execute': ['$(false)', None, False]}}
BODY = canonical(VALUE)
BODY += b' ' * (2646 - len(BODY))


class Snapshot(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-snapshot-', dir='/var/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'action'
        self.root.mkdir(mode=0o700)
        fixture = old.ConfigAcquisition()
        fixture.setUp()
        context = copy.deepcopy(fixture.context)
        info = self.root.stat()
        context.update(output_directory=str(self.root), output_directory_fingerprint={
            'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid})
        context['bindings']['dependency_sha256'] = {name: sha(Path(snapshot.__file__).with_name(name).read_bytes())
                                                    for name in snapshot.FULL_DEPENDENCIES}
        platform = {**fixture.platform, 'layer_count': 3}
        self.plan = snapshot.action_manifest(acquisition_plan=acquisition.action_manifest(
            retained_image=fixture.image, platform_evidence=platform,
            schema_reference_closure=acquisition.config_schema.reference_closure_sha256(), **context),
            prepared_at=100000, expires_at=101000, browser_contract_expiry=200000)
        self.digest = sha(canonical(self.plan))
        self.write(snapshot.MANIFEST, self.plan)
        self.args = Namespace(manifest=str(self.root / snapshot.MANIFEST), manifest_sha256=self.digest,
            runner_sha256=context['bindings']['dependency_sha256']['config_snapshot.py'])
        self.now, self.utc = 5., 100001
        self.roles = []
        self.responses = [(200, canonical({'token': old.TOKEN})), (307, old.LOCATION), (200, BODY)]
        self.transport = Mock()
        self.transport.request.side_effect = self.respond
        for target in ('socket.getaddrinfo', 'socket.socket', 'socket.create_connection', 'subprocess.Popen'):
            guard = patch(target, side_effect=AssertionError('Offline operation refused'))
            guard.start()
            self.addCleanup(guard.stop)
        for guard in (patch.object(snapshot, '_verify_source', return_value=b'synthetic CA'),
                      patch.object(snapshot.https, 'BoundedHTTPS', return_value=self.transport),
                      patch.object(snapshot.resource, 'setrlimit')):
            guard.start()
            self.addCleanup(guard.stop)

    def write(self, leaf, value):
        path = self.root / leaf
        path.write_bytes(canonical(value) + b'\n')
        path.chmod(0o600)

    def read(self, leaf):
        return json.loads((self.root / leaf).read_bytes())

    def names(self):
        return {entry.name for entry in self.root.iterdir()}

    def respond(self, role, *, location, bearer, deadline, observe):
        self.assertTrue((self.root / snapshot.MARKER).is_file())
        index = acquisition.ROLES.index(role)
        self.assertEqual(bearer, old.TOKEN if index == 1 else None)
        self.assertEqual(location, old.LOCATION if index == 2 else None)
        self.assertLessEqual(deadline, self.now + 10)
        for event, value in [('peer_ok', True), ('tls_ok', True), ('send', None),
                             ('http_status', self.responses[index][0])]:
            observe(event, value)
        self.roles.append(role)
        if index == 2:
            observe('body_bytes', len(self.responses[index][1]))
        return self.responses[index]

    def digest_seam(self, raw):
        # Only the exact synthetic positive control substitutes the pinned digest.
        return acquisition.CONFIG_DIGEST[7:] if raw == BODY else sha(raw)

    def execute(self):
        return snapshot.execute_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)

    def success(self):
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            self.execute()
        return self.read(snapshot.RECEIPT)

    def gate(self):
        result = self.success()
        command = sha(canonical(snapshot.action_command(self.plan, self.digest, 'execute')))
        tool = snapshot.tool_record(command_sha256=command, exit_code=0,
            stdout_sha256=sha(snapshot.SUCCESS.encode() + b'\n'), stderr_sha256=sha(b''),
            reference='synthetic-tool-result')
        review = snapshot.review_record(self.plan, self.digest,
            marker_sha256=sha((self.root / snapshot.MARKER).read_bytes()), receipt=result,
            tool_result=tool, engineering='pass', security='pass', reviewed_at=self.utc)
        self.tool_path = Path(self.temp.name) / 'tool-result.json'
        self.tool_path.write_bytes(canonical(tool) + b'\n')
        self.tool_path.chmod(0o600)
        self.args.tool_result = str(self.tool_path)
        self.write(snapshot.REVIEW, review)
        return result

    def test_exact_bytes_durable_pair_and_distinct_closed_protocol(self):
        receipt = self.success()
        self.assertEqual((self.root / snapshot.PAYLOAD).read_bytes(), BODY)
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.PAYLOAD, snapshot.RECEIPT})
        self.assertEqual(self.roles, ['token', 'registry', 'destination'])
        snapshot.checked_receipt(receipt, self.plan, self.digest,
                                 sha((self.root / snapshot.MARKER).read_bytes()))
        self.assertTrue(all(value is False for value in receipt['authority'].values()))
        for path in self.root.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        for private in ('SYNTHETIC_CANARY', old.TOKEN, old.LOCATION, 'rootfs', 'x-unknown'):
            self.assertNotIn(private.encode(), canonical(receipt))
        with self.assertRaises(Refused):
            acquisition.checked_manifest(self.plan, self.digest)
        with self.assertRaises(Refused):
            self.execute()
        self.assertEqual(len(self.roles), 3)

    def test_bad_digest_cannot_publish_payload_without_success_seam(self):
        with self.assertRaises(snapshot.SnapshotFailure) as caught:
            self.execute()
        self.assertEqual(caught.exception.code, 'digest')
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.RECEIPT})
        self.assertEqual(self.read(snapshot.RECEIPT)['failure'], 'digest')

    def test_inert_parser_preserves_missing_null_unknown_and_types(self):
        parsed = snapshot.inspect_fields(BODY)
        self.assertEqual(parsed, VALUE)
        self.assertNotIn('User', parsed['config'])
        self.assertIsNone(parsed['config']['Cmd'])
        self.assertEqual(parsed['config']['Env'], ['SYNTHETIC_CANARY=private'])

    def test_valid_gate_then_private_report_then_exact_cleanup(self):
        receipt = self.gate()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            result = snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.assertEqual(result['outcome'], 'private-field-report-written')
            report = self.read(snapshot.REPORT)
            self.assertEqual(report['fields'], VALUE)
            self.assertEqual(report['expires_at'], self.plan['expires_at'])
            self.args.expected_payload = canonical(receipt['snapshot']).decode()
            self.args.expected_report = canonical(result['report']).decode()
            self.utc = self.plan['expires_at'] + 1
            outcome = snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual(outcome['outcome'], 'owned-retained-data-absent')
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.RECEIPT,
                                       snapshot.REVIEW, snapshot.CLEANUP})

    def test_complete_pair_without_separate_review_cannot_be_inspected(self):
        self.success()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertNotIn(snapshot.REPORT, self.names())

    def test_lock_contention_refuses_before_gate_and_releases_after_failure(self):
        fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
            self.assertEqual(caught.exception.code, 'binding')
            self.assertEqual(self.names(), {snapshot.MANIFEST})
            self.assertEqual(self.roles, [])
        finally:
            os.close(fd)
        self.success()

    def test_initial_marker_fstat_failure_closes_fd_and_preserves_spent_marker(self):
        budget = snapshot.Budget(5, clock=lambda: self.now, utc=lambda: self.utc, manifest=self.plan)
        with snapshot.Store(self.plan, budget) as store:
            real_fstat, real_open = os.fstat, os.open
            opened = []
            def record_open(path, *args, **kwargs):
                fd = real_open(path, *args, **kwargs)
                if path == snapshot.MARKER:
                    opened.append(fd)
                return fd
            def fail_leaf(fd):
                if opened and fd == opened[0]:
                    raise OSError('SYNTHETIC_FSTAT_FAILURE')
                return real_fstat(fd)
            with patch.object(os, 'open', side_effect=record_open), patch.object(os, 'fstat', side_effect=fail_leaf):
                with self.assertRaises(OSError):
                    store.write(snapshot.MARKER, b'{}\n')
            self.assertEqual(len(opened), 1)
            with self.assertRaises(OSError):
                real_fstat(opened[0])
            self.assertIsNone(store.created[snapshot.MARKER])
            self.assertTrue((self.root / snapshot.MARKER).exists())

    def test_outer_deadline_after_spent_operation_keeps_spent_classification(self):
        calls = iter((self.now, self.now + 2))
        @snapshot.locked_action(1)
        def completed(args, *, clock, utc):
            args._snapshot_spent = True
        with self.assertRaises(snapshot.SnapshotFailure) as caught:
            completed(self.args, clock=lambda: next(calls), utc=lambda: self.utc)
        self.assertEqual((caught.exception.code, caught.exception.stage), ('deadline', 'spent'))

    def test_outer_descriptor_close_failure_after_spent_operation_is_spent(self):
        locked = []
        @snapshot.locked_action(10)
        def completed(args, *, clock, utc):
            args._snapshot_spent = True
            locked.append(args._snapshot_directory_fd)
        real_close = os.close
        def close_then_fail(fd):
            real_close(fd)
            if locked and fd == locked[0]:
                raise OSError('SYNTHETIC_CLOSE_FAILURE')
        with patch.object(os, 'close', side_effect=close_then_fail), \
                self.assertRaises(snapshot.SnapshotFailure) as caught:
            completed(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual((caught.exception.code, caught.exception.stage), ('cleanup', 'spent'))

    def test_expiry_before_marker_and_independent_monotonic_deadline(self):
        self.utc = 101000
        with self.assertRaises(snapshot.SnapshotFailure) as caught:
            self.execute()
        self.assertEqual(caught.exception.code, 'expiry')
        self.assertEqual(self.names(), {snapshot.MANIFEST})
        self.assertEqual(self.roles, [])

    def test_payload_write_fault_removes_owned_partial_but_keeps_spent_marker(self):
        real_write = os.write
        reached = []
        def failure(fd, data):
            if Path(f'/proc/self/fd/{fd}').readlink().name == snapshot.PAYLOAD:
                reached.append(True)
                raise OSError(errno.ENOSPC, 'SYNTHETIC_CANARY')
            return real_write(fd, data)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(os, 'write', side_effect=failure):
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
        self.assertEqual(caught.exception.code, 'payload_output')
        self.assertTrue(reached)
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.RECEIPT})

    def test_unknown_leaf_preserved_and_prevents_consumption(self):
        self.write('foreign', {'canary': 'private'})
        with self.assertRaises(snapshot.SnapshotFailure):
            self.execute()
        self.assertEqual(self.names(), {snapshot.MANIFEST, 'foreign'})
        self.assertEqual(self.roles, [])

    def test_report_write_failure_removes_owned_partial_report(self):
        self.gate()
        real_write = os.write
        reached = []
        def fail_report(fd, raw):
            if Path(f'/proc/self/fd/{fd}').readlink().name == snapshot.REPORT:
                reached.append(True)
                raise OSError('SYNTHETIC_CANARY')
            return real_write(fd, raw)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(os, 'write', side_effect=fail_report):
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertTrue(reached)
        self.assertNotIn(snapshot.REPORT, self.names())
        self.assertEqual((self.root / snapshot.PAYLOAD).read_bytes(), BODY)

    def test_signal_handler_restore_failure_rolls_back_payload_preserving_receipt(self):
        real_signal = signal.signal
        reached = []
        def restoring(sig, handler):
            if handler == signal.getsignal(sig):
                return real_signal(sig, handler)
            if sig == signal.SIGTERM and len(reached) == 2:
                reached.append('restore')
                real_signal(sig, handler)
                raise OSError('SYNTHETIC_CANARY')
            reached.append(sig)
            return real_signal(sig, handler)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(signal, 'signal', side_effect=restoring):
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
        self.assertIn('restore', reached)
        self.assertEqual(caught.exception.code, 'cleanup')
        self.assertNotIn(snapshot.PAYLOAD, self.names())
        self.assertEqual(self.read(snapshot.RECEIPT)['status'], 'complete')

    def test_cleanup_foreign_report_refuses_before_removing_valid_payload(self):
        receipt = self.gate()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            report = snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.args.expected_payload = canonical(receipt['snapshot']).decode()
            changed = copy.deepcopy(report['report'])
            changed['inode'] += 1
            self.args.expected_report = canonical(changed).decode()
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertIn(snapshot.PAYLOAD, self.names())
        self.assertIn(snapshot.REPORT, self.names())

    def test_historical_manifest_cannot_drop_executing_dependency(self):
        value = copy.deepcopy(self.plan)
        dependencies = value['acquisition_plan']['context']['bindings']['dependency_sha256']
        dependencies.pop('registry_metadata.py', None)
        with self.assertRaises(snapshot.SnapshotFailure):
            snapshot.checked_manifest(value, sha(canonical(value)))

    def test_inspection_refuses_rehashed_gate_changes_on_otherwise_valid_pairs(self):
        changes = [lambda r: r.update(execution_exit=1), lambda r: r.update(engineering='pending'),
            lambda r: r.update(security='fail'), lambda r: r.update(receipt_sha256='0' * 64),
            lambda r: r.update(execution_record_sha256='0' * 64),
            lambda r: r.update(command_sha256='0' * 64), lambda r: r.update(reviewed_at=101000),
            lambda r: r.update(state='unknown'), lambda r: r.update(extra='private')]
        self.gate()
        original = self.read(snapshot.REVIEW)
        for change in changes:
            value = copy.deepcopy(original)
            change(value)
            value = snapshot.sealed({k: v for k, v in value.items() if k != 'self_sha256'})
            self.write(snapshot.REVIEW, value)
            with self.subTest(change=change), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                with self.assertRaises(snapshot.SnapshotFailure):
                    snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
                self.assertNotIn(snapshot.REPORT, self.names())
        self.write(snapshot.REVIEW, original)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)

    def test_review_boolean_integer_equality_cannot_bypass_seal(self):
        self.gate()
        value = self.read(snapshot.REVIEW)
        value['execution_exit'] = False
        self.write(snapshot.REVIEW, value)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                self.assertRaises(snapshot.SnapshotFailure):
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertNotIn(snapshot.REPORT, self.names())

    def test_tool_result_unknown_nonzero_mismatch_and_staleness_refuse(self):
        self.gate()
        original = json.loads(self.tool_path.read_bytes())
        original_review = self.read(snapshot.REVIEW)
        changes = [(lambda r: r.update(exit_code=1), False), (lambda r: r.update(exit_code=None), False),
            (lambda r: r.update(command_sha256='0' * 64), True), (lambda r: r.update(stdout_sha256='0' * 64), False),
            (lambda r: r.update(stderr_sha256='0' * 64), False), (lambda r: r.update(reference=''), False),
            (lambda r: r.update(extra='private'), False)]
        for change, command_binding in changes:
            value = copy.deepcopy(original)
            change(value)
            value = snapshot.sealed({k: v for k, v in value.items() if k != 'self_sha256'})
            self.tool_path.write_bytes(canonical(value) + b'\n')
            with self.subTest(change=change), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                review = copy.deepcopy(original_review)
                review['execution_record_sha256'] = sha(canonical(value) + b'\n')
                if command_binding:
                    review['command_sha256'] = value['command_sha256']
                self.write(snapshot.REVIEW, snapshot.sealed({k: v for k, v in review.items() if k != 'self_sha256'}))
                with self.assertRaises(snapshot.SnapshotFailure):
                    snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
                self.assertNotIn(snapshot.REPORT, self.names())
        # Preserve a separate stale binding case after semantic negatives.
        self.tool_path.write_bytes(canonical(original) + b'\n')
        stale = copy.deepcopy(original)
        stale['reference'] = 'synthetic-other-reference'
        stale = snapshot.sealed({k: v for k, v in stale.items() if k != 'self_sha256'})
        self.tool_path.write_bytes(canonical(stale) + b'\n')
        self.write(snapshot.REVIEW, original_review)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                self.assertRaises(snapshot.SnapshotFailure):
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.tool_path.write_bytes(canonical(original) + b'\n')
        self.write(snapshot.REVIEW, original_review)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        (self.root / snapshot.REPORT).unlink()
        self.utc = self.plan['expires_at']
        with self.assertRaises(snapshot.SnapshotFailure) as caught:
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual(caught.exception.code, 'expiry')
        self.assertNotIn(snapshot.REPORT, self.names())

    def test_read_only_joint_verification_never_self_issues_review(self):
        self.gate()
        (self.root / snapshot.REVIEW).unlink()
        before = {path.name: path.read_bytes() for path in self.root.iterdir()}
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            result = snapshot.verify_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual(result['outcome'], 'joint-local-consistency-only')
        self.assertEqual(before, {path.name: path.read_bytes() for path in self.root.iterdir()})

    def test_private_file_symlink_hardlink_mode_fifo_and_directory_replacement(self):
        for kind in ('symlink', 'hardlink', 'mode', 'fifo', 'directory'):
            self.setUp()
            self.gate()
            payload = self.root / snapshot.PAYLOAD
            if kind == 'symlink':
                payload.rename(self.root.parent / 'retained-private')
                payload.symlink_to(self.root.parent / 'retained-private')
            elif kind == 'hardlink':
                os.link(payload, self.root.parent / 'linked-private')
            elif kind == 'mode':
                payload.chmod(0o640)
            elif kind == 'fifo':
                payload.unlink()
                os.mkfifo(payload)
            else:
                self.root.rename(self.root.parent / 'old-action')
                self.root.mkdir(mode=0o700)
                self.write(snapshot.MANIFEST, self.plan)
            with self.subTest(kind=kind), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                with self.assertRaises(snapshot.SnapshotFailure):
                    snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
                self.assertNotIn(snapshot.REPORT, self.names())

    def test_symlink_in_any_parent_component_refuses_before_transport(self):
        original = self.root
        alias = self.root.parent / 'alias'
        alias.symlink_to(original, target_is_directory=True)
        self.plan['acquisition_plan']['context']['output_directory'] = str(alias)
        self.digest = sha(canonical(self.plan))
        self.write(snapshot.MANIFEST, self.plan)
        self.args.manifest, self.args.manifest_sha256 = str(alias / snapshot.MANIFEST), self.digest
        with self.assertRaises(snapshot.SnapshotFailure):
            self.execute()
        self.assertEqual(self.roles, [])
        self.assertEqual(self.names(), {snapshot.MANIFEST})

    def test_zero_short_writes_and_receipt_failure_are_leaf_specific(self):
        for kind in ('zero', 'short', 'receipt'):
            self.setUp()
            real = os.write
            reached = []
            def inject(fd, data):
                leaf = Path(f'/proc/self/fd/{fd}').readlink().name
                if leaf == (snapshot.RECEIPT if kind == 'receipt' else snapshot.PAYLOAD):
                    reached.append(leaf)
                    if kind == 'zero':
                        return 0
                    if kind == 'receipt':
                        raise OSError('SYNTHETIC_CANARY')
                    return real(fd, data[:11])
                return real(fd, data)
            with self.subTest(kind=kind), patch.object(os, 'write', side_effect=inject), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                if kind == 'short':
                    self.execute()
                    self.assertEqual((self.root / snapshot.PAYLOAD).read_bytes(), BODY)
                else:
                    with self.assertRaises(snapshot.SnapshotFailure) as caught:
                        self.execute()
                    self.assertEqual(caught.exception.code, 'receipt_output' if kind == 'receipt' else 'payload_output')
                    self.assertNotIn(snapshot.PAYLOAD, self.names())
                    if kind == 'receipt':
                        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER})
                self.assertTrue(reached)

    def test_fsync_failure_after_payload_write_and_close_failure_do_not_succeed(self):
        for kind in ('fsync', 'close'):
            self.setUp()
            real = getattr(os, kind)
            reached = []
            def inject(fd):
                leaf = Path(f'/proc/self/fd/{fd}').readlink().name
                if leaf == snapshot.PAYLOAD and not reached:
                    reached.append(True)
                    if kind == 'close':
                        real(fd)
                    raise OSError('SYNTHETIC_CANARY')
                return real(fd)
            with self.subTest(kind=kind), patch.object(os, kind, side_effect=inject), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                with self.assertRaises(snapshot.SnapshotFailure) as caught:
                    self.execute()
                self.assertEqual(caught.exception.code, 'payload_output')
                self.assertTrue(reached)
                self.assertNotIn(snapshot.PAYLOAD, self.names())
                self.assertIn(snapshot.MARKER, self.names())

    def test_handled_interruption_is_spent_and_restores_handlers(self):
        before = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT)}
        respond = self.respond
        def interrupt(role, **kwargs):
            response = respond(role, **kwargs)
            if role == 'destination':
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
            return response
        self.transport.request.side_effect = interrupt
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            with self.assertRaises(snapshot.SnapshotFailure):
                self.execute()
        self.assertIn(snapshot.MARKER, self.names())
        self.assertNotIn(snapshot.PAYLOAD, self.names())
        self.assertEqual(before, {sig: signal.getsignal(sig) for sig in before})

    def test_pure_parser_strict_schema_and_numeric_bounds(self):
        invalid = [b'{"os":"linux","os":"linux"}', b'\xff', b'[]', b'{"x":NaN}',
                   b'[' * 33 + b'0' + b']' * 33]
        for change in (lambda v: v.update(os='windows'), lambda v: v.update(architecture='arm64'),
                       lambda v: v['config'].update(Env=1), lambda v: v['config'].update(Memory=1.5),
                       lambda v: v['rootfs'].update(diff_ids=[])):
            value = copy.deepcopy(VALUE)
            change(value)
            invalid.append(canonical(value))
        for raw in invalid:
            with self.subTest(raw=raw[:20]), self.assertRaises(snapshot.SnapshotFailure):
                snapshot.inspect_fields(raw)

    def test_monotonic_inspection_and_cleanup_budgets_are_independent_of_utc(self):
        for seconds in (5, 10):
            now = [10.]
            budget = snapshot.Budget(seconds, clock=lambda: now[0], utc=lambda: self.utc,
                                     manifest=self.plan, expiry=seconds != 10)
            now[0] += seconds - .001
            budget.check()
            now[0] = 10. + seconds
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                budget.check()
            self.assertEqual(caught.exception.code, 'deadline')
        self.assertEqual(snapshot.BUDGETS, {'acquisition': 60, 'request': 10, 'execution_outer': 90,
            'inspect': 5, 'cleanup': 10, 'local_outer': 15, 'kill_grace': 5,
            'retention': 259200, 'report_bytes': 32768, 'artifact_leaves': 7})
        for verb, limit in (('execute', '90'), ('inspect', '15'), ('cleanup', '15')):
            command = snapshot.action_command(self.plan, self.digest, verb)
            self.assertEqual(command[:9], ['/usr/bin/env', '-i', 'PATH=/usr/bin:/bin', 'LC_ALL=C',
                                          '/usr/bin/timeout', '-k', '5', limit, self.plan['acquisition_plan']['runtime']['interpreter']])

    def test_sanitized_cli_failure_does_not_print_config_or_underlying_error(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(snapshot.sys, 'argv', ['snapshot', 'execute', '--manifest', self.args.manifest,
                '--manifest-sha256', self.digest, '--runner-sha256', self.args.runner_sha256]), \
                patch.dict(os.environ, {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}, clear=True), \
                patch.object(snapshot, 'execute_action', side_effect=OSError('SYNTHETIC_CANARY')), \
                redirect_stdout(stdout), redirect_stderr(stderr), self.assertRaises(SystemExit):
            snapshot.main()
        self.assertEqual(stdout.getvalue(), '')
        self.assertEqual(stderr.getvalue(), snapshot.ERROR + '; stage=preconsume; failure=binding\n')

    def test_owned_partial_orphan_cleanup_after_expiry_without_replay(self):
        self.write(snapshot.MARKER, {'manifest_sha256': self.digest})
        partial = b'SYNTHETIC-CANARY-partial'
        payload = self.root / snapshot.PAYLOAD
        payload.write_bytes(partial)
        payload.chmod(0o600)
        expected = snapshot.identity(payload.stat(), partial, payload=True)
        expected['durably_verified'] = False
        self.args.expected_payload = canonical(expected).decode()
        self.args.expected_report = None
        self.utc = self.plan['expires_at'] + 1
        result = snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual(result['outcome'], 'owned-retained-data-absent')
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.CLEANUP})
        with self.assertRaises(snapshot.SnapshotFailure):
            self.execute()
        self.assertEqual(self.roles, [])

    def test_historical_inspector_uses_committed_closure_after_docs_head_and_ca_drift(self):
        context = self.plan['acquisition_plan']['context']
        source_calls = []
        def historical(_repo, *arguments):
            self.assertEqual(arguments[-2], 'show')
            source, relative = arguments[-1].split(':', 1)
            self.assertEqual(source, context['source_sha'])
            source_calls.append(relative)
            return Path(snapshot.__file__).with_name(Path(relative).name).read_bytes()
        with patch.object(metadata_source := snapshot.metadata.base, 'git', side_effect=historical), \
                patch.object(metadata_source, '_source', side_effect=AssertionError('HEAD must not gate inert history')), \
                patch.object(snapshot.metadata, '_source_inputs', side_effect=AssertionError('Ambient CA must not gate inert history')):
            REAL_VERIFY_SOURCE(self.plan, self.args, historical=True)
        self.assertEqual(len(source_calls), len(snapshot.FULL_DEPENDENCIES))
        with patch.object(snapshot.metadata.base, 'git', return_value=b'changed inspector'):
            with self.assertRaises(snapshot.SnapshotFailure):
                REAL_VERIFY_SOURCE(self.plan, self.args, historical=True)

    def test_cleanup_current_implementation_closure_ignores_historical_head_ca_and_expiry(self):
        current = {name: sha(Path(snapshot.__file__).with_name(name).read_bytes()) for name in snapshot.FULL_DEPENDENCIES}
        self.args.cleanup_source_sha = 'f' * 40
        self.args.cleanup_closure_sha256 = sha(canonical(current))
        self.utc = self.plan['expires_at'] + 1
        def current_source(_repo, *arguments):
            self.assertTrue(arguments[-1].startswith(self.args.cleanup_source_sha + ':'))
            return Path(snapshot.__file__).with_name(Path(arguments[-1].split(':', 1)[1]).name).read_bytes()
        with patch.object(snapshot.metadata.base, '_source') as source, \
                patch.object(snapshot.metadata.base, 'git', side_effect=current_source), \
                patch.object(snapshot.metadata, '_source_inputs', side_effect=AssertionError('historical CA must not gate cleanup')):
            REAL_VERIFY_SOURCE(self.plan, self.args, cleanup=True)
            source.assert_called_once_with('/fixture/repo', self.args.cleanup_source_sha)
            self.args.cleanup_closure_sha256 = '0' * 64
            with self.assertRaises(snapshot.SnapshotFailure):
                REAL_VERIFY_SOURCE(self.plan, self.args, cleanup=True)

    def test_fresh_source_binding_matrix_has_a_valid_control_and_each_drift(self):
        manifest = copy.deepcopy(self.plan)
        plan = manifest['acquisition_plan']
        context = plan['context']
        raw = b'{"synthetic":"source-contract"}'
        context['bindings']['contract_sha256'] = sha(raw)
        contract = {'pairing_sha256': context['pairing_sha256'], 'operational_sha256': context['operational_sha256'],
                    'browser': {'expires_at': manifest['browser_contract_expiry']}}
        inputs = {'local_files': {}, 'retained_manifest_path': context['bindings']['retained_manifest_path'],
            'total_timeout': 60, 'attempt': context['attempt'], 'image_refs': context['image_refs'],
            'retained_manifest_sha256': context['retained_manifest_sha256']}
        source = (contract, raw, inputs, context['bindings']['image_inputs_sha256'], plan['retained_image'], b'CA')
        changes = [lambda p, s: p['acquisition_plan']['runtime'].update(python=[0, 0, 0]),
            lambda p, s: p['acquisition_plan'].update(schema_reference_closure='0' * 64),
            lambda p, s: p['acquisition_plan']['context']['bindings'].update(contract_sha256='0' * 64),
            lambda p, s: s[0].update(pairing_sha256='0' * 64),
            lambda p, s: s[0].update(operational_sha256='0' * 64),
            lambda p, s: s[0]['browser'].update(expires_at=199999),
            lambda p, s: s[2].update(local_files={'wrong': '0' * 64}),
            lambda p, s: s[2].update(attempt='wrong'),
            lambda p, s: s[2].update(total_timeout=59)]
        for change in (None, *changes):
            value, supplied = copy.deepcopy(manifest), copy.deepcopy(source)
            if change:
                change(value, supplied)
            with self.subTest(change=change), patch.object(snapshot.metadata, '_source_inputs', return_value=supplied), \
                    patch.object(snapshot, '_dependencies', return_value=context['bindings']['dependency_sha256']), \
                    patch.object(snapshot.metadata.base, '_read', return_value=b'platform'), \
                    patch.object(acquisition, '_platform', return_value={k: v for k, v in plan['platform_evidence'].items() if k != 'path'}):
                if change:
                    with self.assertRaises((Refused, snapshot.SnapshotFailure)):
                        REAL_VERIFY_SOURCE(value, self.args)
                else:
                    self.assertEqual(REAL_VERIFY_SOURCE(value, self.args), b'CA')

    def test_all_cooperating_entrypoints_lock_before_first_manifest_read(self):
        fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for function in (snapshot.execute_action, snapshot.verify_action, snapshot.inspect_action,
                             snapshot.cleanup_action):
                with self.subTest(function=function.__name__), patch.object(snapshot, '_load') as load:
                    with self.assertRaises(snapshot.SnapshotFailure):
                        function(self.args, clock=lambda: self.now, utc=lambda: self.utc)
                    load.assert_not_called()
        finally:
            os.close(fd)

    def test_cleanup_preserves_markers_and_refuses_hardlinked_other_evidence(self):
        receipt = self.success()
        os.link(self.root / snapshot.RECEIPT, self.root.parent / 'linked-receipt')
        self.args.expected_payload = canonical(receipt['snapshot']).decode()
        self.args.expected_report = None
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertIn(snapshot.PAYLOAD, self.names())
        self.assertIn(snapshot.MARKER, self.names())

    def test_marker_partial_write_is_spent_and_never_sent_or_removed(self):
        real_write = os.write
        reached = []
        def fail_marker(fd, raw):
            if Path(f'/proc/self/fd/{fd}').readlink().name == snapshot.MARKER:
                reached.append(True)
                raise OSError('SYNTHETIC_CANARY')
            return real_write(fd, raw)
        with patch.object(os, 'write', side_effect=fail_marker):
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
        self.assertTrue(reached)
        self.assertEqual(caught.exception.stage, 'spent')
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER})
        self.assertEqual(self.roles, [])

    def test_partial_cleanup_is_durable_and_recovery_uses_fresh_separate_directory(self):
        receipt = self.gate()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            report = snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.args.expected_payload = canonical(receipt['snapshot']).decode()
            self.args.expected_report = canonical(report['report']).decode()
            original = os.unlink
            reached = []
            def fail_report(leaf, **kwargs):
                if leaf == snapshot.REPORT:
                    reached.append(True)
                    raise OSError('SYNTHETIC_CANARY')
                return original(leaf, **kwargs)
            with patch.object(os, 'unlink', side_effect=fail_report), self.assertRaises(snapshot.SnapshotFailure):
                snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.assertTrue(reached)
            self.assertNotIn(snapshot.PAYLOAD, self.names())
            self.assertIn(snapshot.REPORT, self.names())
            first = (self.root / snapshot.CLEANUP).read_bytes()
            self.assertEqual(json.loads(first)['outcome'], 'cleanup-incomplete')
            self.args.recovery_directory = str(Path(self.temp.name) / 'fresh-recovery')
            result = snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual(result['outcome'], 'owned-retained-data-absent')
        self.assertEqual((self.root / snapshot.CLEANUP).read_bytes(), first)
        self.assertNotIn(snapshot.REPORT, self.names())
        recovery = Path(self.args.recovery_directory)
        self.assertEqual(recovery.stat().st_mode & 0o777, 0o700)
        self.assertEqual({path.name for path in recovery.iterdir()}, {snapshot.CLEANUP})
        self.assertEqual((recovery / snapshot.CLEANUP).stat().st_mode & 0o777, 0o600)

    def test_killed_synthetic_coordinator_orphan_is_reaped_classified_and_not_replayed(self):
        ready_read, ready_write = os.pipe()
        hold_read, hold_write = os.pipe()
        original_publish = snapshot.Store.publish
        def pause_after_payload(store, leaf, raw, code):
            result = original_publish(store, leaf, raw, code)
            if leaf == snapshot.PAYLOAD:
                os.write(ready_write, b'ready')
                os.read(hold_read, 1)
            return result
        pid = os.fork()
        if pid == 0:
            try:
                os.close(ready_read)
                os.close(hold_write)
                with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                        patch.object(snapshot.Store, 'publish', new=pause_after_payload):
                    self.execute()
            finally:
                os._exit(97)
        reaped = False
        try:
            os.close(ready_write)
            os.close(hold_read)
            self.assertEqual(select.select([ready_read], [], [], 3.)[0], [ready_read])
            self.assertEqual(os.read(ready_read, 5), b'ready')
            # This fixture owns the unreaped PID; no ancestor/group/host census.
            os.kill(pid, signal.SIGKILL)
            done, status = os.waitpid(pid, 0)
            reaped = True
            self.assertEqual(done, pid)
            self.assertEqual(os.waitstatus_to_exitcode(status), -signal.SIGKILL)
            self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.PAYLOAD})
            classification = snapshot.verify_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.assertEqual(classification['outcome'], 'recovery-incomplete')
            self.assertFalse(classification['evidence_accepted'])
            with self.assertRaises(snapshot.SnapshotFailure):
                self.execute()
            self.assertEqual(self.roles, [])
            observed = snapshot.identity((self.root / snapshot.PAYLOAD).stat(), BODY, payload=True)
            observed['sha256'] = acquisition.CONFIG_DIGEST[7:]
            observed['durably_verified'] = False
            self.args.expected_payload, self.args.expected_report = canonical(observed).decode(), None
            with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.assertNotIn(snapshot.PAYLOAD, self.names())
            self.assertIn(snapshot.MARKER, self.names())
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(ready_read)
            os.close(hold_write)

    def test_report_serialized_size_limit_never_truncates(self):
        self.gate()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(snapshot, 'inspect_fields', return_value={'extension': 'x' * 32769}):
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertNotIn(snapshot.REPORT, self.names())

    def test_report_rollback_failure_is_reported_as_cleanup_and_preserves_owned_leaf(self):
        self.gate()
        real_write = snapshot.Store.write
        def publish_then_fail(store, name, raw):
            result = real_write(store, name, raw)
            if name == snapshot.REPORT:
                raise OSError('SYNTHETIC_REPORT_PUBLISH_FAILURE')
            return result
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(snapshot.Store, 'write', new=publish_then_fail), \
                patch.object(snapshot.Store, 'remove_created', side_effect=OSError('SYNTHETIC_ROLLBACK_FAILURE')), \
                self.assertRaises(snapshot.SnapshotFailure) as caught:
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual((caught.exception.code, caught.exception.stage), ('cleanup', 'inspection'))
        self.assertIn(snapshot.REPORT, self.names())

    def test_unidentified_report_creation_is_preserved_and_reported_as_cleanup(self):
        self.gate()
        real_fstat = os.fstat
        opened = []
        def fail_report(fd):
            try:
                name = Path(f'/proc/self/fd/{fd}').readlink().name
            except OSError:
                name = ''
            if name == snapshot.REPORT:
                opened.append(fd)
                raise OSError('SYNTHETIC_REPORT_FSTAT_FAILURE')
            return real_fstat(fd)
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                patch.object(os, 'fstat', side_effect=fail_report), \
                self.assertRaises(snapshot.SnapshotFailure) as caught:
            snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertEqual((caught.exception.code, caught.exception.stage), ('cleanup', 'inspection'))
        self.assertTrue(opened)
        with self.assertRaises(OSError):
            real_fstat(opened[-1])
        self.assertIn(snapshot.REPORT, self.names())

    def test_receipt_and_payload_corruption_each_refuse_a_previously_valid_pair(self):
        for kind in ('payload', 'receipt', 'authority'):
            self.setUp()
            self.gate()
            if kind == 'payload':
                (self.root / snapshot.PAYLOAD).write_bytes(BODY[:-1] + b'!')
            else:
                value = self.read(snapshot.RECEIPT)
                if kind == 'receipt':
                    value['snapshot']['inode'] += 1
                else:
                    value['authority']['qualified'] = True
                self.write(snapshot.RECEIPT, snapshot.sealed({k: v for k, v in value.items() if k != 'self_sha256'}))
            with self.subTest(kind=kind), patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                with self.assertRaises(snapshot.SnapshotFailure):
                    snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            self.assertNotIn(snapshot.REPORT, self.names())

    def test_census_reads_at_most_eight_entries_and_never_recursively_removes(self):
        for leaf in snapshot.LEAVES[1:]:
            self.write(leaf, {})
        self.write('eighth-foreign', {})
        budget = snapshot.Budget(5, clock=lambda: self.now, utc=lambda: self.utc, manifest=self.plan)
        with snapshot.Store(self.plan, budget) as store:
            with self.assertRaises(snapshot.SnapshotFailure):
                store.census()
        self.assertEqual(len(self.names()), 8)

    def test_prepare_file_only_exclusive_manifest_and_no_marker(self):
        plan = self.plan['acquisition_plan']
        context, bindings = plan['context'], plan['context']['bindings']
        raw = b'{"synthetic":"prepare-contract"}'
        contract = {'pairing_sha256': context['pairing_sha256'], 'operational_sha256': context['operational_sha256'],
                    'browser': {'expires_at': self.plan['browser_contract_expiry']}}
        inputs = {'retained_manifest_sha256': context['retained_manifest_sha256'], 'image_refs': context['image_refs'],
            'attempt': context['attempt'], 'total_timeout': 60, 'retained_manifest_path': bindings['retained_manifest_path'],
            'local_files': {}}
        directory = str(self.root.parent / 'prepared')
        args = Namespace(repo=bindings['repo'], source_sha=context['source_sha'], contract=bindings['contract_path'],
            image_inputs=bindings['image_inputs_path'], ca_file=context['ca_file'], ca_sha256=context['ca_sha256'],
            platform_file=plan['platform_evidence']['path'], directory=directory, expires_at=101000)
        source = (contract, raw, inputs, bindings['image_inputs_sha256'], plan['retained_image'], b'CA')
        with patch.object(snapshot.metadata, '_source_inputs', return_value=source), \
                patch.object(snapshot, '_dependencies', return_value=bindings['dependency_sha256']), \
                patch.object(snapshot.metadata.base, '_read', return_value=b'synthetic-platform'), \
                patch.object(acquisition, '_platform', return_value={k: v for k, v in plan['platform_evidence'].items() if k != 'path'}):
            digest = snapshot.prepare_action(args, utc=lambda: 100000)
            prepared = Path(directory)
            self.assertEqual({path.name for path in prepared.iterdir()}, {snapshot.MANIFEST})
            self.assertEqual(prepared.stat().st_mode & 0o777, 0o700)
            value = json.loads((prepared / snapshot.MANIFEST).read_bytes())
            snapshot.checked_manifest(value, digest)
            with self.assertRaises(FileExistsError):
                snapshot.prepare_action(args, utc=lambda: 100000)
            self.transport.request.assert_not_called()

    def test_locking_unavailable_refuses_without_reading_artifacts_or_sending(self):
        with patch.object(fcntl, 'flock', side_effect=OSError('SYNTHETIC_CANARY')), \
                patch.object(snapshot, '_load') as load:
            with self.assertRaises(snapshot.SnapshotFailure):
                self.execute()
        load.assert_not_called()
        self.assertEqual(self.roles, [])
        self.assertEqual(self.names(), {snapshot.MANIFEST})

    def test_output_substitution_before_verification_preserves_foreign_leaf(self):
        original_fsync = os.fsync
        reached = []
        saved = self.root.parent / 'original-owned'
        def replace(fd):
            original_fsync(fd)
            if Path(f'/proc/self/fd/{fd}').readlink().name == snapshot.PAYLOAD and not reached:
                reached.append(True)
                (self.root / snapshot.PAYLOAD).rename(saved)
                (self.root / snapshot.PAYLOAD).write_bytes(b'SYNTHETIC_CANARY-foreign')
                (self.root / snapshot.PAYLOAD).chmod(0o600)
        with patch.object(os, 'fsync', side_effect=replace), \
                patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
        self.assertTrue(reached)
        self.assertEqual(caught.exception.code, 'cleanup')
        self.assertEqual(saved.read_bytes(), BODY)
        self.assertEqual((self.root / snapshot.PAYLOAD).read_bytes(), b'SYNTHETIC_CANARY-foreign')
        self.assertEqual(self.names(), {snapshot.MANIFEST, snapshot.MARKER, snapshot.PAYLOAD})

    def test_valid_complete_receipt_remains_historical_when_final_binding_fails(self):
        reached = []
        def changed_source(*args, **kwargs):
            if (self.root / snapshot.RECEIPT).exists():
                reached.append(True)
                raise snapshot.SnapshotFailure('binding')
            return b'CA'
        with patch.object(snapshot, '_verify_source', side_effect=changed_source), \
                patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            with self.assertRaises(snapshot.SnapshotFailure) as caught:
                self.execute()
        self.assertEqual(caught.exception.code, 'binding')
        self.assertTrue(reached)
        self.assertEqual(self.read(snapshot.RECEIPT)['status'], 'complete')
        self.assertNotIn(snapshot.PAYLOAD, self.names())
        self.assertIn(snapshot.MARKER, self.names())

    def test_expiry_at_payload_and_receipt_boundary_never_reports_completion(self):
        original_write = snapshot.Store.write
        for leaf in (snapshot.PAYLOAD, snapshot.RECEIPT):
            self.setUp()
            reached = []
            def expire(store, name, raw):
                if name == leaf and not reached:
                    reached.append(True)
                    self.utc = self.plan['expires_at']
                return original_write(store, name, raw)
            with self.subTest(leaf=leaf), patch.object(snapshot.Store, 'write', new=expire), \
                    patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
                with self.assertRaises(snapshot.SnapshotFailure) as caught:
                    self.execute()
            self.assertTrue(reached)
            self.assertEqual(caught.exception.code, 'expiry')
            self.assertNotIn(snapshot.PAYLOAD, self.names())
            self.assertIn(snapshot.MARKER, self.names())

    def test_length_and_schema_refusal_never_retain_invalid_bytes(self):
        for kind in ('length', 'schema'):
            self.setUp()
            if kind == 'length':
                self.responses[2] = (200, b'{}')
                with self.assertRaises(snapshot.SnapshotFailure) as caught:
                    self.execute()
            else:
                with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam), \
                        patch.object(snapshot.config_schema, 'validate_config', side_effect=Refused('SYNTHETIC_CANARY')):
                    with self.assertRaises(snapshot.SnapshotFailure) as caught:
                        self.execute()
            self.assertEqual(caught.exception.code, 'body' if kind == 'length' else 'schema')
            self.assertEqual(self.read(snapshot.RECEIPT)['failure'], caught.exception.code)
            self.assertNotIn(snapshot.PAYLOAD, self.names())

    def test_cleanup_wrong_payload_refuses_before_removing_valid_report(self):
        receipt = self.gate()
        with patch.object(acquisition, '_config_sha256', side_effect=self.digest_seam):
            report = snapshot.inspect_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
            wrong = copy.deepcopy(receipt['snapshot'])
            wrong['inode'] += 1
            self.args.expected_payload = canonical(wrong).decode()
            self.args.expected_report = canonical(report['report']).decode()
            with self.assertRaises(snapshot.SnapshotFailure):
                snapshot.cleanup_action(self.args, clock=lambda: self.now, utc=lambda: self.utc)
        self.assertIn(snapshot.PAYLOAD, self.names())
        self.assertIn(snapshot.REPORT, self.names())

    def test_manifest_retention_bounds_and_reserved_leaf_schema_are_exact(self):
        for change in (lambda m: m.update(expires_at=True), lambda m: m.update(expires_at=100000),
                       lambda m: m.update(expires_at=400000), lambda m: m.update(browser_contract_expiry=100001),
                       lambda m: m['leaves'].append('unexpected'), lambda m: m['budgets'].update(inspect=6),
                       lambda m: m['acquisition_plan']['platform_evidence'].update(layer_count=2)):
            value = copy.deepcopy(self.plan)
            change(value)
            with self.subTest(change=change), self.assertRaises(snapshot.SnapshotFailure):
                snapshot.checked_manifest(value, sha(canonical(value)))


if __name__ == '__main__':
    unittest.main()

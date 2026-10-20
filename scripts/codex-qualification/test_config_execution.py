"""Real execute dispatch with synthetic private files and no network authority."""
from argparse import Namespace
from contextlib import ExitStack, contextmanager, redirect_stderr, redirect_stdout
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import traceback
import unittest
from unittest.mock import Mock, patch

import config_acquisition as acquisition
import test_config_acquisition as fixtures
from prepare import Refused, canonical, sha


CANARY = 'SYNTHETIC-EXECUTION-PRIVATE-CANARY'


class ConfigExecution(unittest.TestCase):
    @contextmanager
    def environment(self, *, before=None, after=None, failure=None, preflight_seconds=0,
                    durations=None, publication_failure=False, real_digest=False):
        """Keep _verify_inputs and descriptor-relative manifest reads real."""
        fixture = fixtures.ConfigAcquisition()
        fixture.setUp()
        plan, runner, source = fixture.source_inputs()
        source = copy.deepcopy(source)
        platform = {key: value for key, value in fixture.platform.items() if key != 'path'}
        self.fixture, self.source = fixture, source
        self.roles, self.deadlines, self.source_calls = [], [], 0
        self.now = 10.0
        with tempfile.TemporaryDirectory(prefix='synthetic-config-execute-') as directory:
            output = Path(directory) / 'out'
            output.mkdir(mode=0o700)
            info = output.stat()
            plan['context']['output_directory'] = str(output)
            plan['context']['output_directory_fingerprint'] = {
                'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid}
            self.output, self.plan = output, plan
            self.digest = sha(canonical(plan))
            manifest_path = output / acquisition.MANIFEST
            manifest_path.write_bytes(canonical(plan) + b'\n')
            manifest_path.chmod(0o600)
            self.args = Namespace(manifest=str(manifest_path), manifest_sha256=self.digest,
                                  runner_sha256=sha(runner))
            if before:
                before(source)
            original_read = acquisition.metadata.base._read
            original_write = acquisition.metadata.base._write_at

            def read(path, *args, **kwargs):
                if str(path) == str(Path(acquisition.__file__).absolute()):
                    return runner
                if str(path) == plan['platform_evidence']['path']:
                    return b'synthetic platform bytes'
                return original_read(path, *args, **kwargs)

            def source_inputs(_args):
                self.source_calls += 1
                if self.source_calls == 1:
                    self.now += preflight_seconds
                return source

            def write(descriptor, name, value):
                if publication_failure and name == acquisition.RECEIPT:
                    raise OSError(CANARY)
                return original_write(descriptor, name, value)

            def request(role, *, location=None, bearer=None, deadline, observe):
                self.assertTrue((output / acquisition.MARKER).exists(), 'send requires a spent marker')
                self.roles.append(role)
                self.deadlines.append(deadline)
                index = acquisition.ROLES.index(role)
                self.assertEqual(location, fixtures.LOCATION if index == 2 else None)
                self.assertEqual(bearer, fixtures.TOKEN if index == 1 else None)
                if failure and role == failure[0] and failure[1] in ('dns', 'peer', 'tls', 'headers', 'internal'):
                    code = failure[1]
                    if code != 'dns':
                        observe('peer_ok', code != 'peer')
                    if code in ('headers', 'internal'):
                        observe('tls_ok', True)
                        observe('send', None)
                    if code == 'internal':
                        raise RuntimeError(CANARY)
                    error = acquisition.https.TransportRefused(code)
                    error.add_note(CANARY)
                    raise error
                observe('peer_ok', True)
                observe('tls_ok', True)
                observe('send', None)
                if durations:
                    self.now += durations[index]
                status, payload = [(200, canonical({'token': fixtures.TOKEN})),
                                   (307, fixtures.LOCATION), (200, fixtures.BODY)][index]
                observe('http_status', status)
                if index == 2:
                    if failure and failure[1] == 'body':
                        payload = b'{"' + CANARY.encode() + b'":0}'
                    elif failure and failure[1] == 'schema':
                        payload = canonical({'synthetic': CANARY})
                        payload += b' ' * (2646 - len(payload))
                    observe('body_bytes', len(payload))
                if after:
                    after(role, source)
                return status, payload

            self.transport = Mock()
            self.transport.request.side_effect = request
            with ExitStack() as stack:
                stack.enter_context(patch.object(acquisition.metadata, '_source_inputs', side_effect=source_inputs))
                stack.enter_context(patch.object(acquisition, '_dependencies',
                    return_value=copy.deepcopy(plan['context']['bindings']['dependency_sha256'])))
                stack.enter_context(patch.object(acquisition, '_platform', return_value=platform))
                stack.enter_context(patch.object(acquisition.metadata.base, '_read', side_effect=read))
                stack.enter_context(patch.object(acquisition.metadata.base, '_write_at', side_effect=write))
                stack.enter_context(patch.object(acquisition.resource, 'setrlimit'))
                stack.enter_context(patch.object(acquisition.https, 'BoundedHTTPS', return_value=self.transport))
                if not real_digest:
                    stack.enter_context(patch.object(acquisition, '_config_sha256',
                        return_value=acquisition.CONFIG_DIGEST[7:]))
                yield

    def execute(self):
        return acquisition.execute_action(self.args, clock=lambda: self.now)

    def assert_private_result(self, *, failure=None, complete=False, receipt=True):
        names = {path.name for path in self.output.iterdir()}
        expected = {acquisition.MANIFEST, acquisition.MARKER}
        if receipt:
            expected.add(acquisition.RECEIPT)
        self.assertEqual(names, expected, 'Config must never be a persisted output')
        for path in self.output.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        if not receipt:
            return
        result = json.loads((self.output / acquisition.RECEIPT).read_bytes())
        marker = sha((self.output / acquisition.MARKER).read_bytes())
        acquisition.checked_receipt(result, self.plan, self.digest, marker)
        self.assertEqual(result['status'], 'complete' if complete else 'refused')
        self.assertEqual(result['failure'], failure)
        self.assertTrue(all(value is False for value in result['authority'].values()))
        data = canonical(result)
        for secret in (CANARY, fixtures.TOKEN, fixtures.LOCATION, 'SYNTHESIZED_SECRET',
                       'rootfs', 'diff_ids'):
            self.assertNotIn(secret.encode(), data)
        return result

    def refusal(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        caught = None
        with redirect_stdout(stdout), redirect_stderr(stderr):
            try:
                self.execute()
            except Exception as error:
                caught = error
                rendered = ''.join(traceback.format_exception(error))
        self.assertIsInstance(caught, Refused, 'execute must refuse')
        self.assertEqual(str(caught), acquisition.ERROR)
        self.assertNotIn(CANARY, rendered)
        self.assertEqual(stdout.getvalue(), '')
        self.assertEqual(stderr.getvalue(), '')

    def test_real_dispatch_success_checks_bindings_repeatedly_and_never_writes_config(self):
        with self.environment():
            self.execute()
            self.assertEqual(self.roles, ['token', 'registry', 'destination'])
            self.assertGreaterEqual(self.source_calls, 10)
            self.assert_private_result(complete=True)

    def test_binding_changed_before_gate_has_no_marker_or_transport(self):
        def change(source):
            source[0]['pairing_sha256'] = '0' * 64
        with self.environment(before=change):
            self.refusal()
            self.assertEqual({path.name for path in self.output.iterdir()}, {acquisition.MANIFEST})
            self.transport.request.assert_not_called()

    def test_binding_changed_after_token_is_spent_and_stops_registry(self):
        def change(role, source):
            if role == 'token':
                source[0]['pairing_sha256'] = '0' * 64
        with self.environment(after=change):
            self.refusal()
            self.assertEqual(self.roles, ['token'])
            self.assert_private_result(failure='binding')

    def test_execute_failure_matrix_persists_only_sanitized_spent_receipts(self):
        cases = [('token', 'dns'), ('token', 'peer'), ('token', 'tls'),
                 ('registry', 'headers'), ('destination', 'body'),
                 ('destination', 'digest'), ('destination', 'schema'), ('token', 'internal')]
        for role, code in cases:
            with self.subTest(code=code), self.environment(failure=(role, code), real_digest=code == 'digest'):
                self.refusal()
                self.assertEqual(self.roles, list(acquisition.ROLES[:acquisition.ROLES.index(role) + 1]))
                self.assert_private_result(failure=code)

    def test_main_failure_matrix_sanitizes_stdout_stderr_and_exceptions(self):
        for code in ('dns', 'peer', 'tls', 'headers', 'body', 'digest', 'schema', 'internal'):
            role = 'destination' if code in ('body', 'digest', 'schema') else 'token'
            with self.subTest(code=code), self.environment(failure=(role, code), real_digest=code == 'digest'):
                stdout, stderr = io.StringIO(), io.StringIO()
                real_execute = acquisition.execute_action
                argv = ['config_acquisition.py', 'execute', '--manifest', self.args.manifest,
                        '--manifest-sha256', self.args.manifest_sha256,
                        '--runner-sha256', self.args.runner_sha256]
                with patch.object(sys, 'argv', argv), \
                        patch.object(acquisition, 'execute_action',
                            side_effect=lambda args: real_execute(args, clock=lambda: self.now)), \
                        redirect_stdout(stdout), redirect_stderr(stderr), self.assertRaises(SystemExit) as caught:
                    acquisition.main()
                self.assertEqual(caught.exception.code, 1)
                self.assertEqual(stdout.getvalue(), '')
                self.assertEqual(stderr.getvalue(), acquisition.ERROR + '\n')
                self.assertEqual(self.roles, list(acquisition.ROLES[:acquisition.ROLES.index(role) + 1]))
                self.assert_private_result(failure=code)

    def test_publication_write_failure_keeps_spent_marker_without_success_receipt(self):
        with self.environment(publication_failure=True):
            self.refusal()
            self.assertEqual(self.roles, list(acquisition.ROLES))
            self.assert_private_result(receipt=False)

    def test_main_publication_failure_has_fixed_error_and_keeps_spent_marker(self):
        with self.environment(publication_failure=True):
            stdout, stderr = io.StringIO(), io.StringIO()
            real_execute = acquisition.execute_action
            argv = ['config_acquisition.py', 'execute', '--manifest', self.args.manifest,
                    '--manifest-sha256', self.args.manifest_sha256,
                    '--runner-sha256', self.args.runner_sha256]
            with patch.object(sys, 'argv', argv), \
                    patch.object(acquisition, 'execute_action',
                        side_effect=lambda args: real_execute(args, clock=lambda: self.now)), \
                    redirect_stdout(stdout), redirect_stderr(stderr), self.assertRaises(SystemExit) as caught:
                acquisition.main()
            self.assertEqual(caught.exception.code, 1)
            self.assertEqual(stdout.getvalue(), '')
            self.assertEqual(stderr.getvalue(), acquisition.ERROR + '\n')
            self.assertEqual(self.roles, list(acquisition.ROLES))
            self.assert_private_result(receipt=False)

    def test_real_execute_preflight_consumes_overall_budget_without_phase_reset(self):
        with self.environment(preflight_seconds=52, durations=[3, 3, 2.1]):
            self.refusal()
            self.assertEqual(self.roles, list(acquisition.ROLES))
            self.assertEqual(self.deadlines, [70.0, 70.0, 70.0])
            result = self.assert_private_result(failure='deadline')
            self.assertEqual(result['stage'], 'destination')
            self.assertIsNone(result['actions'][2]['http_status'])

    def test_real_execute_backward_clock_refuses_before_follow_on(self):
        def backward(role, _source):
            if role == 'token':
                self.now -= 1
        with self.environment(after=backward):
            self.refusal()
            self.assertEqual(self.roles, ['token'])
            self.assert_private_result(failure='deadline')

    def test_dispatch_mutations_have_pristine_controls_and_specific_assertion_failures(self):
        source = Path(acquisition.__file__).read_text()
        before_oracle = 'test_binding_changed_before_gate_has_no_marker_or_transport'
        after_oracle = 'test_binding_changed_after_token_is_spent_and_stops_registry'
        mutants = [
            ([('    _verify_inputs(manifest, args)\n', '    pass\n'),
              ('        ca = _verify_inputs(manifest, args)\n', "        ca = b'synthetic CA'\n"),
              ('                _verify_inputs(manifest, args)\n', '                pass\n')], before_oracle),
            ([('                _verify_inputs(manifest, args)\n', '                pass\n')], after_oracle),
        ]
        for index, (changes, oracle) in enumerate(mutants):
            with self.subTest(oracle=oracle), tempfile.TemporaryDirectory(prefix='synthetic-execution-mutant-') as directory:
                pristine = unittest.TestResult()
                ConfigExecution(oracle).run(pristine)
                self.assertTrue(pristine.wasSuccessful(), str(pristine.errors + pristine.failures))
                mutated = source
                for old, new in changes:
                    # Match full indentation so initial/callback call sites are distinct.
                    lines = mutated.splitlines(keepends=True)
                    self.assertEqual(lines.count(old), 1)
                    mutated = ''.join(new if line == old else line for line in lines)
                path = Path(directory) / 'execution_mutant.py'
                path.write_text(mutated)
                spec = importlib.util.spec_from_file_location('execution_mutant_' + str(index), path)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                result = unittest.TestResult()
                with patch.dict(globals(), acquisition=module):
                    ConfigExecution(oracle).run(result)
                self.assertFalse(result.errors, 'mutation instrumentation error is not a killed mutant')
                self.assertEqual(len(result.failures), 1)
                self.assertIn('execute must refuse', result.failures[0][1])


if __name__ == '__main__':
    unittest.main()

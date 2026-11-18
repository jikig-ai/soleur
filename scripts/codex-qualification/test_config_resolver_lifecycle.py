"""Owned scratch lifecycle checks with resolver/socket seams closed to networking."""
import os
import functools
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import config_https as transport
import config_resolver as helper
import resolver_supervisor as supervisor

REAL_POPEN = subprocess.Popen
GUARDS = []
SANDBOX = None
REPO = Path(__file__).resolve().parents[2]


def bounded_command(command, **kwargs):
    # REAL_POPEN is reserved for the fixed allocator/namespace wrapper commands;
    # ordinary fixture launches still pass the module's scratch-only guard.
    process = REAL_POPEN(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, start_new_session=True, **kwargs)
    try:
        stdout, stderr = process.communicate(timeout=128.)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate(timeout=2.)
        return subprocess.CompletedProcess(command, 124, stdout, stderr)
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def run_namespace_row(root, sandbox, test, run=bounded_command):
    command = ['timeout', '-k', '5', '120', 'bash', str(root / 'scripts/soleur-sandbox.sh'),
               'run-isolated', str(sandbox), '--', sys.executable, '-I', '-S', '-B', '-c',
               'import sys,unittest; sys.path.insert(0,sys.argv.pop(1)); '
               'import test_config_resolver_lifecycle as m; '
               'r=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromName(sys.argv.pop(1),m)); '
               'r.wasSuccessful() or sys.exit(1); unittest.main(module=m)',
               str(sandbox / 'scripts/codex-qualification'),
               'ConfigLifecycle.test_isolated_helper_bootstraps_fixed_import_and_resolves_only_synthetic_rows', test]
    result = run(command, cwd=str(root), env={'PATH': os.defpath, 'LC_ALL': 'C',
                 'TMPDIR': '/var/tmp', 'SOLEUR_LIFECYCLE_NAMESPACE': '1'})
    first = result.stderr.decode('utf-8', errors='replace').splitlines()
    diagnostic = first[0] if first else 'no diagnostic'
    if result.returncode in (2, 127) or (result.returncode == 125 and
                                        diagnostic.startswith('RUN_IN_PID_NAMESPACE_REFUSED')):
        raise AssertionError(f'UNVERIFIED-NO-NAMESPACE: {diagnostic}')
    if result.returncode in (124, 137):
        raise AssertionError('INCONCLUSIVE-NAMESPACE-TIMEOUT')
    if result.returncode != 0:
        raise AssertionError(f'Namespace control/mutant failed rc={result.returncode}: '
                             + result.stderr.decode('utf-8', errors='replace')[:12000])


def namespace_mutant(test):
    @functools.wraps(test)
    def isolated(self):
        global SANDBOX
        if os.environ.get('SOLEUR_LIFECYCLE_NAMESPACE') == '1':
            nspid = next((line.split()[1:] for line in Path('/proc/self/status').read_text().splitlines()
                          if line.startswith('NSpid:')), [])
            self.assertEqual((os.getpid(), nspid), (1, ['1']), 'UNVERIFIED-NO-NAMESPACE: invalid reentry')
            return test(self)
        if SANDBOX is None:
            result = bounded_command(['bash', str(REPO / 'scripts/soleur-sandbox.sh'),
                                      'new', 'config-lifecycle'], cwd=str(REPO))
            self.assertEqual(result.returncode, 0, 'ALLOC-FAILED: ' + result.stderr.decode(errors='replace')[:1000])
            SANDBOX = Path(result.stdout.decode().strip())
            self.assertTrue(SANDBOX.is_absolute() and SANDBOX.is_dir() and
                            SANDBOX.name.startswith('soleur-sbx.'), 'ALLOC-FAILED: invalid path')
        return run_namespace_row(REPO, SANDBOX, f'ConfigLifecycle.{test.__name__}')
    return isolated


class NamespaceDispatchTests(unittest.TestCase):
    def test_dispatch_uses_allocator_namespace_and_kill_after_bound(self):
        calls = []
        def run(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0, b'control and mutant passed', b'')
        run_namespace_row(Path('/synthetic/repo'), Path('/var/tmp/soleur-sbx.test.fake'),
                          'ConfigLifecycle.test_mutant', run)
        command, options = calls[0]
        self.assertEqual(command[:4], ['timeout', '-k', '5', '120'])
        self.assertEqual(command[4:9], ['bash', '/synthetic/repo/scripts/soleur-sandbox.sh',
                         'run-isolated', '/var/tmp/soleur-sbx.test.fake', '--'])
        self.assertIn('ConfigLifecycle.test_isolated_helper_bootstraps_fixed_import_and_resolves_only_synthetic_rows', command)
        self.assertEqual(command[-1], 'ConfigLifecycle.test_mutant')
        self.assertEqual(options['env']['SOLEUR_LIFECYCLE_NAMESPACE'], '1')
        self.assertEqual(len(calls), 1)

    def test_refusal_fails_closed_without_second_run(self):
        for code, error in ((125, b'RUN_IN_PID_NAMESPACE_REFUSED reason=userns-unavailable\n'),
                            (2, b'run-isolated: helper missing\n'),
                            (127, b'missing command\n')):
            calls = []
            def refused(command, **kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, code, b'', error)
            with self.subTest(code=code), self.assertRaisesRegex(AssertionError, 'UNVERIFIED-NO-NAMESPACE'):
                run_namespace_row(Path('/synthetic/repo'), Path('/var/tmp/soleur-sbx.test.fake'),
                                  'ConfigLifecycle.test_mutant', refused)
            self.assertEqual(len(calls), 1)

    def test_timeout_is_inconclusive_not_a_mutant_kill(self):
        for code in (124, 137):
            def timed_out(command, **kwargs):
                return subprocess.CompletedProcess(command, code, b'', b'')
            with self.subTest(code=code), self.assertRaisesRegex(AssertionError, 'INCONCLUSIVE-NAMESPACE-TIMEOUT'):
                run_namespace_row(Path('/synthetic/repo'), Path('/var/tmp/soleur-sbx.test.fake'),
                                  'ConfigLifecycle.test_mutant', timed_out)

    def test_environment_marker_cannot_bypass_namespace_verification(self):
        called = []
        @namespace_mutant
        def mutant(seat):
            called.append(True)
        for pid, status in ((1, 'NSpid:\t42\n'), (1, 'NSpid:\t42\t1\n'),
                            (42, 'NSpid:\t1\n')):
            with self.subTest(pid=pid, status=status), \
                    patch.dict(os.environ, {'SOLEUR_LIFECYCLE_NAMESPACE': '1'}), \
                    patch.object(os, 'getpid', return_value=pid), \
                    patch.object(Path, 'read_text', return_value=status):
                with self.assertRaisesRegex(AssertionError, 'UNVERIFIED-NO-NAMESPACE'):
                    mutant(self)
                self.assertEqual(called, [])
        # This is a no-process synthetic callback, never a signalling mutant.
        with patch.dict(os.environ, {'SOLEUR_LIFECYCLE_NAMESPACE': '1'}), \
                patch.object(os, 'getpid', return_value=1), \
                patch.object(Path, 'read_text', return_value='NSpid:\t1\n'):
            mutant(self)
        self.assertEqual(called, [True])

    def test_red_namespace_control_prevents_mutant_execution(self):
        commands = []
        def capture(command, **kwargs):
            commands.append(command)
            return subprocess.CompletedProcess(command, 0, b'', b'')
        run_namespace_row(Path('/synthetic/repo'), Path('/var/tmp/soleur-sbx.test.fake'),
                          'ConfigLifecycle.test_mutant', capture)
        command = commands[0]
        runner = command[command.index('-c') + 1]
        class RedControl:
            def wasSuccessful(self):
                return False
        with patch.object(sys, 'argv', ['runner', '/synthetic/modules',
                          'ConfigLifecycle.test_isolated_helper_bootstraps_fixed_import_and_resolves_only_synthetic_rows',
                          'ConfigLifecycle.test_mutant']), patch.object(sys, 'path', list(sys.path)), \
                patch.object(unittest.TextTestRunner, 'run', return_value=RedControl()), \
                patch.object(unittest, 'main') as run_mutant:
            with self.assertRaises(SystemExit) as stopped:
                exec(compile(runner, '<synthetic-namespace-runner>', 'exec'), {})
            self.assertEqual(stopped.exception.code, 1)
            run_mutant.assert_not_called()


def setUpModule():
    def scratch_only(command, *args, **kwargs):
        script = Path(command[4]) if type(command) is list and len(command) >= 5 else Path('/')
        if (command[1:4] != ['-I', '-S', '-B'] or
                not script.parent.name.startswith('config-lifecycle-test-') or
                not script.name.startswith('synthetic_')):
            raise AssertionError('Only owned synthetic processes permitted')
        return REAL_POPEN(command, *args, **kwargs)
    for target in ('socket.getaddrinfo', 'socket.socket', 'socket.create_connection'):
        guard = patch(target, side_effect=AssertionError('Offline network boundary refused'))
        guard.start()
        GUARDS.append(guard)
    guard = patch('subprocess.Popen', side_effect=scratch_only)
    guard.start()
    GUARDS.append(guard)


def tearDownModule():
    global SANDBOX
    for guard in reversed(GUARDS):
        guard.stop()
    GUARDS.clear()
    if SANDBOX is not None:
        result = bounded_command(['bash', str(REPO / 'scripts/soleur-sandbox.sh'), 'rm', str(SANDBOX)], cwd=str(REPO))
        if result.returncode != 0:
            raise AssertionError(f'Sandbox cleanup refused: {SANDBOX}: ' + result.stderr.decode(errors='replace')[:1000])
        SANDBOX = None


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux process containment')
class ConfigLifecycle(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='config-lifecycle-test-')
        self.root = Path(self.scratch.name)
        self.addCleanup(self.scratch.cleanup)
        self.children = []
        self.adopted = []
        supervisor.enable_subreaper()

    def tearDown(self):
        self.cleanup_owned()

    def owned_descendant(self, pid):
        # The random scratch path is the nonce. Both argv ownership and an
        # ancestry chain ending at this fixture's child/subreaper are required.
        try:
            arguments = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            if not any(argument.startswith(os.fsencode(self.root) + b'/') for argument in arguments):
                return False
            seen = set()
            current = pid
            while current > 1 and current not in seen:
                seen.add(current)
                status = Path(f'/proc/{current}/status').read_text()
                parent = int(next(line.split()[1] for line in status.splitlines() if line.startswith('PPid:')))
                if parent == os.getpid() or parent in {child.pid for child in self.children}:
                    return True
                current = parent
        except (FileNotFoundError, ProcessLookupError):
            return False
        return False

    def census_owned(self):
        # This does not depend on either readiness or the resolver's PID file.
        direct = {process.pid for process in self.children}
        for entry in Path('/proc').iterdir():
            if entry.name.isascii() and entry.name.isdecimal():
                pid = int(entry.name)
                if pid not in direct and pid not in self.adopted and self.owned_descendant(pid):
                    self.adopted.append(pid)

    def retire(self, pid):
        while pid in self.adopted:
            self.adopted.remove(pid)

    def cleanup_owned(self):
        self.census_owned()
        for process in list(self.children):
            if process.poll() is None:
                process.kill()
            process.wait(timeout=2.)
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()
        self.census_owned()
        # Only current nonce-owned descendants may be signalled; a PID is
        # retired immediately on wait/absence, before another PID could reuse it.
        for pid in list(self.adopted):
            if self.owned_descendant(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    self.assertTrue(self.reaped(pid, 2.), 'Disappearing synthetic helper was not reaped')
                    continue
            self.assertTrue(self.reaped(pid, 2.), 'Owned synthetic helper was not reaped')
        self.children.clear()

    def reaped(self, pid, budget):
        deadline = time.monotonic() + budget
        while time.monotonic() < deadline:
            try:
                done, _ = os.waitpid(pid, os.WNOHANG)
                if done:
                    self.retire(pid)
                    return True
            except ChildProcessError:
                if not Path(f'/proc/{pid}').exists():
                    self.retire(pid)
                    return True
            time.sleep(.005)
        return False

    def launch(self, script, *args):
        process = subprocess.Popen([sys.executable, '-I', '-S', '-B', str(script), *args],
            env={}, cwd='/', close_fds=True, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.children.append(process)
        self.census_owned()
        return process

    def wrapper(self, *, blocking=False, disable_parent_death=False,
                bypass_group_check=False, wait_for_parent_loss=False):
        path = self.root / 'synthetic_helper.py'
        ready = self.root / 'ready'
        # Execute the actual helper source under its actual fixed __file__; no
        # socket call reaches libc, including in the isolated child interpreter.
        path.write_text('import os,sys,time,socket\n'
            'def forbidden(*args,**kwargs): raise AssertionError("Offline socket refused")\n'
            'socket.socket=socket.create_connection=forbidden\n'
            'def resolve(*args,**kwargs):\n'
            f' open({str(ready)!r},"w").write(str(os.getpid()))\n'
            + (' time.sleep(30)\n' if blocking else ' return [(socket.AF_INET,socket.SOCK_STREAM,socket.IPPROTO_TCP,"",("8.8.8.8",443))]\n') +
            'socket.getaddrinfo=resolve\n'
            f'source={str(Path(helper.__file__).resolve())!r}\n'
            'scope={"__file__":source,"__name__":"synthetic_config_helper"}\n'
            'code=open(source).read()\n'
            + ('code=code.replace("if os.getpgid(parent) != os.getpgrp() or os.getsid(parent) != os.getsid(0):","if False:")\n'
               if bypass_group_check else '') +
            'exec(compile(code,source,"exec"),scope)\n'
            + (f'sys.path.insert(0,{str(Path(supervisor.__file__).parent)!r})\n'
               'import resolver_supervisor\nresolver_supervisor.arm_parent_death=lambda _:None\n'
               if disable_parent_death else '') +
            ('deadline=time.monotonic()+2.\n'
             'while os.getppid()==int(sys.argv[-1]) and time.monotonic()<deadline: time.sleep(.005)\n'
             if wait_for_parent_loss else '') +
            'sys.exit(scope["main"]())\n')
        return path, ready

    def test_isolated_helper_bootstraps_fixed_import_and_resolves_only_synthetic_rows(self):
        script, ready = self.wrapper()
        # An owned coordinator supplies the actual parent and shared session.
        coordinator = self.root / 'synthetic_startup.py'
        coordinator.write_text('import os,sys,subprocess\n'
            f'p=subprocess.Popen([sys.executable,"-I","-S","-B",{str(script)!r},"auth.docker.io",str(os.getpid())],env={{}},close_fds=True)\n'
            'sys.exit(p.wait(timeout=2.))\n')
        process = self.launch(coordinator)
        stdout, stderr = process.communicate(timeout=3.)
        self.assertEqual(process.returncode, 0, stderr.decode('ascii', errors='replace'))
        self.assertEqual(stdout, b'[[2,"8.8.8.8",443,0,0]]')
        self.assertTrue(ready.exists())

    def test_parent_loss_before_arming_refuses_before_resolver(self):
        script, ready = self.wrapper(wait_for_parent_loss=True)
        coordinator = self.root / 'synthetic_exiting_parent.py'
        pidfile = self.root / 'starting-child'
        coordinator.write_text('import os,sys,subprocess\n'
            f'p=subprocess.Popen([sys.executable,"-I","-S","-B",{str(script)!r},"auth.docker.io",str(os.getpid())],env={{}},close_fds=True)\n'
            f'open({str(pidfile)!r},"w").write(str(p.pid))\n'
            'os._exit(0)\n')
        process = self.launch(coordinator)
        stdout, _ = process.communicate(timeout=2.)
        self.assertEqual(process.returncode, 0)
        self.assertEqual(stdout, b'')
        self.assertFalse(ready.exists())
        pid = int(pidfile.read_text())
        if pid not in self.adopted:
            self.adopted.append(pid)
        done, status = os.waitpid(pid, 0)
        self.retire(pid)
        self.assertEqual(done, pid)
        self.assertEqual(os.waitstatus_to_exitcode(status), 1)

    def fixture(self, *, disable_parent_death=False, detached=False,
                bypass_group_check=False, readiness_fault=None):
        script, ready = self.wrapper(blocking=True, disable_parent_death=disable_parent_death,
                                     bypass_group_check=bypass_group_check)
        # The real transport launches its sibling helper, redirected only to an
        # owned, network-free wrapper; its real spawn and read loop remain intact.
        (self.root / 'config_resolver.py').write_bytes(script.read_bytes())
        source = Path(transport.__file__).read_text()
        if detached:
            source = source.replace('start_new_session=False', 'start_new_session=True')
        coordinator = self.root / 'synthetic_coordinator.py'
        coordinator.write_text('import os,sys,socket\n'
            f'sys.path.insert(0,{str(Path(transport.__file__).parent)!r})\n'
            'import config_https as t\n'
            f't.__file__={str(self.root / "config_https.py")!r}\n'
            f'exec(compile({source!r},t.__file__,"exec"),t.__dict__)\n'
            'def forbidden(*args,**kwargs): raise AssertionError("Offline network refused")\n'
            'socket.getaddrinfo=socket.socket=socket.create_connection=forbidden\n'
            't.resolve_addresses("auth.docker.io",deadline=t.time.monotonic()+8.,clock=t.time.monotonic)\n')
        process = self.launch(coordinator)
        deadline = time.monotonic() + 3.
        while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
            self.census_owned()
            time.sleep(.005)
        self.census_owned()
        if readiness_fault == 'assertion':
            self.fail('Synthetic early readiness assertion')
        self.assertTrue(ready.exists(), 'Synthetic blocking resolver did not start')
        if readiness_fault == 'pidfile':
            ready.write_text('synthetic-invalid-pid')
        pid = int(ready.read_text())
        if pid not in self.adopted:
            self.adopted.append(pid)
        return process, pid

    def test_readiness_failures_still_census_and_reap_nonce_owned_helper(self):
        for failure, exception in (('assertion', AssertionError), ('pidfile', ValueError)):
            with self.subTest(failure=failure):
                with self.assertRaises(exception):
                    self.fixture(readiness_fault=failure)
                self.assertTrue(self.adopted, 'Readiness-independent helper census was empty')
                owned = list(self.adopted)
                self.cleanup_owned()
                self.assertEqual(self.adopted, [])
                self.assertTrue(all(not Path(f'/proc/{pid}').exists() for pid in owned))
                (self.root / 'ready').unlink(missing_ok=True)

    def test_reaping_immediately_retires_success_and_known_absence(self):
        for absent in (False, True):
            with self.subTest(absent=absent):
                # Census and PID-file enrollment may report the same child.
                self.adopted.extend((2147483647, 2147483647))
                with patch.object(os, 'waitpid', side_effect=ChildProcessError if absent else None,
                                  return_value=(2147483647, 0)):
                    self.assertTrue(self.reaped(2147483647, .1))
                self.assertEqual(self.adopted, [])

    def test_coordinator_death_kills_blocking_resolver_independently_of_process_group(self):
        process, pid = self.fixture()
        os.kill(process.pid, signal.SIGKILL)  # Owned coordinator only, not its group.
        process.wait(timeout=2.)
        self.assertTrue(self.reaped(pid, 1.), 'Parent death left the helper alive')

    @namespace_mutant
    def test_parent_death_mutation_is_detected_with_single_coordinator_kill(self):
        process, pid = self.fixture(disable_parent_death=True)
        os.kill(process.pid, signal.SIGKILL)
        process.wait(timeout=2.)
        self.assertFalse(self.reaped(pid, .1), 'Mutation did not remove parent-death containment')

    @namespace_mutant
    def test_outer_group_timeout_kills_helper_even_without_parent_death_signal(self):
        process, pid = self.fixture(disable_parent_death=True, bypass_group_check=True)
        self.assertEqual(os.getpgid(pid), process.pid)
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2.)
        self.assertTrue(self.reaped(pid, 1.), 'Outer group cancellation left the helper alive')

    @namespace_mutant
    def test_group_membership_mutation_survives_outer_cancellation_without_pdeath_backstop(self):
        # Hold the helper's independent safeguards open in this synthetic seam
        # so this test discriminates only the transport's process-group layer.
        process, pid = self.fixture(disable_parent_death=True, bypass_group_check=True, detached=True)
        self.assertNotEqual(os.getpgid(pid), process.pid)
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2.)
        self.assertFalse(self.reaped(pid, .1), 'Mutation did not detach the helper')

    def test_detached_group_mutation_refuses_before_resolution(self):
        # Parent/session validation independently detects a detached launch.
        script, ready = self.wrapper()
        process = self.launch(script, 'auth.docker.io', str(os.getpid()))
        stdout, _ = process.communicate(timeout=2.)
        self.assertEqual(process.returncode, 1)
        self.assertEqual(stdout, b'')
        self.assertFalse(ready.exists())


if __name__ == '__main__':
    unittest.main()

"""Owned scratch lifecycle checks with resolver/socket seams closed to networking."""
import os
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
    for guard in reversed(GUARDS):
        guard.stop()
    GUARDS.clear()


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
        # Only PIDs observed from our scratch argv/parent may be signalled.
        for pid in self.adopted:
            try:
                if str(self.root).encode() in Path(f'/proc/{pid}/cmdline').read_bytes():
                    os.kill(pid, signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError):
                self.assertTrue(self.reaped(pid, 2.), 'Disappearing synthetic child was not reaped')
        for process in self.children:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=2.)
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()
        for pid in self.adopted:
            self.assertTrue(self.reaped(pid, 2.), 'Owned synthetic helper was not reaped')

    def reaped(self, pid, budget):
        deadline = time.monotonic() + budget
        while time.monotonic() < deadline:
            try:
                done, _ = os.waitpid(pid, os.WNOHANG)
                if done:
                    return True
            except ChildProcessError:
                if not Path(f'/proc/{pid}').exists():
                    return True
            time.sleep(.005)
        return False

    def launch(self, script, *args):
        process = subprocess.Popen([sys.executable, '-I', '-S', '-B', str(script), *args],
            env={}, cwd='/', close_fds=True, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.children.append(process)
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
        self.adopted.append(pid)
        done, status = os.waitpid(pid, 0)
        self.assertEqual(done, pid)
        self.assertEqual(os.waitstatus_to_exitcode(status), 1)

    def fixture(self, *, disable_parent_death=False, detached=False,
                bypass_group_check=False):
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
            time.sleep(.005)
        self.assertTrue(ready.exists(), 'Synthetic blocking resolver did not start')
        pid = int(ready.read_text())
        self.adopted.append(pid)
        return process, pid

    def test_coordinator_death_kills_blocking_resolver_independently_of_process_group(self):
        process, pid = self.fixture()
        os.kill(process.pid, signal.SIGKILL)  # Owned coordinator only, not its group.
        process.wait(timeout=2.)
        self.assertTrue(self.reaped(pid, 1.), 'Parent death left the helper alive')

    def test_parent_death_mutation_is_detected_with_single_coordinator_kill(self):
        process, pid = self.fixture(disable_parent_death=True)
        os.kill(process.pid, signal.SIGKILL)
        process.wait(timeout=2.)
        self.assertFalse(self.reaped(pid, .1), 'Mutation did not remove parent-death containment')

    def test_outer_group_timeout_kills_helper_even_without_parent_death_signal(self):
        process, pid = self.fixture(disable_parent_death=True, bypass_group_check=True)
        self.assertEqual(os.getpgid(pid), process.pid)
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2.)
        self.assertTrue(self.reaped(pid, 1.), 'Outer group cancellation left the helper alive')

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

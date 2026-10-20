"""Synthetic child lifecycle checks only; no production helper/resolver runs."""
import os
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import resolver_supervisor as supervisor
import resolver_diagnostic as diagnostic

_REAL_POPEN = subprocess.Popen
_OFFLINE_GUARDS = []


def setUpModule():
    def synthetic_only(command, *args, **kwargs):
        script = Path(command[4]) if type(command) is list and len(command) >= 5 else Path('/')
        if (command[1:4] != ['-I', '-S', '-B'] or
                not script.parent.name.startswith('resolver-lifecycle-test-') or
                not script.name.startswith('synthetic_') or script.suffix != '.py'):
            raise AssertionError('Only synthesized scratch processes permitted')
        return _REAL_POPEN(command, *args, **kwargs)
    for target in ('socket.getaddrinfo', 'socket.socket', 'socket.create_connection'):
        guard = patch(target, side_effect=AssertionError('Offline test boundary refused'))
        guard.start()
        _OFFLINE_GUARDS.append(guard)
    guard = patch('subprocess.Popen', side_effect=synthetic_only)
    guard.start()
    _OFFLINE_GUARDS.append(guard)


def tearDownModule():
    for guard in reversed(_OFFLINE_GUARDS):
        guard.stop()
    _OFFLINE_GUARDS.clear()


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='resolver-lifecycle-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        # The scratch coordinator/helper contain no socket or resolver code.
        self.helper = self.root / 'synthetic_helper.py'
        self.helper.write_text('import os,sys,time\n'
            f'sys.path.insert(0,{str(Path(supervisor.__file__).parent)!r})\n'
            'from resolver_supervisor import arm_parent_death\n'
            'arm_parent_death(int(sys.argv[1]))\n'
            'open(sys.argv[2],"w").write(str(os.getpid()))\n'
            'time.sleep(30)\n')
        self.coordinator = self.root / 'synthetic_coordinator.py'
        self.pidfile = self.root / 'helper.pid'
        self.coordinator.write_text('import os,sys,time,subprocess,signal\n'
            f'sys.path.insert(0,{str(Path(supervisor.__file__).parent)!r})\n'
            'from resolver_supervisor import arm_parent_death\n'
            'arm_parent_death(int(sys.argv[1]))\n'
            f'p=subprocess.Popen([sys.executable,"-I","-S","-B",{str(self.helper)!r},str(os.getpid()),{str(self.pidfile)!r}],env={{}},close_fds=True)\n'
            'if len(sys.argv)>2 and sys.argv[2]=="die":\n'
            ' while not os.path.exists(sys.argv[3]): time.sleep(.01)\n'
            ' os._exit(0)\n'
            'signal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
            'time.sleep(30)\n')

    def assert_gone(self, pid):
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def tearDown(self):
        # Error paths must also leave no scratch process/zombie. Recheck its
        # scratch-script argv before signalling; never target an unrelated PID.
        owned = []
        needle = str(self.root).encode()
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit() or int(entry.name) == os.getpid():
                continue
            try:
                argv = (entry / 'cmdline').read_bytes()
                if needle in argv:
                    owned.append(int(entry.name))
                    os.kill(int(entry.name), signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                argv = b''  # Process disappeared or is outside readable fixture ownership.
        deadline = time.monotonic() + 2.
        pending = set(owned)
        while pending and time.monotonic() < deadline:
            for pid in list(pending):
                try:
                    done, _ = os.waitpid(pid, os.WNOHANG)
                    if done:
                        pending.remove(pid)
                except ChildProcessError:
                    if not Path('/proc/' + str(pid)).exists():
                        pending.remove(pid)
            time.sleep(.005)
        self.assertFalse(pending, 'Synthetic child teardown could not establish reaping')

    def test_outer_timeout_kills_and_reaps_coordinator_and_live_helper(self):
        result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(self.coordinator),
            str(os.getpid())], timeout=.5, grace=.2)
        self.assertEqual(result, 2)
        self.assertTrue(self.pidfile.exists())
        self.assert_gone(int(self.pidfile.read_text()))

    def test_coordinator_death_kills_helper_and_supervisor_reaps_adopted_child(self):
        result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(self.coordinator),
            str(os.getpid()), 'die', str(self.pidfile)], timeout=2., grace=.2)
        self.assertEqual(result, 2)  # An adopted child is not a clean coordinator result.
        self.assert_gone(int(self.pidfile.read_text()))

    def test_parent_race_fails_before_synthetic_child_work(self):
        child = subprocess.run([sys.executable, '-I', '-S', '-B', str(self.helper),
            str(os.getpid() + 1000000), str(self.pidfile)], env={}, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2., close_fds=True)
        self.assertNotEqual(child.returncode, 0)
        self.assertFalse(self.pidfile.exists())

    def test_supervisor_emits_only_closed_sanitized_stage_messages(self):
        report = []
        for message, code in [
                ('Resolver diagnostic refused; preconsume_stage=source_binding', 1),
                ('SYNTHETIC_SECRET_DO_NOT_RETAIN', 2)]:
            program = self.root / 'synthetic_report.py'
            program.write_text('import sys\nprint(' + repr(message) + ')\nsys.exit(1)\n')
            result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(program)],
                                          timeout=2., grace=.2, report=report.append)
            self.assertEqual(result, code)
        self.assertEqual(report, ['Resolver diagnostic refused; preconsume_stage=source_binding'])

    def test_supervisor_error_path_kills_and_reaps_live_descendants(self):
        original = supervisor._exited
        failed = False
        def fail_once_with_live_helper(pid):
            nonlocal failed
            if self.pidfile.exists() and not failed:
                failed = True
                raise RuntimeError('SYNTHETIC_SECRET_DO_NOT_RETAIN')
            return original(pid)
        with patch.object(supervisor, '_exited', side_effect=fail_once_with_live_helper):
            result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(self.coordinator),
                str(os.getpid())], timeout=2., grace=.2)
        self.assertTrue(failed)
        self.assertEqual(result, 2)
        self.assert_gone(int(self.pidfile.read_text()))

    def synthetic_coordinate(self, *, pause_after=False):
        from test_resolver_diagnostic import plan
        directory = self.root / 'synthetic-action'
        directory.mkdir(mode=0o700)
        info = directory.stat()
        manifest = plan(str(directory), {'dev': info.st_dev, 'ino': info.st_ino, 'uid': info.st_uid})
        digest = diagnostic.sha(diagnostic.canonical(manifest))
        manifest_file = directory / diagnostic.MANIFEST
        manifest_file.write_bytes(diagnostic.canonical(manifest) + b'\n')
        manifest_file.chmod(0o600)
        args = {'manifest': str(manifest_file), 'manifest_sha256': digest, 'parent_pid': 3456}
        parent_argv = ['/synthetic/python', '-I', '-S', '-B',
            '/synthetic/repo/scripts/codex-qualification/resolver_supervisor.py', 'execute',
            '--manifest', str(manifest_file), '--manifest-sha256', digest, '--supervisor-sha256', 'b' * 64]
        script = self.root / 'synthetic_composition.py'
        script.write_text('import os,sys,time,socket,subprocess\n'
            'from argparse import Namespace\nfrom pathlib import Path\nfrom unittest.mock import patch,Mock\n'
            f'sys.path.insert(0,{str(Path(supervisor.__file__).parent)!r})\n'
            'import resolver_diagnostic as d\nimport resolver_supervisor as s\n'
            's.arm_parent_death(int(sys.argv[1]))\n'
            'real_diagnostic=d.Diagnostic\nreal_read=Path.read_bytes\n'
            f'parent_argv={parent_argv!r}\n'
            'def proc(path):\n'
            ' if str(path)=="/proc/3456/cmdline": return b"\\0".join(v.encode() for v in parent_argv)+b"\\0"\n'
            ' return real_read(path)\n'
            'def collector(*args,**kwargs):\n'
            ' return real_diagnostic(*args,helper=Mock(return_value=("admitted","complete",1,"reaped")),**kwargs)\n'
            'with patch.object(d,"__file__","/synthetic/repo/scripts/codex-qualification/resolver_diagnostic.py"),'
            'patch.object(d,"verify_sources"),patch.object(d,"Diagnostic",side_effect=collector),'
            'patch.object(s,"arm_parent_death"),patch.object(d.resource,"setrlimit"),'
            'patch.object(os,"getpid",return_value=1234),patch.object(os,"getpgrp",return_value=1234),'
            'patch.object(os,"getsid",return_value=1234),patch.object(Path,"read_bytes",proc),'
            'patch.object(socket,"getaddrinfo",side_effect=AssertionError("Offline DNS refused")),'
            'patch.object(socket,"socket",side_effect=AssertionError("Offline connection refused")),'
            'patch.object(subprocess,"Popen",side_effect=AssertionError("Production child refused")):\n'
            f' result=d.coordinate(Namespace(**{args!r}),clock=lambda:0.)\n'
            + ('sys.stdout.flush()\ntime.sleep(30)\n' if pause_after else '') + 'sys.exit(result)\n')
        expected = {'manifest_sha256': digest, 'source_sha': manifest['source_sha'], 'supervisor_sha256': 'b' * 64}
        return script, directory, manifest, digest, expected

    def test_real_coordinator_and_supervisor_compose_with_only_synthesized_dependencies(self):
        script, directory, manifest, digest, expected = self.synthetic_coordinate()
        signals = []
        result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(script), str(os.getpid())],
            timeout=2., grace=.2, expected=expected, completed=signals)
        self.assertEqual(result, 0)
        self.assertEqual(len(signals), 1)
        receipt = json.loads((directory / diagnostic.RECEIPT).read_bytes())
        marker = diagnostic.sha((directory / diagnostic.MARKER).read_bytes())
        diagnostic.checked_completed_action(receipt, signals[0], manifest, digest, marker, supervisor_exit=result)

    def test_candidate_before_outer_timeout_never_yields_completion_signal(self):
        script, directory, manifest, digest, expected = self.synthetic_coordinate(pause_after=True)
        signals = []
        result = supervisor.supervise([sys.executable, '-I', '-S', '-B', str(script), str(os.getpid())],
            timeout=.5, grace=.2, expected=expected, completed=signals)
        self.assertEqual(result, 2)
        self.assertEqual(signals, [])
        receipt = json.loads((directory / diagnostic.RECEIPT).read_bytes())
        marker = diagnostic.sha((directory / diagnostic.MARKER).read_bytes())
        with self.assertRaises(diagnostic.Refused):
            diagnostic.checked_completed_action(receipt, None, manifest, digest, marker, supervisor_exit=result)

    def test_supervisor_parent_death_terminates_group_and_reaps_helper(self):
        monitor = self.root / 'synthetic_monitor.py'
        monitor.write_text('import os,sys\n'
            f'sys.path.insert(0,{str(Path(supervisor.__file__).parent)!r})\n'
            'from resolver_supervisor import arm_parent_death,supervise\n'
            'arm_parent_death(int(sys.argv[1]),terminate=True)\n'
            f'sys.exit(supervise([sys.executable,"-I","-S","-B",{str(self.coordinator)!r},str(os.getpid())],timeout=5.,grace=.2))\n')
        owner = self.root / 'synthetic_owner.py'
        monitor_pid = self.root / 'monitor.pid'
        owner.write_text('import os,sys,time,subprocess\n'
            f'p=subprocess.Popen([sys.executable,"-I","-S","-B",{str(monitor)!r},str(os.getpid())],env={{}},close_fds=True)\n'
            f'open({str(monitor_pid)!r},"w").write(str(p.pid))\n'
            'time.sleep(30)\n')
        # The test acts as a subreaper so even a broken implementation cannot orphan fixtures.
        supervisor.enable_subreaper()
        process = subprocess.Popen([sys.executable, '-I', '-S', '-B', str(owner)], env={},
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            close_fds=True, start_new_session=True)
        try:
            deadline = time.monotonic() + 2.
            while not self.pidfile.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(self.pidfile.exists())
            helper_pid = int(self.pidfile.read_text())
            process.kill()
            process.wait(timeout=2.)
            pid = int(monitor_pid.read_text())
            while time.monotonic() < deadline + 2.:
                done, _status = os.waitpid(pid, os.WNOHANG)
                if done:
                    break
                time.sleep(.01)
            self.assertEqual(done, pid)
            self.assert_gone(helper_pid)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2.)


if __name__ == '__main__':
    unittest.main()

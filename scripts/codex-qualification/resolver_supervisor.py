"""Dormant Linux outer containment; operational invocation needs separate approval.

This supervisor does not resolve names. Coordinator and helper share a dedicated
process group. Parent-death signals close the startup race; a subreaper owns
descendants if the coordinator dies. Timeout exit alone proves no cleanup.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

STAGES = ('startup', 'manifest', 'source_binding', 'private_output', 'gate_publication')
CLOSED_MESSAGES = tuple('Resolver diagnostic refused; preconsume_stage=' + stage + '\n' for stage in STAGES) + (
    'Resolver diagnostic publication refused\n',)
CANDIDATE_PREFIX = 'Resolver diagnostic candidate='
COMPLETION_PREFIX = 'Resolver diagnostic completion='


def completion_signal(candidate, expected):
    required = {'schema': 'resolver-coordinator-completion-v1', **expected,
                'receipt_sha256': candidate.get('receipt_sha256') if type(candidate) is dict else None}
    if type(candidate) is not dict or set(candidate) != set(required) or candidate != required:
        raise RuntimeError('Resolver completion refused')
    for key, length in (('manifest_sha256', 64), ('source_sha', 40),
                        ('supervisor_sha256', 64), ('receipt_sha256', 64)):
        value = candidate[key]
        if type(value) is not str or len(value) != length or any(c not in '0123456789abcdef' for c in value):
            raise RuntimeError('Resolver completion refused')
    return {'schema': 'resolver-supervisor-completion-v1', **expected,
            'receipt_sha256': candidate['receipt_sha256'], 'coordinator_exit': 0,
            'group_cleanup': 'reaped', 'adopted_descendants': False}


def checked_completion(value, *, manifest_sha256, source_sha, supervisor_sha256,
                       receipt_sha256, supervisor_exit):
    expected = {'manifest_sha256': manifest_sha256, 'source_sha': source_sha,
                'supervisor_sha256': supervisor_sha256}
    candidate = {'schema': 'resolver-coordinator-completion-v1', **expected,
                 'receipt_sha256': receipt_sha256}
    signal_value = completion_signal(candidate, expected)
    if (type(value) is not dict or value != signal_value or type(supervisor_exit) is not int
            or supervisor_exit != 0):
        raise RuntimeError('Resolver completion refused')


class ClosedParser(argparse.ArgumentParser):
    def error(self, _message):
        print('Resolver diagnostic refused; preconsume_stage=startup')
        raise SystemExit(1)


def _prctl(option, value):
    if not sys.platform.startswith('linux'):
        raise RuntimeError('Resolver containment unavailable')
    function = ctypes.CDLL(None, use_errno=True).prctl
    function.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                         ctypes.c_ulong, ctypes.c_ulong]
    function.restype = ctypes.c_int
    if function(option, value, 0, 0, 0) != 0:
        raise RuntimeError('Resolver containment unavailable')


def arm_parent_death(expected_parent, *, terminate=False):
    """Arm before child work, then reject a parent change during process startup."""
    if type(expected_parent) is not int or expected_parent <= 1:
        raise RuntimeError('Resolver parent refused')
    _prctl(1, signal.SIGTERM if terminate else signal.SIGKILL)  # PR_SET_PDEATHSIG
    if os.getppid() != expected_parent:
        raise RuntimeError('Resolver parent refused')


def enable_subreaper():
    _prctl(36, 1)  # PR_SET_CHILD_SUBREAPER; Linux UAPI linux/prctl.h.


def _exited(pid):
    # WNOWAIT keeps the leader PID pinned until the final process-group signal.
    return os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None


def _reap_group(process, deadline):
    code, adopted = process.returncode, False
    while True:
        try:
            pid, status = os.waitpid(-process.pid, os.WNOHANG)
        except ChildProcessError:
            return code, adopted, True
        if pid == process.pid:
            code = os.waitstatus_to_exitcode(status)
            process.returncode = code
        elif pid:
            adopted = True
        if not pid:
            if time.monotonic() >= deadline:
                return code, adopted, False
            time.sleep(.005)


def supervise(command, *, timeout=12., grace=1., report=None, expected=None, completed=None):
    """Contain one coordinator; injected commands/budgets exist for offline tests.

    Operational main fixes the command and 12s+1s bounds. The leader is NOT reaped
    until the last group signal, avoiding signalling a recycled process-group ID.
    The final quarter of the grace interval is reserved for SIGKILL and reaping.
    Any adopted child or timeout makes the outer result uncertain (exit 2).
    """
    enable_subreaper()
    interrupted = [False]
    def terminate(_signum, _frame):
        interrupted[0] = True
    previous = {sig: signal.signal(sig, terminate) for sig in (signal.SIGTERM, signal.SIGINT)}
    process = None
    uncertain = False
    raw = bytearray()
    def drain():
        while len(raw) < 769:
            try:
                part = os.read(process.stdout.fileno(), 769 - len(raw))
            except BlockingIOError:
                return
            if not part:
                return
            raw.extend(part)
    try:
        started = time.monotonic()
        process = subprocess.Popen(command, env={}, cwd='/', close_fds=True,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, start_new_session=True)
        os.set_blocking(process.stdout.fileno(), False)
        while not _exited(process.pid):
            drain()
            if interrupted[0] or len(raw) > 768 or time.monotonic() >= started + timeout:
                uncertain = True
                break
            time.sleep(min(.01, max(0., started + timeout - time.monotonic())))
        cleanup_end = time.monotonic() + grace
        if uncertain:
            os.killpg(process.pid, signal.SIGTERM)
            kill_at = cleanup_end - min(.25, grace / 2)
            while not _exited(process.pid) and time.monotonic() < kill_at:
                time.sleep(.005)
        # The unreaped leader still owns this group, even on the normal path.
        os.killpg(process.pid, signal.SIGKILL)
        code, adopted, reaped = _reap_group(process, cleanup_end)
        drain()
        if raw:
            message = bytes(raw)
            accepted = next((value for value in CLOSED_MESSAGES if message == value.encode('ascii')), None)
            if accepted is not None and code == 1:
                if report is not None:
                    report(accepted.rstrip('\n'))
            elif expected is not None and code == 0 and not adopted and reaped and not uncertain:
                try:
                    prefix = CANDIDATE_PREFIX.encode('ascii')
                    if not message.startswith(prefix) or not message.endswith(b'\n'):
                        raise RuntimeError('Resolver completion refused')
                    candidate = json.loads(message[len(prefix):-1].decode('ascii'))
                    signal_value = completion_signal(candidate, expected)
                    if completed is not None:
                        completed.append(signal_value)
                    if report is not None:
                        report(COMPLETION_PREFIX + json.dumps(signal_value, sort_keys=True, separators=(',', ':')))
                except Exception:
                    uncertain = True
            else:
                uncertain = True
        elif expected is not None and code == 0:
            uncertain = True
        return 2 if uncertain or adopted or not reaped or interrupted[0] or code is None else (0 if code == 0 else 1)
    except Exception:
        # Never print OS errors, paths, helper output or exception context.
        # On exceptional setup failure, a known unreaped leader still owns PGID.
        if process is not None and process.returncode is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
                _reap_group(process, time.monotonic() + max(.01, grace))
            except Exception:
                return 2
        return 2
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = ClosedParser(description=__doc__)
    parser.add_argument('command', choices=('execute',))
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--supervisor-sha256', required=True)
    args = parser.parse_args()
    try:
        import hashlib
        if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != args.supervisor_sha256:
            raise RuntimeError('Resolver supervisor binding refused')
        from prepare import canonical, sha
        raw_manifest = Path(args.manifest).read_bytes()
        manifest = json.loads(raw_manifest.decode('ascii'))
        if len(raw_manifest) > 32768 or sha(canonical(manifest)) != args.manifest_sha256:
            raise RuntimeError('Resolver manifest binding refused')
        arm_parent_death(os.getppid(), terminate=True)
        command = [sys.executable, '-I', '-S', '-B',
            str(Path(__file__).with_name('resolver_diagnostic.py').absolute()), '_coordinate',
            '--manifest', args.manifest, '--manifest-sha256', args.manifest_sha256,
            '--parent-pid', str(os.getpid())]
        completion = []
        expected = {'manifest_sha256': args.manifest_sha256,
                    'source_sha': manifest['source_sha'],
                    'supervisor_sha256': args.supervisor_sha256}
        code = supervise(command, report=print, expected=expected, completed=completion)
        if code == 0 and len(completion) != 1:
            code = 2
    except Exception:
        code = 2
    print('Resolver diagnostic terminated; independent evidence review required' if code == 0
          else 'Resolver diagnostic refused; no retry authority')
    return code


if __name__ == '__main__':
    sys.exit(main())

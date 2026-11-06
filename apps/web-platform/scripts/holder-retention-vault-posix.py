"""Disposable POSIX fixture experiment, NOT a receipt vault or authority.

It only writes one hard-coded synthetic value, provides no deletion operation,
and cannot establish identity, authorization, independent epoch, trusted time,
restoration safety, copy controls, or a deletion deadline. All participants and
the containing directory must be trusted; flock is advisory. A hostile process
with the same filesystem credentials can race path replacement after a check.
"""
import fcntl
import json
import os
import re
import stat
import threading


class Refused(Exception):
    pass


_FLAGS = os.O_NOFOLLOW | os.O_CLOEXEC
_FIXTURE = b'synthetic-vault-fixture\n'
_ID = re.compile(r'[a-z0-9][a-z0-9-]{0,63}\Z')


def _valid_id(value):
    return isinstance(value, str) and _ID.fullmatch(value) is not None


def _checked_file(directory, name, flags=os.O_RDONLY):
    fd = os.open(name, flags | _FLAGS, dir_fd=directory)
    try:
        s = os.fstat(fd)
        if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_nlink != 1 or stat.S_IMODE(s.st_mode) != 0o600:
            raise Refused('unsafe fixture file')
        return fd
    except BaseException:
        os.close(fd)
        raise


def _directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | _FLAGS)
    s = os.fstat(fd)
    if s.st_uid != os.geteuid() or stat.S_IMODE(s.st_mode) != 0o700:
        os.close(fd)
        raise Refused('unsafe fixture directory')
    return fd


def _write_all(fd, data):
    pos = 0
    while pos < len(data):
        count = os.write(fd, data[pos:])
        if count <= 0:
            raise Refused('short fixture write')
        pos += count
    os.fsync(fd)


class SyntheticPosixVault:
    @classmethod
    def initialize(cls, path, operation, generation):
        if not _valid_id(operation) or not _valid_id(generation):
            raise Refused('invalid identity')
        directory = _directory(path)
        try:
            if os.listdir(directory):
                raise Refused('directory is not empty')
            fd = os.open('lock', os.O_CREAT | os.O_EXCL | os.O_RDWR | _FLAGS, 0o600, dir_fd=directory)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
            fd = os.open('state', os.O_CREAT | os.O_EXCL | os.O_WRONLY | _FLAGS, 0o600, dir_fd=directory)
            try:
                _write_all(fd, cls._encode({'operation': operation, 'generation': generation,
                                           'phase': 'open', 'fixture': None}))
            finally:
                os.close(fd)
            os.fsync(directory)
        finally:
            os.close(directory)

    def __init__(self, path, operation, generation):
        if not _valid_id(operation) or not _valid_id(generation):
            raise Refused('invalid identity')
        self.directory = _directory(path)
        try:
            self.lock = _checked_file(self.directory, 'lock', os.O_RDWR)
        except BaseException:
            os.close(self.directory)
            raise
        self.operation = operation
        self.generation = generation
        self._thread_lock = threading.Lock()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        os.close(self.lock)
        os.close(self.directory)

    @staticmethod
    def _encode(state):
        return json.dumps(state, sort_keys=True, separators=(',', ':')).encode('ascii')

    def _assert_lock(self):
        current = os.stat('lock', dir_fd=self.directory, follow_symlinks=False)
        held = os.fstat(self.lock)
        if (not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or
                held.st_nlink != 1 or (current.st_dev, current.st_ino) != (held.st_dev, held.st_ino)):
            raise Refused('lock identity changed')

    def _read(self):
        names = set(os.listdir(self.directory))
        if not names.issubset({'lock', 'state', 'fixture'}) or not {'lock', 'state'}.issubset(names):
            raise Refused('unexpected fixture entry')
        fd = _checked_file(self.directory, 'state')
        try:
            raw = os.read(fd, 513)
        finally:
            os.close(fd)
        if len(raw) > 512:
            raise Refused('invalid state')
        try:
            state = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            raise Refused('invalid state') from None
        if (not isinstance(state, dict) or set(state) != {'operation', 'generation', 'phase', 'fixture'} or
                state['operation'] != self.operation or state['generation'] != self.generation or
                state['phase'] not in ('open', 'sealed', 'tombstoned') or
                self._encode(state) != raw):
            raise Refused('state mismatch')
        fixture = state['fixture']
        if fixture is None:
            if 'fixture' in names:
                raise Refused('unrecorded fixture')
        else:
            if (not isinstance(fixture, list) or len(fixture) != 2 or
                    any(type(value) is not int or value < 0 for value in fixture)):
                raise Refused('invalid fixture identity')
            fd = _checked_file(self.directory, 'fixture')
            try:
                s = os.fstat(fd)
                if [s.st_dev, s.st_ino] != fixture or os.read(fd, len(_FIXTURE) + 1) != _FIXTURE:
                    raise Refused('fixture changed')
            finally:
                os.close(fd)
        return state

    def _save(self, state):
        fd = os.open('state-next', os.O_CREAT | os.O_EXCL | os.O_WRONLY | _FLAGS, 0o600, dir_fd=self.directory)
        try:
            _write_all(fd, self._encode(state))
        finally:
            os.close(fd)
        os.rename('state-next', 'state', src_dir_fd=self.directory, dst_dir_fd=self.directory)
        os.fsync(self.directory)

    def _call(self, action):
        with self._thread_lock:
            return self._call_locked(action)

    def _call_locked(self, action):
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX)
            self._assert_lock()
            state = self._read()
            if action == 'status':
                return state['phase']
            if action == 'write_fixture':
                if state['phase'] != 'open' or state['fixture'] is not None:
                    raise Refused('fixture not writable')
                fd = os.open('fixture', os.O_CREAT | os.O_EXCL | os.O_WRONLY | _FLAGS, 0o600, dir_fd=self.directory)
                try:
                    _write_all(fd, _FIXTURE)
                    s = os.fstat(fd)
                    state['fixture'] = [s.st_dev, s.st_ino]
                finally:
                    os.close(fd)
            elif action == 'seal' and state['phase'] == 'open':
                state['phase'] = 'sealed'
            elif action == 'tombstone' and state['phase'] == 'sealed':
                state['phase'] = 'tombstoned'
            else:
                raise Refused('transition refused')
            self._save(state)
        except (OSError, ValueError, TypeError):
            raise Refused('fixture operation unavailable') from None
        finally:
            fcntl.flock(self.lock, fcntl.LOCK_UN)

    def status(self):
        return self._call('status')

    def write_fixture(self):
        return self._call('write_fixture')

    def seal(self):
        return self._call('seal')

    def tombstone(self):
        return self._call('tombstone')

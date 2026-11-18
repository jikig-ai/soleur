"""Unwired bounded receipt-store candidate; no deletion or authorization.

The directory descriptor and injected authority, epoch, reservation and clock
are assertions, not independently authenticated controls. Exact callback echoes
do not prove durable storage, readback or fencing. Advisory flock requires cooperation;
a hostile same-UID process can replace paths after checks. Restored files can
roll back state and tombstones. Interrupted writes may leave orphan entries and
block further work; they are not automatically deleted. File I/O and injected
callbacks may block or cross deadlines; post-checks do not undo written bytes.
This is not evidence of durable erasure, isolation, or retention compliance.
"""
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import threading

class Refused(Exception):
    pass

_FLAGS = os.O_NOFOLLOW | os.O_CLOEXEC
_ID = re.compile(r'[0-9a-f]{32}\Z')
_LIMIT = 65536

def _identity(value):
    return type(value) is str and _ID.fullmatch(value) is not None

def _directory(fd):
    if type(fd) is not int:
        raise Refused('refused')
    fd = os.dup(fd)
    try:
        s = os.fstat(fd)
        if not stat.S_ISDIR(s.st_mode) or s.st_uid != os.geteuid() or stat.S_IMODE(s.st_mode) != 0o700:
            raise Refused('refused')
        return fd
    except BaseException:
        os.close(fd)
        raise

def _file(directory, name, flags=os.O_RDONLY):
    fd = os.open(name, flags | _FLAGS, dir_fd=directory)
    try:
        s = os.fstat(fd)
        if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_nlink != 1 or stat.S_IMODE(s.st_mode) != 0o600:
            raise Refused('refused')
        return fd
    except BaseException:
        os.close(fd)
        raise

def _encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode('ascii')

def _write(fd, data):
    offset = 0
    while offset < len(data):
        n = os.write(fd, data[offset:])
        if n <= 0: raise Refused('refused')
        offset += n
    os.fsync(fd)

class ReceiptStore:
    @classmethod
    def initialize(cls, directory_fd, operation, generation, capture_start_ms, deadline_ms):
        if (not _identity(operation) or not _identity(generation) or type(capture_start_ms) is not int or
            type(deadline_ms) is not int or capture_start_ms < 0 or deadline_ms <= capture_start_ms or
            deadline_ms - capture_start_ms > 86400000): raise Refused('refused')
        directory = _directory(directory_fd)
        try:
            if os.listdir(directory): raise Refused('refused')
            fd = os.open('lock', os.O_CREAT | os.O_EXCL | os.O_RDWR | _FLAGS, 0o600, dir_fd=directory)
            try: os.fsync(fd)
            finally: os.close(fd)
            state = {'operation': operation, 'generation': generation, 'start': capture_start_ms,
                     'deadline': deadline_ms, 'phase': 'open', 'receipt': None}
            fd = os.open('state', os.O_CREAT | os.O_EXCL | os.O_WRONLY | _FLAGS, 0o600, dir_fd=directory)
            try: _write(fd, _encode(state))
            finally: os.close(fd)
            os.fsync(directory)
        except (OSError, ValueError, TypeError): raise Refused('refused') from None
        finally: os.close(directory)

    def __init__(self, directory_fd, operation, generation, *, authority=None, clock=None, epoch=None, reservation=None):
        if not _identity(operation) or not _identity(generation): raise Refused('refused')
        self.directory = _directory(directory_fd)
        try: self.lock = _file(self.directory, 'lock', os.O_RDWR)
        except BaseException:
            os.close(self.directory); raise
        self.operation, self.generation = operation, generation
        self.authority, self.clock, self.epoch = authority, clock, epoch
        self.reservation = reservation
        self.thread_lock = threading.Lock()

    def __enter__(self): return self
    def __exit__(self, *_): os.close(self.lock); os.close(self.directory)

    def _check_lock(self):
        held = os.fstat(self.lock); current = os.stat('lock', dir_fd=self.directory, follow_symlinks=False)
        if (not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or held.st_nlink != 1 or
            (held.st_dev, held.st_ino) != (current.st_dev, current.st_ino)): raise Refused('refused')

    def _read(self):
        names = set(os.listdir(self.directory))
        if not {'lock', 'state'}.issubset(names) or not names.issubset({'lock', 'state', 'receipt', 'reservation-pending'}): raise Refused('refused')
        fd = _file(self.directory, 'state')
        try: raw = os.read(fd, 2049)
        finally: os.close(fd)
        if len(raw) > 2048: raise Refused('refused')
        state = json.loads(raw)
        if (type(state) is not dict or set(state) != {'operation','generation','start','deadline','phase','receipt'} or
            _encode(state) != raw or state['operation'] != self.operation or state['generation'] != self.generation or
            type(state['start']) is not int or type(state['deadline']) is not int or state['start'] < 0 or
            not 0 < state['deadline'] - state['start'] <= 86400000 or state['phase'] not in ('open','sealed','tombstoned')): raise Refused('refused')
        receipt = state['receipt']
        bound_epoch = None
        if receipt is None:
            if 'receipt' in names or 'reservation-pending' in names: raise Refused('refused')
        else:
            if (type(receipt) is not dict or set(receipt) != {'device','inode','size','sha256','reservation_sha256'} or
                any(type(receipt[k]) is not int or receipt[k] < 0 for k in ('device','inode','size')) or
                not 0 < receipt['size'] <= _LIMIT or type(receipt['sha256']) is not str or
                not re.fullmatch(r'[0-9a-f]{64}', receipt['sha256']) or type(receipt['reservation_sha256']) is not str or
                not re.fullmatch(r'[0-9a-f]{64}', receipt['reservation_sha256'])): raise Refused('refused')
            fd = _file(self.directory, 'reservation-pending')
            try: pending = os.read(fd, 2049)
            finally: os.close(fd)
            if len(pending) > 2048 or hashlib.sha256(pending).hexdigest() != receipt['reservation_sha256']: raise Refused('refused')
            reservation = json.loads(pending)
            vault = os.fstat(self.directory)
            if (type(reservation) is not dict or set(reservation) != {'operation','generation','epoch','entry','nonce','vault_device','vault_inode','start','deadline'} or
                _encode(reservation) != pending or reservation['operation'] != self.operation or reservation['generation'] != self.generation or
                reservation['entry'] != 'receipt' or not _identity(reservation['nonce']) or
                type(reservation['epoch']) is not int or not 0 <= reservation['epoch'] <= 2**63 - 1 or
                type(reservation['vault_device']) is not int or type(reservation['vault_inode']) is not int or
                (reservation['vault_device'], reservation['vault_inode']) != (vault.st_dev, vault.st_ino) or
                reservation['start'] != state['start'] or reservation['deadline'] != state['deadline']): raise Refused('refused')
            bound_epoch = reservation['epoch']
            fd = _file(self.directory, 'receipt')
            try:
                s = os.fstat(fd); data = os.read(fd, _LIMIT + 1)
                if (s.st_dev != receipt['device'] or s.st_ino != receipt['inode'] or
                    len(data) != receipt['size'] or hashlib.sha256(data).hexdigest() != receipt['sha256']): raise Refused('refused')
            finally: os.close(fd)
        return state, bound_epoch

    def _gate(self, action, state, *, writable=False, expected_epoch=None):
        if (not callable(self.authority) or not callable(self.clock) or not callable(self.epoch) or
            self.authority(action, self.operation, self.generation) is not True): raise Refused('refused')
        epoch = self.epoch(self.operation, self.generation)
        if type(epoch) is not int or not 0 <= epoch <= 2**63 - 1 or (expected_epoch is not None and epoch != expected_epoch): raise Refused('refused')
        sample = self.clock()
        if (type(sample) is not tuple or len(sample) != 2 or any(type(v) is not int for v in sample) or
            sample[0] < 0 or sample[1] < sample[0] or sample[1] - sample[0] > 5000 or
            (writable and (sample[0] < state['start'] or sample[1] >= state['deadline']))): raise Refused('refused')
        return epoch

    def _empty_receipt(self, fd, expected):
        held = os.fstat(fd)
        named = os.stat('receipt', dir_fd=self.directory, follow_symlinks=False)
        if (not stat.S_ISREG(held.st_mode) or not stat.S_ISREG(named.st_mode) or
            held.st_uid != os.geteuid() or named.st_uid != os.geteuid() or
            stat.S_IMODE(held.st_mode) != 0o600 or stat.S_IMODE(named.st_mode) != 0o600 or
            held.st_nlink != 1 or named.st_nlink != 1 or held.st_size != 0 or named.st_size != 0 or
            (held.st_dev, held.st_ino) != expected or (named.st_dev, named.st_ino) != expected): raise Refused('refused')

    def _check_pending(self, fd, content):
        held = os.fstat(fd); named = os.stat('reservation-pending', dir_fd=self.directory, follow_symlinks=False)
        if (not stat.S_ISREG(held.st_mode) or not stat.S_ISREG(named.st_mode) or
            held.st_uid != os.geteuid() or named.st_uid != os.geteuid() or held.st_nlink != 1 or named.st_nlink != 1 or
            stat.S_IMODE(held.st_mode) != 0o600 or stat.S_IMODE(named.st_mode) != 0o600 or
            (held.st_dev, held.st_ino) != (named.st_dev, named.st_ino) or os.pread(fd, 2049, 0) != content): raise Refused('refused')

    def _check_written(self, fd, receipt):
        held = os.fstat(fd); named = os.stat('receipt', dir_fd=self.directory, follow_symlinks=False)
        if (not stat.S_ISREG(held.st_mode) or not stat.S_ISREG(named.st_mode) or
            held.st_uid != os.geteuid() or named.st_uid != os.geteuid() or held.st_nlink != 1 or named.st_nlink != 1 or
            stat.S_IMODE(held.st_mode) != 0o600 or stat.S_IMODE(named.st_mode) != 0o600 or
            (held.st_dev, held.st_ino) != (receipt['device'], receipt['inode']) or
            (named.st_dev, named.st_ino) != (receipt['device'], receipt['inode']) or
            held.st_size != receipt['size'] or named.st_size != receipt['size'] or
            hashlib.sha256(os.pread(fd, _LIMIT + 1, 0)).hexdigest() != receipt['sha256']): raise Refused('refused')

    def _save(self, state):
        fd = os.open('state-next', os.O_CREAT | os.O_EXCL | os.O_WRONLY | _FLAGS, 0o600, dir_fd=self.directory)
        try: _write(fd, _encode(state))
        finally: os.close(fd)
        os.rename('state-next', 'state', src_dir_fd=self.directory, dst_dir_fd=self.directory)
        os.fsync(self.directory)

    def _call(self, action, data=None):
        if not self.thread_lock.acquire(blocking=False): raise Refused('refused')
        locked = False
        pending_fd = None
        receipt_fd = None
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB); locked = True
            self._check_lock(); state, bound_epoch = self._read(); epoch = self._gate(action, state, writable=action == 'write', expected_epoch=bound_epoch)
            if action == 'status': return state['phase']
            if action == 'write':
                if state['phase'] != 'open' or state['receipt'] is not None or type(data) is not bytes or not 0 < len(data) <= _LIMIT: raise Refused('refused')
                if self.reservation is None: raise Refused('refused')
                vault = os.fstat(self.directory)
                reservation = {'operation': self.operation, 'generation': self.generation, 'epoch': epoch,
                               'entry': 'receipt', 'nonce': secrets.token_hex(16),
                               'vault_device': vault.st_dev, 'vault_inode': vault.st_ino,
                               'start': state['start'], 'deadline': state['deadline']}
                reserve_request = _encode(reservation)
                # Persist the exact attempt before contacting the authority. A
                # crash or ambiguous response leaves this marker and blocks all
                # operations; no retry generates another nonce automatically.
                pending_fd = os.open('reservation-pending', os.O_CREAT | os.O_EXCL | os.O_RDWR | _FLAGS, 0o600, dir_fd=self.directory)
                _write(pending_fd, reserve_request)
                os.fsync(self.directory)
                self._check_lock(); self._gate(action, state, writable=True, expected_epoch=epoch)
                self._check_pending(pending_fd, reserve_request)
                confirmation = self.reservation.reserve(reserve_request)
                if type(confirmation) is not bytes or confirmation != reserve_request: raise Refused('refused')
                self._check_lock(); self._gate(action, state, writable=True, expected_epoch=epoch)
                receipt_fd = os.open('receipt', os.O_CREAT | os.O_EXCL | os.O_RDWR | _FLAGS, 0o600, dir_fd=self.directory)
                s = os.fstat(receipt_fd); expected = (s.st_dev, s.st_ino)
                self._empty_receipt(receipt_fd, expected)
                os.fsync(receipt_fd); os.fsync(self.directory)
                binding = _encode({**reservation, 'receipt_device': s.st_dev, 'receipt_inode': s.st_ino})
                confirmation = self.reservation.bind(binding)
                if type(confirmation) is not bytes or confirmation != binding: raise Refused('refused')
                confirmation = self.reservation.verify(binding)
                if type(confirmation) is not bytes or confirmation != binding: raise Refused('refused')
                self._check_lock(); self._gate(action, state, writable=True, expected_epoch=epoch)
                self._check_pending(pending_fd, reserve_request)
                self._empty_receipt(receipt_fd, expected)
                _write(receipt_fd, data); s = os.fstat(receipt_fd)
                state['receipt'] = {'device': s.st_dev, 'inode': s.st_ino, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                                    'reservation_sha256': hashlib.sha256(reserve_request).hexdigest()}
                os.fsync(self.directory)
                self._check_lock(); self._gate(action, state, writable=True, expected_epoch=epoch)
            elif action == 'seal' and state['phase'] == 'open': state['phase'] = 'sealed'
            elif action == 'tombstone' and state['phase'] == 'sealed': state['phase'] = 'tombstoned'
            else: raise Refused('refused')
            self._check_lock(); self._gate(action, state, writable=action == 'write', expected_epoch=epoch)
            if action == 'write':
                self._check_pending(pending_fd, reserve_request)
                self._check_written(receipt_fd, state['receipt'])
            self._save(state)
        except Exception: raise Refused('refused') from None
        finally:
            if receipt_fd is not None:
                try: os.close(receipt_fd)
                except OSError: pass
            if pending_fd is not None:
                try: os.close(pending_fd)
                except OSError: pass
            if locked:
                try: fcntl.flock(self.lock, fcntl.LOCK_UN)
                except OSError: pass
            self.thread_lock.release()

    def status(self): return self._call('status')
    def write(self, data): return self._call('write', data)
    def seal(self): return self._call('seal')
    def tombstone(self): return self._call('tombstone')
    def delete(self): raise Refused('refused')

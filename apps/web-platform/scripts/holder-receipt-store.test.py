import importlib.util
import json
import os
import select
import stat
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('receipt_store', os.path.join(os.path.dirname(__file__), 'holder-receipt-store.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); os.chmod(self.temp.name, 0o700)
        self.directory = os.open(self.temp.name, os.O_RDONLY | os.O_DIRECTORY)
        module.ReceiptStore.initialize(self.directory, 'a' * 32, 'b' * 32, 100, 200)
        self.clock = lambda: (100, 101)
        self.authority = lambda action, op, gen: True
        self.epoch = lambda op, gen: 7
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): return value
            def verify(self, value): return value
        self.binding = Binding()
    def tearDown(self):
        os.close(self.directory); self.temp.cleanup()
    def store(self, **kw):
        opts = dict(authority=self.authority, clock=self.clock, epoch=self.epoch, reservation=self.binding); opts.update(kw)
        return module.ReceiptStore(self.directory, 'a' * 32, 'b' * 32, **opts)
    def test_default_refusal_and_bounded_write_seal_tombstone(self):
        with module.ReceiptStore(self.directory, 'a' * 32, 'b' * 32) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        with self.store() as s:
            with self.assertRaises(module.Refused): s.write(b'x' * 65537)
            s.write(b'synthetic-receipt')
            s.seal()
            with self.assertRaises(module.Refused): s.write(b'again')
            s.tombstone()
            with self.assertRaises(module.Refused): s.write(b'again')
            with self.assertRaises(module.Refused): s.delete()
        with self.store() as s: self.assertEqual(s.status(), 'tombstoned')
    def test_authority_false_refuses(self):
        with self.store(authority=lambda *_: False) as s:
            with self.assertRaises(module.Refused): s.write(b'x')
    def test_seal_empty_store_refuses_first_write(self):
        with self.store() as s:
            s.seal()
            with self.assertRaises(module.Refused): s.write(b'x')
    def test_expired_rejected_and_identity_epoch_checked(self):
        with self.store(clock=lambda: (199, 200)) as s:
            with self.assertRaises(module.Refused): s.write(b'x')
        with self.store(epoch=lambda *_: False) as s:
            with self.assertRaises(module.Refused): s.write(b'x')
        with self.assertRaises(module.Refused):
            with module.ReceiptStore(self.directory, 'a'*32, 'c'*32, authority=self.authority, clock=self.clock, epoch=self.epoch) as s: s.write(b'x')
    def test_unexpected_symlink_and_interrupted_state_refuse(self):
        os.symlink('/etc/passwd', 'receipt', dir_fd=self.directory)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.write(b'x')
        os.unlink('receipt', dir_fd=self.directory)
        fd = os.open('state-next', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600, dir_fd=self.directory); os.close(fd)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.write(b'x')
    def test_exclusive_lock_refuses_competing_writer(self):
        import fcntl
        fd = os.open('lock', os.O_RDWR, dir_fd=self.directory)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.store() as s:
                with self.assertRaises(module.Refused): s.write(b'x')
        finally:
            os.close(fd)

    def test_clock_crossing_after_write_leaves_orphan_and_blocks_operations(self):
        def crossing():
            try: size = os.stat('receipt', dir_fd=self.directory).st_size
            except FileNotFoundError: size = 0
            return (199, 200) if size else (100, 101)
        with self.store(clock=crossing) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic-orphan')
        fd = os.open('receipt', os.O_RDONLY, dir_fd=self.directory)
        try: self.assertEqual(os.read(fd, 100), b'synthetic-orphan')
        finally: os.close(fd)
        fd = os.open('state', os.O_RDONLY, dir_fd=self.directory)
        try: self.assertIsNone(json.loads(os.read(fd, 2048))['receipt'])
        finally: os.close(fd)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.status()
            with self.assertRaises(module.Refused): s.seal()
            with self.assertRaises(module.Refused): s.delete()

    def test_hardlinked_receipt_refuses_even_when_bytes_match(self):
        with self.store() as s: s.write(b'synthetic-receipt')
        with tempfile.TemporaryDirectory() as elsewhere:
            alias = os.path.join(elsewhere, 'alias')
            os.link('receipt', alias, src_dir_fd=self.directory, follow_symlinks=False)
            self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_nlink, 2)
            with self.store() as s:
                with self.assertRaises(module.Refused): s.status()
                with self.assertRaises(module.Refused): s.seal()

    def test_tampered_receipt_refuses_even_when_inode_and_size_match(self):
        with self.store() as s: s.write(b'original')
        fd = os.open('receipt', os.O_WRONLY, dir_fd=self.directory)
        try: self.assertEqual(os.write(fd, b'modified'), 8)
        finally: os.close(fd)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.status()
            with self.assertRaises(module.Refused): s.tombstone()

    def test_competing_process_holds_the_actual_lock_file(self):
        child_code = ('import fcntl,os,sys; '
                      'f=os.open(sys.argv[1],os.O_RDWR); '
                      'fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB); '
                      'print("locked",flush=True); sys.stdin.readline(); os.close(f)')
        child = subprocess.Popen([sys.executable, '-c', child_code, os.path.join(self.temp.name, 'lock')],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertTrue(select.select([child.stdout], [], [], 5)[0], 'child did not lock')
            self.assertEqual(child.stdout.readline().strip(), 'locked')
            with self.store() as s:
                with self.assertRaises(module.Refused): s.write(b'synthetic')
            self.assertNotIn('receipt', os.listdir(self.directory))
        finally:
            if child.stdin: child.stdin.write('\n'); child.stdin.flush()
            child.communicate(timeout=5)
        self.assertEqual(child.returncode, 0)


    def test_reservation_refusal_and_ambiguous_binding_never_write_bytes(self):
        with self.store(reservation=None) as s:
            with self.assertRaises(module.Refused): s.write(b'secret-synthetic')
        self.assertNotIn('receipt', os.listdir(self.directory))
        class RejectReservation:
            def reserve(self, value): return None
            def bind(self, value): raise AssertionError('must not bind')
            def verify(self, value): raise AssertionError('must not verify')
        with self.store(reservation=RejectReservation()) as s:
            with self.assertRaises(module.Refused): s.write(b'secret-synthetic')
        self.assertNotIn('receipt', os.listdir(self.directory))
    def test_ambiguous_binding_leaves_empty_entry(self):
        class LostBinding:
            def reserve(self, value): return value
            def bind(self, value): raise TimeoutError('lost response')
            def verify(self, value): raise AssertionError('must not adopt')
        with self.store(reservation=LostBinding()) as s:
            with self.assertRaises(module.Refused): s.write(b'secret-synthetic')
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.status()

    def test_exact_binding_and_fresh_epoch_are_required_before_bytes(self):
        class WrongBinding:
            def reserve(self, value): return value
            def bind(self, value): return value
            def verify(self, value): return value + b'changed'
        with self.store(reservation=WrongBinding()) as s:
            with self.assertRaises(module.Refused): s.write(b'secret-synthetic')
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)

    def test_wrong_bind_ack_refuses_without_verification(self):
        called = []
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): return value + b'changed'
            def verify(self, value): called.append(True); return value
        with self.store(reservation=Binding()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertEqual(called, [])
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)

    def test_changed_empty_inode_before_write_is_refused(self):
        directory = self.directory
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): return value
            def verify(self, value):
                fd = os.open('receipt', os.O_WRONLY, dir_fd=directory)
                try: os.write(fd, b'x')
                finally: os.close(fd)
                return value
        with self.store(reservation=Binding()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        fd = os.open('receipt', os.O_RDONLY, dir_fd=self.directory)
        try: self.assertEqual(os.read(fd, 20), b'x')
        finally: os.close(fd)

    def test_reservation_marker_removed_during_verify_refuses_before_bytes(self):
        directory = self.directory
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): return value
            def verify(self, value): os.unlink('reservation-pending', dir_fd=directory); return value
        with self.store(reservation=Binding()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)

    def test_reservation_marker_replaced_during_verify_refuses_before_bytes(self):
        directory = self.directory
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): return value
            def verify(self, value):
                old = os.open('reservation-pending', os.O_RDONLY, dir_fd=directory)
                try:
                    content = os.read(old, 2049)
                    os.unlink('reservation-pending', dir_fd=directory)
                    fd = os.open('reservation-pending', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600, dir_fd=directory)
                    try: os.write(fd, content)
                    finally: os.close(fd)
                finally: os.close(old)
                return value
        with self.store(reservation=Binding()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)

    def test_marker_removed_after_write_prevents_publication(self):
        def clock():
            try:
                if os.stat('receipt', dir_fd=self.directory).st_size:
                    os.unlink('reservation-pending', dir_fd=self.directory)
            except FileNotFoundError: pass
            return (100, 101)
        with self.store(clock=clock) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        fd = os.open('state', os.O_RDONLY, dir_fd=self.directory)
        try: self.assertIsNone(json.loads(os.read(fd, 2048))['receipt'])
        finally: os.close(fd)

    def test_receipt_replaced_after_write_prevents_publication(self):
        changed = False
        def clock():
            nonlocal changed
            try:
                if not changed and os.stat('receipt', dir_fd=self.directory).st_size:
                    changed = True
                    os.rename('receipt', 'old-receipt', src_dir_fd=self.directory, dst_dir_fd=self.directory)
                    fd = os.open('receipt', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600, dir_fd=self.directory)
                    try: os.write(fd, b'synthetic')
                    finally: os.close(fd)
            except FileNotFoundError: pass
            return (100, 101)
        with self.store(clock=clock) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertTrue(changed)
        fd = os.open('state', os.O_RDONLY, dir_fd=self.directory)
        try: self.assertIsNone(json.loads(os.read(fd, 2048))['receipt'])
        finally: os.close(fd)

    def test_binding_is_for_exact_empty_synced_inode_and_current_epoch(self):
        events = []
        original_fsync = os.fsync
        def traced_fsync(fd):
            info = os.fstat(fd)
            events.append(('dir' if stat.S_ISDIR(info.st_mode) else 'file', info.st_dev, info.st_ino))
            return original_fsync(fd)
        class Binding:
            def reserve(inner, value):
                data = json.loads(value); self.assertEqual(data['operation'], 'a' * 32); self.assertEqual(data['generation'], 'b' * 32)
                self.assertEqual(data['epoch'], 7); self.assertEqual(data['entry'], 'receipt'); self.assertRegex(data['nonce'], r'^[0-9a-f]{32}$')
                self.assertNotIn('receipt', os.listdir(self.directory)); return value
            def bind(inner, value):
                data = json.loads(value); receipt = os.stat('receipt', dir_fd=self.directory); directory = os.fstat(self.directory)
                self.assertEqual(receipt.st_size, 0); self.assertEqual((data['receipt_device'], data['receipt_inode']), (receipt.st_dev, receipt.st_ino))
                self.assertIn(('file', receipt.st_dev, receipt.st_ino), events)
                file_index = events.index(('file', receipt.st_dev, receipt.st_ino))
                self.assertIn(('dir', directory.st_dev, directory.st_ino), events[file_index + 1:])
                return value
            def verify(inner, value):
                self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0); return value
        os.fsync = traced_fsync
        try:
            with self.store(reservation=Binding()) as s: s.write(b'synthetic')
        finally: os.fsync = original_fsync

    def test_epoch_change_during_binding_blocks_first_byte(self):
        epoch = [7]
        class Binding:
            def reserve(self, value): return value
            def bind(self, value): epoch[0] = 8; return value
            def verify(self, value): return value
        with self.store(reservation=Binding(), epoch=lambda *_: epoch[0]) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)

    def test_reopen_requires_exact_reservation_epoch_before_any_operation(self):
        with self.store() as s: s.write(b'synthetic')
        for epoch in (6, 8):
            with self.store(epoch=lambda *_, value=epoch: value) as s:
                with self.assertRaises(module.Refused): s.status()
                with self.assertRaises(module.Refused): s.seal()
        with self.store() as s:
            self.assertEqual(s.status(), 'open'); s.seal()
        for epoch in (6, 8):
            with self.store(epoch=lambda *_, value=epoch: value) as s:
                with self.assertRaises(module.Refused): s.status()
                with self.assertRaises(module.Refused): s.tombstone()
        with self.store() as s: self.assertEqual(s.status(), 'sealed')

    def test_forged_equality_does_not_confirm_reservation(self):
        class Forged:
            def __eq__(self, other): return True
        class Binding:
            def reserve(self, value): return Forged()
        with self.store(reservation=Binding()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertNotIn('receipt', os.listdir(self.directory))

    def test_process_interruption_during_binding_leaves_empty_inode(self):
        child_code = """
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location('store',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class B:
 def reserve(self,x): return x
 def bind(self,x): os._exit(77)
 def verify(self,x): return x
d=os.open(sys.argv[2],os.O_RDONLY|os.O_DIRECTORY)
with m.ReceiptStore(d,'a'*32,'b'*32,authority=lambda *_:True,clock=lambda:(100,101),epoch=lambda *_:7,reservation=B()) as s: s.write(b'synthetic')
"""
        result = subprocess.run([sys.executable, '-c', child_code, spec.origin, self.temp.name], timeout=5, capture_output=True)
        self.assertEqual(result.returncode, 77)
        self.assertEqual(os.stat('receipt', dir_fd=self.directory).st_size, 0)
        with self.store() as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')


    def test_lost_reservation_ack_blocks_every_retry(self):
        calls = []
        class Lost:
            def reserve(self, value): calls.append(value); return None
            def bind(self, value): raise AssertionError('must not bind')
            def verify(self, value): raise AssertionError('must not verify')
        with self.store(reservation=Lost()) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        with self.store(reservation=self.binding) as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')
        self.assertEqual(len(calls), 1)
        self.assertNotIn('receipt', os.listdir(self.directory))
        self.assertIn('reservation-pending', os.listdir(self.directory))

    def test_pending_marker_is_synced_and_matches_request_before_contact(self):
        events = []
        original = os.fsync
        def traced(fd):
            info = os.fstat(fd)
            events.append(('dir' if stat.S_ISDIR(info.st_mode) else 'file', info.st_dev, info.st_ino))
            return original(fd)
        directory = self.directory
        class Binding:
            def reserve(self, value):
                fd = os.open('reservation-pending', os.O_RDONLY, dir_fd=directory)
                try:
                    info = os.fstat(fd)
                    if os.read(fd, 2049) != value: raise AssertionError('different reservation')
                finally: os.close(fd)
                directory_stat = os.fstat(directory)
                file_index = events.index(('file', info.st_dev, info.st_ino))
                if ('dir', directory_stat.st_dev, directory_stat.st_ino) not in events[file_index + 1:]: raise AssertionError('directory not synced')
                return value
            def bind(self, value): return value
            def verify(self, value): return value
        os.fsync = traced
        try:
            with self.store(reservation=Binding()) as store: store.write(b'synthetic')
        finally: os.fsync = original

    def test_crash_during_reservation_blocks_retry(self):
        child_code = """
import importlib.util, os, sys
spec=importlib.util.spec_from_file_location('store',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class B:
 def reserve(self,x): os._exit(78)
 def bind(self,x): return x
 def verify(self,x): return x
d=os.open(sys.argv[2],os.O_RDONLY|os.O_DIRECTORY)
with m.ReceiptStore(d,'a'*32,'b'*32,authority=lambda *_:True,clock=lambda:(100,101),epoch=lambda *_:7,reservation=B()) as s: s.write(b'synthetic')
"""
        result = subprocess.run([sys.executable, '-c', child_code, spec.origin, self.temp.name], timeout=5, capture_output=True)
        self.assertEqual(result.returncode, 78)
        self.assertNotIn('receipt', os.listdir(self.directory))
        with self.store() as s:
            with self.assertRaises(module.Refused): s.write(b'synthetic')

if __name__ == '__main__': unittest.main()

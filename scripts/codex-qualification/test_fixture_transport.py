"""Test early EOF and bounds in the real fixture receive helper without sockets."""
import unittest
from fixture_transport import receive_until

class SocketFixture:
    def __init__(self, chunks): self.chunks = iter(chunks)
    def settimeout(self, seconds): pass
    def recv(self, count): return next(self.chunks, b'')

class ReceiveBounds(unittest.TestCase):
    def test_early_eof_fails(self):
        with self.assertRaises(EOFError):
            receive_until(SocketFixture([b'partial', b'']), b'sentinel')
    def test_matching_stream_succeeds(self):
        self.assertEqual(receive_until(SocketFixture([b'head:', b'sentinel']), b'sentinel'), b'head:sentinel')
    def test_oversized_stream_fails(self):
        with self.assertRaises(ValueError):
            receive_until(SocketFixture([b'a' * 70000]), b'sentinel')

if __name__ == '__main__': unittest.main()

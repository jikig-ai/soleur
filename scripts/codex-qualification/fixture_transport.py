"""Bounded receive for the synthetic Unix transport fixtures only."""
import time

def receive_until(sock, sentinel):
    deadline = time.monotonic() + 5
    result = b''
    while sentinel not in result:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Synthetic transport sentinel deadline exhausted')
        sock.settimeout(remaining)
        chunk = sock.recv(4096)
        if not chunk:
            raise EOFError('Synthetic transport closed before sentinel')
        result += chunk
        if len(result) > 65536:
            raise ValueError('Synthetic transport header/marker exceeds bound')
    return result

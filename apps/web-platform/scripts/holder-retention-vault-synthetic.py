"""In-memory serialization experiment. Never grants capture or deletion.

No network, filesystem, receipt bytes, identity verification, trusted clock,
durable tombstone or interprocess lock is implemented here. Injected callbacks
are test claims, not independent evidence. This experiment is not a vault.
Authority may be revoked between the check and the simulated mutation; no
epoch, enforceable lease or revocation-latency bound is implemented.
"""
import threading


class SyntheticVault:
    def __init__(self, operation, generation, deadline, clock, authority, capture_stopped):
        if (not isinstance(operation, str) or not operation or
                not isinstance(generation, str) or not generation or
                type(deadline) is not int or deadline < 0 or
                not callable(clock) or not callable(authority) or not callable(capture_stopped)):
            raise ValueError('invalid synthetic configuration')
        self.operation = operation
        self.generation = generation
        self.deadline = deadline
        self.clock = clock
        self.authority = authority
        self.capture_stopped = capture_stopped
        self._lock = threading.Lock()
        self._last_time = -1
        self._sealed = False
        self.write_count = 0

    def _time(self):
        now = self.clock()
        if type(now) is not int or now < 0 or now < self._last_time:
            return None
        self._last_time = now
        return now

    def _mutate(self, operation, generation, write):
        with self._lock:
            try:
                if self._sealed or operation != self.operation or generation != self.generation:
                    return False
                before = self._time()
                if before is None or self.authority(operation, generation) is not True:
                    return False
                if not write and self.capture_stopped() is not True:
                    return False
                after = self._time()
                if after is None or (write and after >= self.deadline):
                    return False
                if write:
                    self.write_count += 1
                else:
                    self._sealed = True
                return True
            except Exception:
                return False

    def write(self, operation, generation):
        return self._mutate(operation, generation, True)

    def seal(self, operation, generation):
        return self._mutate(operation, generation, False)

"""Pure offline race state machine over injected identities and observations.

Recipes are data, never execution authority. A future independently reviewed
adapter must obtain exact source hashes and session birth observations itself.
This module establishes no runtime evidence and consumes no approval.
"""
from dataclasses import dataclass
import math
import re

from prepare import Refused, canonical, require, sha

SCENARIOS = ('40_race_holder.sql', '41_race_waiter.sql',
             '42_race_observe.sql', '43_race_assert.sql')
RACE_SECONDS = 30
CLEANUP_SECONDS = 300
MAX_OBSERVATIONS = 256


@dataclass(frozen=True)
class ScenarioBinding:
    source_sha: str
    entries: tuple

    def __post_init__(self):
        require(isinstance(self.source_sha, str) and
                re.fullmatch(r'[0-9a-f]{40}', self.source_sha), 'Exact source SHA required')
        require(isinstance(self.entries, tuple) and len(self.entries) == len(SCENARIOS),
                'Complete immutable scenario binding required')
        for name, entry in zip(SCENARIOS, self.entries):
            require(isinstance(entry, tuple) and len(entry) == 3,
                    'Immutable scenario entry required')
            actual_name, fingerprint, body = entry
            require(actual_name == name and isinstance(body, bytes) and body and
                    sha(body) == fingerprint, 'Source-bound scenario bytes differ')
            try:
                body.decode('utf-8')
            except UnicodeError:
                raise Refused('Scenario must contain UTF-8 SQL') from None

    def scenario_hash(self, name):
        require(name in SCENARIOS, 'Unknown race scenario')
        return self.entries[SCENARIOS.index(name)][1]

    @property
    def fingerprint(self):
        return sha(canonical({'source_sha': self.source_sha,
                              'scenarios': {name: digest for name, digest, _ in self.entries}}))


def bind_scenarios(source_sha, bodies, expected_source_sha, expected_hashes):
    """Bind injected source bytes to a separately supplied source-hash census.

    The expected census is a trust input, not a runtime or Git attestation.
    Neither filesystem nor Git is read here; callers must retain its provenance.
    """
    require(source_sha == expected_source_sha, 'Source scenario identity differs')
    require(isinstance(bodies, dict) and set(bodies) == set(SCENARIOS) and
            isinstance(expected_hashes, dict) and set(expected_hashes) == set(SCENARIOS),
            'Exact 40-43 scenario byte and hash census required')
    for name in SCENARIOS:
        require(isinstance(bodies[name], bytes) and
                isinstance(expected_hashes[name], str) and
                re.fullmatch(r'[0-9a-f]{64}', expected_hashes[name]) and
                sha(bodies[name]) == expected_hashes[name], 'Source-bound scenario bytes differ')
    return ScenarioBinding(source_sha, tuple((name, expected_hashes[name], bodies[name])
                                             for name in SCENARIOS))


@dataclass(frozen=True)
class SessionIdentity:
    attempt: str
    database: str
    backend_pid: int
    backend_birth: str
    process_pid: int
    process_birth: str
    session_id: str


def _token(value):
    return isinstance(value, str) and 0 < len(value) <= 256 and not any(
        ord(char) < 32 or ord(char) in (127, 0x2028, 0x2029) for char in value)


def _instant(value):
    try:
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    except (OverflowError, ValueError):
        return False


def _zero(value):
    return type(value) is int and value == 0


class RaceController:
    """Bounded transitions; injected monotonic clock, no polling or sleeping.

    Register owned holder and waiter with their scenario hashes, observe the
    exact lock dependency, emit one commit recipe, observe the holder's COMMIT,
    observe waiter exit zero, then observe scenario 43 exit zero. Any terminal
    fault disables commit and success and retains rollback/close recipes for
    the previously registered identities. No recipe reopens any transport.
    """
    def __init__(self, attempt, database, binding, clock):
        require(_token(attempt) and _token(database), 'Attempt and database identity required')
        require(isinstance(binding, ScenarioBinding), 'Source-bound scenario binding required')
        require(callable(clock), 'Injected monotonic clock required')
        initial = clock()
        require(_instant(initial), 'Finite monotonic clock required')
        self._attempt = attempt
        self._database = database
        self._binding = binding
        self._clock = clock
        self._last_time = initial
        self._deadline = initial + RACE_SECONDS
        self._state = 'register-holder'
        self._sessions = {}
        self._primary_failure = None
        self._cleanup_deadline = None
        self._cleanup_expired = False
        self._closed = set()
        self._observations = 0

    @property
    def primary_failure(self):
        return self._primary_failure

    def _trip(self, message):
        if self._primary_failure is None:
            self._primary_failure = message
            self._cleanup_deadline = self._last_time + CLEANUP_SECONDS
        self._state = 'failed'
        raise Refused(self._primary_failure)

    def _check(self, condition, message):
        if not condition:
            self._trip(message)

    def _tick(self):
        try:
            instant = self._clock()
        except Exception:
            self._trip('Injected clock failed')
        self._check(_instant(instant) and instant >= self._last_time,
                    'Finite monotonic clock required')
        self._last_time = instant
        if self._state not in ('failed', 'succeeded'):
            self._check(instant < self._deadline, 'Race deadline expired')
        return instant

    def check_deadline(self):
        self._check(self._state != 'failed', 'Race already failed')
        self._tick()

    def _event(self, expected_state):
        self._check(self._state != 'failed', 'Race already failed')
        self._tick()
        self._observations += 1
        self._check(self._observations <= MAX_OBSERVATIONS, 'Race observation budget exhausted')
        self._check(self._state == expected_state, 'Race observation order differs')

    def _scenario(self, name, digest):
        self._check(digest == self._binding.scenario_hash(name), 'Source-bound scenario hash differs')

    def _identity(self, identity):
        self._check(isinstance(identity, SessionIdentity), 'Exact session identity required')
        self._check(identity.attempt == self._attempt and identity.database == self._database,
                    'Foreign attempt or database session refused')
        self._check(all(_token(value) for value in
                        (identity.backend_birth, identity.process_birth, identity.session_id)) and
                    type(identity.backend_pid) is int and identity.backend_pid > 0 and
                    type(identity.process_pid) is int and identity.process_pid > 0,
                    'Session PID and process/backend birth identities required')

    def _exact(self, role, identity):
        self._identity(identity)
        self._check(self._sessions.get(role) == identity, 'Foreign or reused PID session refused')

    def register_holder(self, identity, scenario_sha256):
        self._event('register-holder')
        self._scenario(SCENARIOS[0], scenario_sha256)
        self._identity(identity)
        self._sessions['holder'] = identity
        self._state = 'register-waiter'

    def register_waiter(self, identity, scenario_sha256):
        self._event('register-waiter')
        self._scenario(SCENARIOS[1], scenario_sha256)
        self._identity(identity)
        holder = self._sessions['holder']
        self._check(identity.backend_pid != holder.backend_pid and
                    identity.process_pid != holder.process_pid and
                    identity.session_id != holder.session_id, 'Distinct owned race sessions required')
        self._sessions['waiter'] = identity
        self._state = 'observe-blocking'

    def observe_blocking(self, *, holder, waiter, blockers, holder_state,
                         waiter_event_type, observer_exit_code, scenario_sha256):
        self._event('observe-blocking')
        self._scenario(SCENARIOS[2], scenario_sha256)
        self._exact('holder', holder)
        self._exact('waiter', waiter)
        self._check(type(observer_exit_code) is int and observer_exit_code >= 0,
                    'Observer exit status required')
        self._check(isinstance(blockers, tuple), 'Exact immutable blocking observation required')
        # An observer's failed assertion with no dependency is a bounded pending
        # sample. Wrong dependencies or contradictory success cannot release.
        if not blockers and observer_exit_code != 0:
            return False
        self._check(blockers == (holder,), 'Exact sole holder/waiter blocking dependency absent')
        self._check(holder_state == 'idle in transaction' and waiter_event_type == 'Lock' and
                    _zero(observer_exit_code), 'Exact lock states and observer success required')
        self._state = 'blocked'
        return True

    @property
    def commit_permitted(self):
        if self._state != 'blocked':
            return False
        try:
            self._tick()
        except Refused:
            return False
        return self._state == 'blocked'

    @property
    def succeeded(self):
        return self._state == 'succeeded'

    def _recipe(self, identity):
        return {'session': identity, 'source_sha': self._binding.source_sha,
                'scenario_binding_sha256': self._binding.fingerprint,
                'transport': 'existing-registered-session-only', 'reopen_stdin': False,
                'execute_available': False}

    def commit_recipe(self):
        self._event('blocked')
        self._state = 'observe-holder-commit'
        return dict(self._recipe(self._sessions['holder']), sql='COMMIT;')

    def observe_holder_commit(self, identity, command_tag, exit_code):
        self._event('observe-holder-commit')
        self._exact('holder', identity)
        self._check(command_tag == 'COMMIT' and _zero(exit_code), 'Explicit holder COMMIT success required')
        self._state = 'observe-waiter-exit'

    def observe_waiter_exit(self, identity, exit_code):
        self._event('observe-waiter-exit')
        self._exact('waiter', identity)
        self._check(_zero(exit_code), 'Owned waiter zero exit required')
        self._state = 'observe-assertion'

    def observe_assertion(self, scenario_sha256, exit_code):
        self._event('observe-assertion')
        self._scenario(SCENARIOS[3], scenario_sha256)
        self._check(_zero(exit_code), 'Source-bound race assertion failed')
        self._state = 'succeeded'

    def observe_eof(self, identity):
        self._check(self._state not in ('failed', 'succeeded'), 'EOF outside active race')
        self._tick()
        self._identity(identity)
        self._check(identity in self._sessions.values(), 'Foreign EOF observation refused')
        self._trip('Owned race session EOF before completion')

    def fail(self, reason):
        """Retain the primary injected failure; later cleanup failures cannot erase it."""
        self._check(_token(reason), 'Bounded failure reason required')
        if self._state != 'failed':
            self._tick()
        self._trip(reason)

    def _cleanup_status(self):
        if self._state != 'failed':
            return 'not-required'
        if self._cleanup_expired:
            return 'expired'
        if set(self._sessions.values()) == self._closed:
            return 'complete'
        try:
            instant = self._clock()
        except Exception:
            self._cleanup_expired = True
            return 'expired'
        if not _instant(instant) or instant < self._last_time or instant >= self._cleanup_deadline:
            self._cleanup_expired = True
            return 'expired'
        self._last_time = instant
        return 'pending'

    def cleanup_recipes(self):
        if self._cleanup_status() != 'pending':
            return ()
        return tuple(dict(self._recipe(identity), actions=('ROLLBACK;', 'close-existing-session'),
                          deadline=self._cleanup_deadline, cleanup_seconds=CLEANUP_SECONDS)
                     for identity in self._sessions.values() if identity not in self._closed)

    def observe_closed(self, identity):
        self._check(self._state == 'failed', 'Cleanup requires a failed race')
        self._check(self._cleanup_status() == 'pending', 'Cleanup deadline expired or cleanup complete')
        self._identity(identity)
        self._check(identity in self._sessions.values() and identity not in self._closed,
                    'Foreign, reused PID or duplicate cleanup session refused')
        self._closed.add(identity)

    def snapshot(self):
        if self._state not in ('failed', 'succeeded'):
            try:
                self._tick()
            except Refused:
                require(self._state == 'failed' and self._primary_failure is not None,
                        'Snapshot refusal must record its terminal failure')
        return {'state': self._state, 'source_sha': self._binding.source_sha,
                'scenario_binding_sha256': self._binding.fingerprint,
                'primary_failure': self._primary_failure, 'cleanup_status': self._cleanup_status(),
                'race_deadline': self._deadline, 'cleanup_deadline': self._cleanup_deadline,
                'observations': self._observations, 'commit_permitted': self.commit_permitted,
                'succeeded': self.succeeded, 'execute_available': False,
                'runtime_evidence': 'pending-injected-observations-only',
                'operations': {'sql': 0, 'docker': 0, 'build': 0, 'credentials': 0,
                               'provider': 0, 'approvals_consumed': 0}}

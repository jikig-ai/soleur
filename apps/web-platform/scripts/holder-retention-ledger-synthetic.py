"""Offline SQLite transition experiment; never admission or deletion evidence.

The caller supplies all times and claims. This has no collector, scheduler,
storage identity, authentication, independent verifier or real cleanup path.
Use only with synthesized values in disposable local test databases.
"""

import re
import sqlite3
from contextlib import closing

IDENTIFIER = re.compile(r'[a-z0-9][a-z0-9._-]{0,79}\Z')
DAY_MS = 24 * 60 * 60 * 1000
TRANSITIONS = {('unarmed', 'armed'), ('armed', 'capturing'),
               ('capturing', 'sealed'), ('sealed', 'deleting')}


def _id(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def _time(value):
    return type(value) is int and 0 <= value <= 2**63 - 1


def _connect(path):
    connection = sqlite3.connect(path, timeout=5, isolation_level=None)
    connection.execute('PRAGMA synchronous = FULL')
    return connection


def initialize(path):
    with closing(_connect(path)) as connection:
        connection.execute('CREATE TABLE IF NOT EXISTS operations '
                           '(operation_id TEXT PRIMARY KEY, generation TEXT NOT NULL, '
                           'start_ms INTEGER NOT NULL, deadline_ms INTEGER NOT NULL, state TEXT NOT NULL, last_ms INTEGER)')


def create(path, operation_id, generation, start_ms, deadline_ms):
    if not (_id(operation_id) and _id(generation) and _time(start_ms) and _time(deadline_ms)
            and 0 < deadline_ms - start_ms <= DAY_MS):
        raise ValueError('invalid synthetic record')
    with closing(_connect(path)) as connection:
        connection.execute('INSERT INTO operations VALUES (?, ?, ?, ?, ?, ?)',
                           (operation_id, generation, start_ms, deadline_ms, 'unarmed', None))


def read(path, operation_id):
    if not _id(operation_id):
        return None
    with closing(_connect(path)) as connection:
        return connection.execute('SELECT generation, start_ms, deadline_ms, state FROM operations '
                                  'WHERE operation_id = ?', (operation_id,)).fetchone()


def transition(path, operation_id, generation, expected, target, now_ms):
    if not (_id(operation_id) and _id(generation) and _time(now_ms) and isinstance(expected, str) and isinstance(target, str)
            and (expected, target) in TRANSITIONS):
        return False
    with closing(_connect(path)) as connection:
        connection.execute('BEGIN IMMEDIATE')
        current = connection.execute('SELECT generation, start_ms, deadline_ms, state, last_ms FROM operations '
                                     'WHERE operation_id = ?', (operation_id,)).fetchone()
        if current is None or current[0] != generation or current[3] != expected or (current[4] is not None and now_ms < current[4]):
            connection.rollback()
            return False
        state = ('expired' if expected in ('unarmed', 'armed') else 'late') if now_ms >= current[2] else target
        if state == target and ((target == 'armed' and now_ms > current[1]) or
                                (target != 'armed' and now_ms < current[1])):
            connection.rollback()
            return False
        connection.execute('UPDATE operations SET state = ?, last_ms = ? WHERE operation_id = ?', (state, now_ms, operation_id))
        connection.commit()
        return state == target


def mark_due(path, now_ms):
    """Expire or mark synthetic records late when called; not a scheduler or clock."""
    if not _time(now_ms):
        raise ValueError('invalid synthetic time')
    with closing(_connect(path)) as connection:
        cursor = connection.execute("UPDATE operations SET state = CASE WHEN state IN ('unarmed', 'armed') "
                                    "THEN 'expired' ELSE 'late' END, last_ms = ? "
                                    "WHERE deadline_ms <= ? AND state IN ('unarmed', 'armed', 'capturing', 'sealed', 'deleting') "
                                    "AND (last_ms IS NULL OR last_ms <= ?)", (now_ms, now_ms, now_ms))
        return cursor.rowcount

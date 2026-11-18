"""Disposable test fixture, not an authenticated authority or live vault."""
import json
import os
import sqlite3
import sys

path, operation = sys.argv[1:]
assert os.path.basename(path) == 'fixture.sqlite'
assert os.path.basename(os.path.dirname(path)).startswith('synthetic-collector-guard-')
assert operation in ('initialize', 'quarantine', 'write', 'inspect')
with sqlite3.connect(path, timeout=3) as db:
    inserted = False
    if operation == 'initialize':
        db.executescript("CREATE TABLE guard (id INTEGER PRIMARY KEY CHECK (id=1), epoch INTEGER NOT NULL, state TEXT NOT NULL); CREATE TABLE writes (epoch INTEGER NOT NULL); INSERT INTO guard VALUES (1, 1, 'active');")
    elif operation == 'quarantine':
        db.execute('BEGIN IMMEDIATE')
        db.execute("UPDATE guard SET state='quarantined', epoch=epoch+1 WHERE id=1 AND state='active'")
    elif operation == 'write':
        db.execute('BEGIN IMMEDIATE')
        cursor = db.execute("INSERT INTO writes SELECT 1 WHERE EXISTS (SELECT 1 FROM guard WHERE id=1 AND state='active' AND epoch=1)")
        inserted = cursor.rowcount == 1
    db.commit()
    state, epoch, writes = db.execute('SELECT state, epoch, (SELECT count(*) FROM writes) FROM guard WHERE id=1').fetchone()
    if operation == 'write':
        state = 'written' if inserted else 'rejected'
    print(json.dumps({'state': state, 'epoch': epoch, 'writes': writes,
                      'backend_stop': 'unknown', 'writer_clearance': False}))

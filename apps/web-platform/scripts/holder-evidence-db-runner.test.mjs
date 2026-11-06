import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { readLocalRoleBindings, inspectBoundRoles, inspectEmbeddedRoles } from './holder-evidence-db-runner.mjs';

const role = { kind: 'role', role_oid: 42, role_name: 'synthetic', can_login: true, superuser: false,
  bypass_rls: false, inherits_by_default: true, can_create_role: false,
  can_create_database: false, replication: false };

function fakeDatabase(state = { read_only: 'on', isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }, rows = [{ row_to_json: JSON.stringify(role) }]) {
  const calls = [];
  return { calls, async begin(mode, callback) {
    calls.push(mode);
    return callback({ unsafe(sql) {
      calls.push(sql);
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([state]);
      return { cursor(batchSize) {
        assert.equal(batchSize, 1);
        return { async *[Symbol.asyncIterator]() { for (const row of rows) yield [row]; } };
      } };
    } });
  } };
}

test('embedded query verifies a private byte snapshot before opening a transaction', async () => {
  const bytes = Buffer.from('SELECT synthetic_role_query');
  const expected = createHash('sha256').update(bytes).digest('hex');
  const db = fakeDatabase();
  const result = await inspectEmbeddedRoles(db, bytes, expected);
  assert.equal(result.state, 'complete');
  assert.equal(db.calls[3], 'SELECT synthetic_role_query');
  const denied = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(denied, bytes, '0'.repeat(64))).state, 'failed');
  assert.deepEqual(denied.calls, []);
});

test('untrusted timeout options fail closed without running getters or opening a transaction', async () => {
  const bytes = Buffer.from('SELECT synthetic_role_query');
  const expected = createHash('sha256').update(bytes).digest('hex');
  let getterCalls = 0;
  const options = Object.defineProperty({}, 'timeoutMs', { get() { getterCalls++; throw Error('private'); } });
  for (const input of [options, null, [], new Proxy({}, { ownKeys() { throw Error('private'); } })]) {
    const db = fakeDatabase();
    const result = await inspectEmbeddedRoles(db, bytes, expected, input);
    assert.deepEqual(result, { state: 'failed', observed_count: null, holder_coverage: 'unknown', writer_clearance: false });
    assert.deepEqual(db.calls, []);
  }
  assert.equal(getterCalls, 0);
  let trapCalls = 0;
  const proxy = new Proxy({ timeoutMs: 10 }, { getOwnPropertyDescriptor() { trapCalls++; throw Error('private'); } });
  const db = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(db, bytes, expected, proxy)).state, 'failed');
  assert.equal(trapCalls, 1);
  assert.deepEqual(db.calls, []);
});

test('embedded query snapshots bytes before an asynchronous adapter can mutate them', async () => {
  const bytes = Buffer.from('SELECT synthetic_role_query');
  const expected = createHash('sha256').update(bytes).digest('hex');
  const db = fakeDatabase();
  const begin = db.begin;
  db.begin = async function (...args) { bytes.fill(0); return begin.apply(this, args); };
  assert.equal((await inspectEmbeddedRoles(db, bytes, expected)).state, 'complete');
  assert.equal(db.calls[3], 'SELECT synthetic_role_query');
});

test('embedded query rejects invalid encoding, mutable shared memory and malformed pins', async () => {
  const digest = (value) => createHash('sha256').update(value).digest('hex');
  for (const [bytes, pin] of [[Buffer.from([0xff]), digest(Buffer.from([0xff]))],
    [Buffer.from([0xef, 0xbb, 0xbf, 0x61]), createHash('sha256').update(Buffer.from([0xef, 0xbb, 0xbf, 0x61])).digest('hex')],
    [Buffer.from('SELECT\0'), digest(Buffer.from('SELECT\0'))], [Buffer.alloc(0), digest(Buffer.alloc(0))],
    [Buffer.alloc(1024 * 1024 + 1), digest(Buffer.alloc(1024 * 1024 + 1))],
    [new Uint8Array(new SharedArrayBuffer(4)), 'a'.repeat(64)], [Buffer.from('SELECT 1'), 'BAD']]) {
    const db = fakeDatabase();
    assert.equal((await inspectEmbeddedRoles(db, bytes, pin)).state, 'failed');
    assert.deepEqual(db.calls, []);
  }
});

test('embedded query rejects foreign-realm shared backing stores before opening a transaction', async () => {
  const shared = runInNewContext('new SharedArrayBuffer(8)');
  const bytes = Buffer.from(shared);
  bytes.write('SELECT 1');
  const db = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(db, bytes, createHash('sha256').update(bytes).digest('hex'))).state, 'failed');
  assert.deepEqual(db.calls, []);
});

test('embedded query rejects shared bytes whose buffer property was shadowed', async () => {
  const bytes = Buffer.from(new SharedArrayBuffer(8));
  bytes.write('SELECT 1');
  Object.defineProperty(bytes, 'buffer', { value: new ArrayBuffer(8) });
  const db = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(db, bytes, createHash('sha256').update(bytes).digest('hex'))).state, 'failed');
  assert.deepEqual(db.calls, []);
});

test('embedded query ignores valueOf substitution', async () => {
  const shared = Buffer.from(new SharedArrayBuffer(8));
  shared.write('SELECT 1');
  const actual = Buffer.alloc(8, 0x78);
  actual.valueOf = () => shared;
  const db = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(db, actual, createHash('sha256').update(shared).digest('hex'))).state, 'failed');
  assert.deepEqual(db.calls, []);
});

test('embedded query enforces actual view length even when byteLength is shadowed', async () => {
  const oversized = Buffer.alloc(1048577, 0x78);
  Object.defineProperty(oversized, 'byteLength', { value: 1 });
  const db = fakeDatabase();
  assert.equal((await inspectEmbeddedRoles(db, oversized, createHash('sha256').update(oversized).digest('hex'))).state, 'failed');
  assert.deepEqual(db.calls, []);
});

test('bound role query runs after read-only isolation verification and emits only counts', async () => {
  const bindings = await readLocalRoleBindings();
  const db = fakeDatabase();
  const result = await inspectBoundRoles(db, bindings);
  assert.equal(db.calls[0], 'isolation level repeatable read read only');
  assert.match(db.calls[1], /^SET LOCAL statement_timeout/);
  assert.match(db.calls[2], /^SELECT current_setting/);
  assert.equal(result.state, 'complete');
  assert.equal(result.observed_count, 1);
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.deepEqual(result.roles, [{ role_oid: 42, can_login: true, superuser: false,
    bypass_rls: false, inherits_by_default: true, can_create_role: false,
    can_create_database: false, replication: false }]);
  assert.equal(JSON.stringify(result).includes('synthetic'), false);
});

test('cursor stops reading immediately after the row cap sentinel', async () => {
  const bindings = await readLocalRoleBindings();
  let yielded = 0;
  const db = { async begin(_mode, callback) { return callback({ unsafe(sql) {
    if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
    if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{ read_only: 'on', isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }]);
    return { cursor() { return { async *[Symbol.asyncIterator]() {
      while (yielded < 20000) { yielded++; yield [{ row_to_json: JSON.stringify({ ...role, role_oid: yielded }) }]; }
    } }; } };
  } }); } };
  const result = await inspectBoundRoles(db, bindings);
  assert.equal(result.state, 'partial');
  assert.equal(yielded, 10001);
});

test('changed bindings refuse before opening a transaction', async () => {
  const bindings = await readLocalRoleBindings();
  const db = fakeDatabase();
  const result = await inspectBoundRoles(db, { ...bindings, query_sha256: '0'.repeat(64) });
  assert.equal(result.state, 'failed');
  assert.deepEqual(db.calls, []);
});

test('a non-read-only transaction never executes the role query', async () => {
  const bindings = await readLocalRoleBindings();
  const db = fakeDatabase({ read_only: 'off', isolation: 'repeatable read' });
  const result = await inspectBoundRoles(db, bindings);
  assert.equal(result.state, 'failed');
  assert.equal(db.calls.length, 3);
});

test('an untrusted search path prevents catalog execution', async () => {
  const bindings = await readLocalRoleBindings();
  const db = fakeDatabase({ read_only: 'on', isolation: 'repeatable read', search_path: 'public, pg_catalog' });
  const result = await inspectBoundRoles(db, bindings);
  assert.equal(result.state, 'failed');
  assert.equal(db.calls.length, 3);
});

test('malformed rows and thrown errors fail without exposing content', async () => {
  const bindings = await readLocalRoleBindings();
  const bad = fakeDatabase(undefined, [{ row_to_json: '{"secret":"do-not-leak"}' }]);
  const result = await inspectBoundRoles(bad, bindings);
  assert.equal(result.state, 'failed');
  assert.equal(JSON.stringify(result).includes('do-not-leak'), false);
  const errored = await inspectBoundRoles({ begin() { throw new Error('secret-error'); } }, bindings);
  assert.equal(errored.state, 'failed');
  assert.equal(JSON.stringify(errored).includes('secret-error'), false);
});

test('role-query cap sentinel cannot be reported as complete', async () => {
  const bindings = await readLocalRoleBindings();
  const rows = Array.from({ length: 10001 }, (_, i) => ({ row_to_json: JSON.stringify({ ...role, role_oid: i + 1 }) }));
  const result = await inspectBoundRoles(fakeDatabase(undefined, rows), bindings);
  assert.equal(result.state, 'partial');
  assert.equal(result.observed_count, 10001);
});

test('total decoded row bytes above the cap remain partial', async () => {
  const bindings = await readLocalRoleBindings();
  const rows = Array.from({ length: 1500 }, (_, i) => ({ row_to_json: JSON.stringify({ ...role, role_oid: i + 1, padding: 'x'.repeat(3000) }) }));
  const result = await inspectBoundRoles(fakeDatabase(undefined, rows), bindings);
  assert.equal(result.state, 'partial');
});

test('duplicate role IDs cannot be a complete roster', async () => {
  const bindings = await readLocalRoleBindings();
  const row = { row_to_json: JSON.stringify(role) };
  const result = await inspectBoundRoles(fakeDatabase(undefined, [row, row]), bindings);
  assert.equal(result.state, 'failed');
});

test('deadline refuses a late transaction before it starts any SQL', async () => {
  const bindings = await readLocalRoleBindings();
  let release;
  let sqlCalls = 0;
  const gate = new Promise((resolve) => { release = resolve; });
  const database = { async begin(_mode, callback) { await gate; return callback({ async unsafe() { sqlCalls++; return []; } }); } };
  const result = await inspectBoundRoles(database, bindings, { timeoutMs: 10 });
  release();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(result.state, 'failed');
  assert.equal(sqlCalls, 0);
});

test('a late cursor batch cannot start another read after the deadline', async () => {
  const bindings = await readLocalRoleBindings();
  let release;
  let requested = 0;
  const gate = new Promise((resolve) => { release = resolve; });
  const database = { async begin(_mode, callback) { return callback({ unsafe(sql) {
    if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
    if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{ read_only: 'on', isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }]);
    return { cursor() { return { async *[Symbol.asyncIterator]() {
      requested++; yield [{ row_to_json: JSON.stringify(role) }];
      requested++; await gate; yield [{ row_to_json: JSON.stringify(role) }];
      requested++; yield [{ row_to_json: JSON.stringify(role) }];
    } }; } };
  } }); } };
  const result = await inspectBoundRoles(database, bindings, { timeoutMs: 10 });
  release();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(result.state, 'failed');
  assert.equal(requested, 2);
});

test('synchronous adapter delay cannot produce success after the deadline', async () => {
  const bindings = await readLocalRoleBindings();
  const db = fakeDatabase();
  const begin = db.begin;
  db.begin = function (...args) {
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return begin.apply(this, args);
  };
  assert.equal((await inspectBoundRoles(db, bindings, { timeoutMs: 10 })).state, 'failed');
});

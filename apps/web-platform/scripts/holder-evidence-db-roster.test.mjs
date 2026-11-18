import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { inspectBoundRoster, inspectEmbeddedRoster, readLocalRosterBindings } from './holder-evidence-db-roster.mjs';

const role = (id) => ({ kind: 'role', role_oid: id, role_name: `private-${id}`, can_login: true, superuser: false,
  bypass_rls: false, inherits_by_default: true, can_create_role: false, can_create_database: false, replication: false });
const edge = { member_oid: 1, role_oid: 2, grantor_oid: 1, member_name: 'private-member', role_name: 'private-parent',
  admin_option: false, inherit_option: true, set_option: true, inherits_privileges: true, can_set_role: true };

function fakeDatabase({ failMembership = false, memberships = [edge], roles = [role(1), role(2)], state = 'on' } = {}) {
  let transactions = 0;
  let savepoints = 0;
  const queries = [];
  const tx = {
    async savepoint(callback) { savepoints++; return callback(tx); },
    unsafe(sql) {
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{ read_only: state, isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }]);
      queries.push(sql);
      const isMembership = sql.includes('FROM pg_catalog.pg_auth_members');
      if (isMembership && failMembership) throw new Error('private-error');
      const items = isMembership ? memberships : roles;
      return { cursor() { return { async *[Symbol.asyncIterator]() { for (const item of items) yield [{ row_to_json: JSON.stringify(item) }]; } }; } };
    },
  };
  return { queries, get transactions() { return transactions; }, get savepoints() { return savepoints; },
    async begin(mode, callback) { transactions++; assert.equal(mode, 'isolation level repeatable read read only'); return callback(tx); } };
}

test('embedded roster binds both exact queries before opening its transaction', async () => {
  const roles = Buffer.from('SELECT synthetic_roles');
  const memberships = Buffer.from('SELECT synthetic_memberships FROM pg_catalog.pg_auth_members');
  const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
  const pins = { roles_sha256: sha(roles), memberships_sha256: sha(memberships) };
  const db = fakeDatabase();
  const begin = db.begin;
  db.begin = async function (...args) { roles.fill(0); memberships.fill(0); return begin.apply(this, args); };
  const result = await inspectEmbeddedRoster(db, { roles, memberships }, pins);
  assert.equal(result.cross_reference, 'consistent');
  assert.equal(result.cross_reference_scope, 'returned_rows_only');
  assert.deepEqual(db.queries, ['SELECT synthetic_roles', 'SELECT synthetic_memberships FROM pg_catalog.pg_auth_members']);
});

test('either invalid embedded roster query refuses before opening a transaction', async () => {
  const roles = Buffer.from('SELECT synthetic_roles');
  const memberships = Buffer.from('SELECT synthetic_memberships');
  const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
  const pins = { roles_sha256: sha(roles), memberships_sha256: sha(memberships) };
  for (const changed of [{ ...pins, roles_sha256: '0'.repeat(64) }, { ...pins, memberships_sha256: '0'.repeat(64) }]) {
    const db = fakeDatabase();
    assert.equal((await inspectEmbeddedRoster(db, { roles, memberships }, changed)).roles.state, 'failed');
    assert.equal(db.transactions, 0);
  }
});

test('same-snapshot roster strips names and reconciles identifiers', async () => {
  const db = fakeDatabase();
  const result = await inspectBoundRoster(db, await readLocalRosterBindings());
  assert.equal(db.transactions, 1);
  assert.equal(db.savepoints, 2);
  assert.equal(result.roles.state, 'complete');
  assert.equal(result.memberships.state, 'complete');
  assert.equal(result.cross_reference, 'consistent');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('failed membership arm remains separate and cannot clear coverage', async () => {
  const result = await inspectBoundRoster(fakeDatabase({ failMembership: true }), await readLocalRosterBindings());
  assert.equal(result.roles.state, 'complete');
  assert.equal(result.memberships.state, 'failed');
  assert.equal(result.cross_reference, 'unknown');
  assert.equal(JSON.stringify(result).includes('private-error'), false);
});

test('unmatched IDs, wrong transaction and source digest fail closed', async () => {
  const bindings = await readLocalRosterBindings();
  const mismatch = await inspectBoundRoster(fakeDatabase({ memberships: [{ ...edge, member_oid: 7 }] }), bindings);
  assert.equal(mismatch.cross_reference, 'unknown');
  const db = fakeDatabase({ state: 'off' });
  assert.equal((await inspectBoundRoster(db, bindings)).roles.state, 'failed');
  assert.equal(db.savepoints, 0);
  const notStarted = fakeDatabase();
  assert.equal((await inspectBoundRoster(notStarted, { ...bindings, memberships_sha256: '0'.repeat(64) })).roles.state, 'failed');
  assert.equal(notStarted.transactions, 0);
});

test('duplicate identities and malformed metadata cannot produce a complete arm', async () => {
  const bindings = await readLocalRosterBindings();
  assert.equal((await inspectBoundRoster(fakeDatabase({ roles: [role(1), role(1)] }), bindings)).roles.state, 'failed');
  assert.equal((await inspectBoundRoster(fakeDatabase({ memberships: [{ ...edge, set_option: 'private' }] }), bindings)).memberships.state, 'failed');
});

test('row and byte caps cannot yield complete role evidence', async () => {
  const bindings = await readLocalRosterBindings();
  const many = Array.from({ length: 10001 }, (_, i) => role(i + 1));
  assert.equal((await inspectBoundRoster(fakeDatabase({ roles: many }), bindings)).roles.state, 'partial');
  const large = Array.from({ length: 1500 }, (_, i) => ({ ...role(i + 1), padding: 'x'.repeat(3000) }));
  assert.equal((await inspectBoundRoster(fakeDatabase({ roles: large }), bindings)).roles.state, 'partial');
});

test('a late first arm cannot initiate the second arm after timeout', async () => {
  const bindings = await readLocalRosterBindings();
  let release;
  let membershipsStarted = 0;
  const gate = new Promise((resolve) => { release = resolve; });
  const tx = { async savepoint(callback) { return callback(tx); }, unsafe(sql) {
    if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
    if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{ read_only: 'on', isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }]);
    if (sql.includes('FROM pg_catalog.pg_auth_members')) membershipsStarted++;
    return { cursor() { return { async *[Symbol.asyncIterator]() { await gate; yield [{ row_to_json: JSON.stringify(role(1)) }]; } }; } };
  } };
  const db = { async begin(_mode, callback) { return callback(tx); } };
  const result = await inspectBoundRoster(db, bindings, { timeoutMs: 10 });
  release();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(result.roles.state, 'failed');
  assert.equal(membershipsStarted, 0);
});

test('synchronous adapter delay cannot produce a complete snapshot after timeout', async () => {
  const bindings = await readLocalRosterBindings();
  const db = fakeDatabase();
  const begin = db.begin;
  db.begin = function (...args) {
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return begin.apply(this, args);
  };
  assert.equal((await inspectBoundRoster(db, bindings, { timeoutMs: 10 })).roles.state, 'failed');
});

test('null and throwing options return fixed failure without starting a transaction', async () => {
  for (const options of [null,{get timeoutMs(){throw Error('private-option');}},new Proxy({}, {ownKeys(){throw Error('private-option');}})]) {
    const db=fakeDatabase();
    const result=await inspectEmbeddedRoster(db,null,null,options);
    assert.equal(result.roles.state,'failed');
    assert.equal(db.transactions,0);
    assert.equal(JSON.stringify(result).includes('private-option'),false);
  }
});

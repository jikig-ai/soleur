import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inspectBoundRoles, readLocalRoleBindings } from './holder-evidence-db-runner.mjs';
import { trackInspectionTransaction } from './holder-evidence-transaction-tracker.mjs';
import { buildQueryBundle } from './holder-evidence-bundle.mjs';

test('public inspection timeout leaves the underlying transaction pending until it actually settles', async () => {
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const database = { begin: () => pending };
  const pins = await readLocalRoleBindings();
  const tracked = trackInspectionTransaction(database, db => inspectBoundRoles(db, pins, { timeoutMs: 10 }));
  const result = await tracked.inspection;
  assert.equal(result.state, 'failed');
  assert.equal(result.writer_clearance, false);
  let settled = false;
  tracked.settlement.then(() => { settled = true; });
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(settled, false);
  release('private late result');
  assert.deepEqual(await tracked.settlement, { state: 'fulfilled', backend_stop: 'unknown', writer_clearance: false });
});

test('the actual bundled roster deadline does not settle its tracked begin promise', async () => {
  const bundle = await buildQueryBundle();
  const { inspectBundledRoster } = await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const tracked = trackInspectionTransaction({ begin: () => pending }, db => inspectBundledRoster(db, bundle.queries, { timeoutMs: 10 }));
  const result = await tracked.inspection;
  assert.equal(result.roles.state, 'failed');
  assert.equal(result.writer_clearance, false);
  let settled = false;
  tracked.settlement.then(() => { settled = true; });
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(settled, false);
  release('late private value');
  assert.deepEqual(await tracked.settlement, { state: 'fulfilled', backend_stop: 'unknown', writer_clearance: false });
});

test('a late attempt to open after inspection has finished is refused', async () => {
  let lateDatabase, starts = 0;
  const tracked = trackInspectionTransaction({ begin: () => { starts++; } }, db => { lateDatabase = db; return { state: 'failed', writer_clearance: false }; });
  await tracked.inspection;
  assert.deepEqual(await tracked.settlement, { state: 'not_started', backend_stop: 'unknown', writer_clearance: false });
  assert.throws(() => lateDatabase.begin('read only', () => {}));
  assert.equal(starts, 0);
});

test('transaction errors and duplicate starts are fixed failures without raw messages', async () => {
  let starts = 0;
  const tracked = trackInspectionTransaction({ begin: () => { starts++; return Promise.reject(new Error('private diagnostic')); } }, async db => {
    const first = db.begin('read only', () => {});
    assert.throws(() => db.begin('read only', () => {}));
    await first;
  });
  assert.equal((await tracked.inspection).state, 'failed');
  assert.deepEqual(await tracked.settlement, { state: 'rejected', backend_stop: 'unknown', writer_clearance: false });
  assert.equal(starts, 1);
});

test('throwing result properties and arbitrary fields never escape the inspection projection', async () => {
  for (const value of [new Proxy({}, { ownKeys() { throw new Error('private keys'); }, get() { throw new Error('private get'); } }),
    Object.defineProperty({}, 'state', { get() { throw new Error('private state'); }, enumerable: true })]) {
    const tracked = trackInspectionTransaction({ begin: () => Promise.resolve() }, () => value);
    assert.deepEqual(await tracked.inspection, { state: 'failed', backend_stop: 'unknown', writer_clearance: false });
    assert.equal((await tracked.settlement).state, 'not_started');
  }
  const tracked = trackInspectionTransaction({ begin: () => Promise.resolve() }, () => ({ state: 'partial', sensitive: 'private value' }));
  assert.deepEqual(await tracked.inspection, { state: 'partial', backend_stop: 'unknown', writer_clearance: false });
});

test('inspection state is snapshotted once before validation and emission', async () => {
  let reads = 0;
  const changing = { get state() { return ++reads === 1 ? 'partial' : 'private value'; } };
  const tracked = trackInspectionTransaction({ begin: () => Promise.resolve() }, () => changing);
  assert.deepEqual(await tracked.inspection, { state: 'partial', backend_stop: 'unknown', writer_clearance: false });
  assert.equal(reads, 1);
  let roleReads = 0, stateReads = 0;
  const roster = { get roles() { roleReads++; return { get state() { return ++stateReads === 1 ? 'failed' : 'private value'; } }; } };
  const trackedRoster = trackInspectionTransaction({ begin: () => Promise.resolve() }, () => roster);
  assert.deepEqual(await trackedRoster.inspection, { roles: { state: 'failed' }, backend_stop: 'unknown', writer_clearance: false });
  assert.equal(roleReads, 1);
  assert.equal(stateReads, 1);
});

test('inspection result projection cannot start a transaction after inspection returned', async () => {
  let starts = 0;
  const tracked = trackInspectionTransaction({ begin: () => { starts++; return Promise.resolve(); } }, db => ({
    get state() { try { db.begin('read only', () => {}); } catch {} return 'failed'; },
  }));
  assert.equal((await tracked.inspection).state, 'failed');
  assert.equal(starts, 0);
  assert.equal((await tracked.settlement).state, 'not_started');
});

test('a synchronous result then getter cannot start a transaction after return', async () => {
  let starts = 0;
  const tracked = trackInspectionTransaction({ begin: () => { starts++; return Promise.resolve(); } }, db => ({
    get then() { try { db.begin('read only', () => {}); } catch {} return undefined; }, state: 'failed',
  }));
  assert.equal((await tracked.inspection).state, 'failed');
  assert.equal(starts, 0);
  assert.equal((await tracked.settlement).state, 'not_started');
});

test('a reentrant asynchronous observation is tracked and never grants backend clearance', async () => {
  let starts = 0;
  const tracked = trackInspectionTransaction({ begin: () => { starts++; return Promise.resolve(); } }, db => {
    const result = Promise.resolve({ state: 'failed' });
    Object.defineProperty(result, 'constructor', { get() { db.begin('read only', () => {}); return Promise; } });
    return result;
  });
  assert.equal((await tracked.inspection).state, 'failed');
  assert.equal(starts, 1);
  assert.deepEqual(await tracked.settlement, { state: 'fulfilled', backend_stop: 'unknown', writer_clearance: false });
});

test('an overridden promise then cannot settle observation before the native promise settles', async () => {
  let release;
  const raw = new Promise(resolve => { release = resolve; });
  Object.defineProperty(raw, 'then', { value() { throw new Error('private then'); } });
  const tracked = trackInspectionTransaction({ begin: () => raw }, async db => { db.begin('read only', () => {}); return { state: 'failed' }; });
  await tracked.inspection;
  let settled = false;
  tracked.settlement.then(() => { settled = true; });
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(settled, false);
  release('private value');
  assert.deepEqual(await tracked.settlement, { state: 'fulfilled', backend_stop: 'unknown', writer_clearance: false });
});

test('a non-native thenable cannot assert transaction settlement', async () => {
  const tracked = trackInspectionTransaction({ begin: () => ({ then() { throw new Error('private then'); } }) }, async db => { await db.begin('read only', () => {}); });
  assert.equal((await tracked.inspection).state, 'failed');
  assert.deepEqual(await tracked.settlement, { state: 'unknown', backend_stop: 'unknown', writer_clearance: false });
});

test('database begin is snapshotted once and accessor failures are sanitized', async () => {
  assert.throws(() => trackInspectionTransaction({ get begin() { throw new Error('private accessor'); } }, () => ({})), { message: 'tracker_configuration' });
  let reads = 0, starts = 0;
  const database = { get begin() { reads++; return () => { starts++; return Promise.resolve(); }; } };
  const tracked = trackInspectionTransaction(database, async db => { await db.begin('read only', () => {}); return { state: 'complete' }; });
  assert.equal((await tracked.inspection).state, 'complete');
  assert.equal((await tracked.settlement).state, 'fulfilled');
  assert.equal(reads, 1);
  assert.equal(starts, 1);
});

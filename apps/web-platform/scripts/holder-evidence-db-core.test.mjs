import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inspectCatalogArm, inspectCatalogSet } from './holder-evidence-db-core.mjs';

test('a successful empty result is distinct from an unavailable arm', async () => {
  const result = await inspectCatalogArm(async () => [], { maxRows: 2, timeoutMs: 1000 });
  assert.deepEqual(result, { state: 'complete', observed_count: 0 });
  const failed = await inspectCatalogArm(async () => { throw new Error('secret failure'); }, { maxRows: 2, timeoutMs: 1000 });
  assert.deepEqual(failed, { state: 'failed', observed_count: null });
  assert.equal(JSON.stringify(failed).includes('secret'), false);
});

test('a cap sentinel cannot be reported as a complete result', async () => {
  const result = await inspectCatalogArm(async () => [{ secret: 'private' }, {}, {}], { maxRows: 2, timeoutMs: 1000 });
  assert.deepEqual(result, { state: 'partial', observed_count: 3 });
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.equal((await inspectCatalogArm(async () => null, { maxRows: 2, timeoutMs: 1000 })).state, 'failed');
  assert.equal((await inspectCatalogArm(async () => [null], { maxRows: 2, timeoutMs: 1000 })).state, 'failed');
  assert.equal((await inspectCatalogArm(async () => ['private'], { maxRows: 2, timeoutMs: 1000 })).state, 'failed');
});

test('global deadline prevents later arms starting after an uncooperative reader', async () => {
  let laterCalls = 0;
  let release;
  const slow = new Promise((resolve) => { release = resolve; });
  const result = await inspectCatalogSet({ roles: () => slow, memberships: async () => { laterCalls++; return []; } }, { maxRows: 2, timeoutMs: 15 });
  release([]);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(laterCalls, 0);
  assert.equal(result.arms.roles.state, 'failed');
  assert.equal(result.arms.memberships.state, 'failed');
});

test('timeout aborts the injected arm and reports a failure', async () => {
  let aborted = false;
  const result = await inspectCatalogArm((signal) => new Promise((_resolve, reject) => {
    signal.addEventListener('abort', () => { aborted = true; reject(new Error('private')); });
  }), { maxRows: 2, timeoutMs: 10 });
  assert.equal(aborted, true);
  assert.deepEqual(result, { state: 'failed', observed_count: null });
});

test('a blocked event loop cannot turn an expired arm into complete', async () => {
  const result = await inspectCatalogArm(() => {
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return [];
  }, { maxRows: 2, timeoutMs: 10 });
  assert.equal(result.state, 'failed');
});

test('each missing or failed arm remains separate and overall coverage unknown', async () => {
  const result = await inspectCatalogSet({ roles: async () => [], memberships: async () => { throw new Error('private'); } }, { maxRows: 2, timeoutMs: 1000 });
  assert.equal(result.arms.roles.state, 'complete');
  assert.equal(result.arms.memberships.state, 'failed');
  assert.equal(result.arms.sessions.state, 'unsupported');
  assert.equal(result.arms.sequence_acls.state, 'unsupported');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('invalid limits never call the supplied arm', async () => {
  let calls = 0;
  const result = await inspectCatalogArm(async () => { calls++; return []; }, { maxRows: 0, timeoutMs: 1000 });
  assert.equal(calls, 0);
  assert.equal(result.state, 'failed');
});

test('session visibility and the query sentinel cannot become a complete census', async () => {
  const session = { kind: 'session', role_oid: 42, role_name: 'synthetic', application_class: 'other', state_class: 'active', transaction_age_bucket: 'none_or_hidden', write_capability: 'unknown', secret: 'not-output' };
  const summary = (count, capped, visibility) => ({ kind: 'session_summary', observed_count: count, capped, visibility });
  const inspect = (rows) => inspectCatalogSet({ sessions: async () => rows }, { maxRows: 10000, timeoutMs: 1000 });
  assert.equal((await inspect([summary(1, false, 'restricted'), session])).arms.sessions.state, 'partial');
  assert.equal((await inspect([summary(257, true, 'full_stats_privilege'), ...Array(257).fill(session)])).arms.sessions.state, 'partial');
  assert.equal((await inspect([session])).arms.sessions.state, 'failed');
  assert.equal((await inspect([summary(2, false, 'full_stats_privilege'), session])).arms.sessions.state, 'failed');
  assert.equal((await inspect([summary(1, false, 'full_stats_privilege'), { ...session, state_class: 'private' }])).arms.sessions.state, 'partial');
  assert.equal((await inspect([summary(1, false, 'full_stats_privilege'), { ...session, state_class: 'disabled' }])).arms.sessions.state, 'partial');
  assert.equal((await inspect([summary(1, false, 'full_stats_privilege'), { ...session, role_oid: null }])).arms.sessions.state, 'partial');
  assert.equal((await inspect([summary(1, false, 'full_stats_privilege'), session])).arms.sessions.state, 'complete');
  assert.equal(JSON.stringify(await inspect([summary(1, false, 'full_stats_privilege'), session])).includes('not-output'), false);
});

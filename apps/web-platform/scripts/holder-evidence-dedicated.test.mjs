import { test } from 'node:test';
import assert from 'node:assert/strict';
import { observeDedicatedLifecycle } from './holder-evidence-dedicated.mjs';
import { trackInspectionTransaction } from './holder-evidence-transaction-tracker.mjs';
import { inspectBoundRoles, readLocalRoleBindings } from './holder-evidence-db-runner.mjs';

const limits = { workMs: 15, cleanupMs: 80 };
const report = (phase) => ({ status: 'stopped', phase, scope: 'owned_operation' });
const adapter = (overrides = {}) => ({
  create: () => ({}),
  start: async () => 'private-result',
  cancel: async () => undefined,
  close: async () => undefined,
  verify: async (_connection, phase) => report(phase),
  ...overrides,
});

test('public collector timeout alone does not let the lifecycle observer close or report stop', async () => {
  let release, verifyCalls = 0, closeCalls = 0, inspection;
  const pending = new Promise(resolve => { release = resolve; });
  const pins = await readLocalRoleBindings();
  const result = await observeDedicatedLifecycle(adapter({
    start: () => {
      const tracked = trackInspectionTransaction({ begin: () => pending }, db => inspectBoundRoles(db, pins, { timeoutMs: 5 }));
      inspection = tracked.inspection;
      return tracked.settlement;
    },
    cancel: async () => undefined,
    verify: async (_connection, phase) => { verifyCalls++; return report(phase); },
    close: async () => { closeCalls++; },
  }), { workMs: 20, cleanupMs: 20 });
  assert.equal((await inspection).state, 'failed');
  assert.equal(result.stop, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.equal(verifyCalls, 0);
  assert.equal(closeCalls, 0);
  release();
});

test('normal completion reports only adapter assertions, never raw result or clearance', async () => {
  const result = await observeDedicatedLifecycle(adapter(), limits);
  assert.equal(result.operation, 'completed');
  assert.equal(result.stop, 'observer_reported_stopped');
  assert.equal(result.evidence, 'adapter_report_only');
  assert.equal(result.ownership, 'unverified');
  assert.equal(result.writer_clearance, false);
  assert.equal(JSON.stringify(result).includes('private-result'), false);
});

test('deadline cancels and observes stop before releasing the held connection', async () => {
  const calls = [];
  let settle;
  const pending = new Promise((resolve) => { settle = resolve; });
  const result = await observeDedicatedLifecycle(adapter({
    start: () => pending,
    cancel: async () => { calls.push('cancel'); settle(); },
    verify: async (_connection, phase) => { calls.push(phase); return report(phase); },
    close: async () => { calls.push('close'); },
  }), limits);
  assert.equal(result.operation, 'timeout');
  assert.equal(result.stop, 'observer_reported_stopped');
  assert.deepEqual(calls, ['cancel', 'preclose', 'close', 'postclose']);
});

test('an unconfirmed cancellation does not release or claim the connection stopped', async () => {
  let closeCalls = 0;
  const result = await observeDedicatedLifecycle(adapter({
    start: () => new Promise(() => {}), cancel: () => new Promise(() => {}),
    close: async () => { closeCalls++; },
  }), { workMs: 10, cleanupMs: 20 });
  assert.equal(result.operation, 'timeout');
  assert.equal(result.stop, 'unknown');
  assert.equal(closeCalls, 0);
});

test('unsettled work or missing independent observations stay unknown', async () => {
  let closed = 0;
  const result = await observeDedicatedLifecycle(adapter({
    start: () => new Promise(() => {}), cancel: async () => undefined,
    close: async () => { closed++; }, verify: async () => true,
  }), { workMs: 10, cleanupMs: 20 });
  assert.equal(result.stop, 'unknown');
  assert.equal(closed, 0);
  const badReport = await observeDedicatedLifecycle(adapter({ verify: async () => true }), limits);
  assert.equal(badReport.stop, 'unknown');
});

test('a rejected cancellation cannot release even if the task has settled', async () => {
  let settle;
  let closes = 0;
  const pending = new Promise((resolve) => { settle = resolve; });
  const result = await observeDedicatedLifecycle(adapter({
    start: () => pending,
    cancel: async () => { settle(); throw new Error('private'); },
    close: async () => { closes++; },
  }), limits);
  assert.equal(result.cancel, 'failed');
  assert.equal(result.stop, 'unknown');
  assert.equal(closes, 0);
});

test('preclose and postclose require distinct observer reports', async () => {
  let closes = 0;
  const badPre = await observeDedicatedLifecycle(adapter({
    verify: async () => report('postclose'), close: async () => { closes++; },
  }), limits);
  assert.equal(badPre.stop, 'unknown');
  assert.equal(closes, 0);
  const badPost = await observeDedicatedLifecycle(adapter({ verify: async () => report('preclose') }), limits);
  assert.equal(badPost.stop, 'unknown');
  assert.equal(badPost.close, 'completed');
});

test('creation, operation, close and observer errors never expose arbitrary messages', async () => {
  for (const replacement of [
    { create: () => { throw new Error('secret-create'); } },
    { start: async () => { throw new Error('secret-start'); } },
    { close: async () => { throw new Error('secret-close'); } },
    { verify: async () => { throw new Error('secret-observer'); } },
  ]) {
    const result = await observeDedicatedLifecycle(adapter(replacement), limits);
    assert.equal(JSON.stringify(result).includes('secret-'), false);
    assert.equal(result.writer_clearance, false);
    if (replacement.create || replacement.close || replacement.verify) assert.equal(result.stop, 'unknown');
  }
});

test('invalid limits or non-synchronous ownership acquisition start no work', async () => {
  let starts = 0;
  const invalid = await observeDedicatedLifecycle(adapter({ start: () => { starts++; } }), { workMs: 0, cleanupMs: 80 });
  const asyncCreate = await observeDedicatedLifecycle(adapter({ create: async () => ({}), start: () => { starts++; } }), limits);
  const rejectedCreate = await observeDedicatedLifecycle(adapter({ create: async () => { throw new Error('private'); }, start: () => { starts++; } }), limits);
  assert.equal(invalid.stop, 'unknown');
  assert.equal(asyncCreate.stop, 'unknown');
  assert.equal(rejectedCreate.stop, 'unknown');
  assert.equal(starts, 0);
});

test('synchronous operation delay cannot be reported as completed before deadline', async () => {
  const result = await observeDedicatedLifecycle(adapter({ start: () => {
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
  } }), { workMs: 10, cleanupMs: 80 });
  assert.equal(result.operation, 'timeout');
});

test('post-close observation after the cleanup deadline cannot prove stop', async () => {
  const result = await observeDedicatedLifecycle(adapter({ verify: (_connection, phase) => {
    if (phase === 'postclose') {
      const until = performance.now() + 30;
      while (performance.now() < until) { /* synthetic event-loop stall */ }
    }
    return report(phase);
  } }), { workMs: 100, cleanupMs: 10 });
  assert.equal(result.stop, 'unknown');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSyntheticDedicatedAdapter } from './holder-evidence-dedicated-adapter.mjs';

const limits = { workMs: 10, cleanupMs: 50 };

test('synthetic held backend can complete without claiming real ownership', async () => {
  const fixture = createSyntheticDedicatedAdapter('complete');
  const result = await fixture.run(limits);
  assert.equal(result.model_stop, 'observer_reported_stopped');
  assert.equal(result.stop, 'unknown');
  assert.equal(result.ownership, 'unverified');
  assert.equal(result.evidence, 'synthetic_only');
  assert.equal(result.writer_clearance, false);
  assert.equal(fixture.stats().starts, 1);
  assert.equal(fixture.stats().closes, 1);
  assert.equal(JSON.stringify(result).includes('backend'), false);
});

test('synthetic cancellation waits for independently reported stop before close', async () => {
  const fixture = createSyntheticDedicatedAdapter('cancel');
  const result = await fixture.run(limits);
  assert.equal(result.operation, 'timeout');
  assert.equal(result.model_stop, 'observer_reported_stopped');
  assert.equal(result.stop, 'unknown');
  assert.deepEqual(fixture.stats(), { starts: 1, cancellation_attempts: 1, cancellations: 1, closes: 1 });
});

test('reused synthetic backend is never cancelled or closed by the stale handle', async () => {
  for (const scenario of ['reuse_before_cancel', 'reuse_generation_only', 'reuse_owner_only']) {
    const fixture = createSyntheticDedicatedAdapter(scenario);
    const result = await fixture.run(limits);
    assert.equal(result.stop, 'unknown');
    assert.equal(result.model_stop, 'unknown');
    assert.equal(result.cancel, 'failed');
    assert.equal(fixture.stats().cancellation_attempts, 1);
    assert.equal(fixture.stats().cancellations, 0);
    assert.equal(fixture.stats().closes, 0);
  }
});

test('shared or ambiguous acquisition never starts synthetic work', async () => {
  for (const scenario of ['shared', 'ambiguous']) {
    const fixture = createSyntheticDedicatedAdapter(scenario);
    const result = await fixture.run(limits);
    assert.equal(result.stop, 'unknown');
    assert.equal(result.model_stop, 'unknown');
    assert.equal(fixture.stats().starts, 0);
  }
});

test('unobservable stop or a nonindependent observer cannot clear or release', async () => {
  for (const scenario of ['observer_missing', 'observer_shared', 'preclose_unknown']) {
    const fixture = createSyntheticDedicatedAdapter(scenario);
    const result = await fixture.run(limits);
    assert.equal(result.stop, 'unknown');
    assert.equal(result.model_stop, 'unknown');
    assert.equal(result.ownership, 'unverified');
    assert.equal(fixture.stats().closes, 0);
  }
});

test('unproven disappearance after close remains unknown', async () => {
  const fixture = createSyntheticDedicatedAdapter('postclose_unknown');
  const result = await fixture.run(limits);
  assert.equal(result.stop, 'unknown');
  assert.equal(result.model_stop, 'unknown');
  assert.equal(result.close, 'completed');
  assert.equal(fixture.stats().closes, 1);
});

test('an already-issued synthetic handle cannot start a second lifecycle', async () => {
  const fixture = createSyntheticDedicatedAdapter('complete');
  assert.equal((await fixture.run(limits)).model_stop, 'observer_reported_stopped');
  const again = await fixture.run(limits);
  assert.equal(again.stop, 'unknown');
  assert.equal(fixture.stats().starts, 1);
});

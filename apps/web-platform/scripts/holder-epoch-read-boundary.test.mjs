import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readEpochEvidence } from './holder-epoch-read-boundary.mjs';

const table_arn = 'arn:aws:dynamodb:eu-west-1:123456789012:table/synthetic-epochs';
const operation_id = 'a'.repeat(32), generation = 'b'.repeat(32), store_id = 'c'.repeat(32);
const expected = { table_arn, operation_id, generation, store_id, timeout_ms: 1000 };
const floor = { table_arn, operation_id, generation, store_id, minimum_epoch: '7', revoked: false };
const item = { operation_id: { S: operation_id }, generation: { S: generation }, store_id: { S: store_id },
  epoch: { N: '7' }, revoked: { BOOL: false } };
const raw = value => Buffer.from(JSON.stringify(value));
const args = (read, value = floor, config = expected) => [read, JSON.stringify(config), JSON.stringify(value)];
const flags = { state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false };

test('requests a strongly consistent pinned GetItem but does not claim nonrollback', async () => {
  let request;
  const result = await readEpochEvidence(...args(async (query) => { request = query; return raw({ Item: item }); }));
  assert.deepEqual(result, { ...flags, reason: 'nonrollback_unverified' });
  assert.deepEqual(request, { TableName: table_arn, Key: { operation_id: { S: operation_id } }, ConsistentRead: true });
  const pretty = Buffer.from(JSON.stringify({ Item: item }, null, 2));
  assert.deepEqual(await readEpochEvidence(...args(async () => pretty)), { ...flags, reason: 'nonrollback_unverified' });
});

test('a restored older epoch and mismatched generation or table cannot reconcile', async () => {
  const stale = { ...item, epoch: { N: '6' } };
  assert.deepEqual(await readEpochEvidence(...args(async () => raw({ Item: stale }))), { ...flags, reason: 'below_asserted_floor' });
  for (const altered of [{ ...item, generation: { S: 'd'.repeat(32) } }, { ...item, store_id: { S: 'd'.repeat(32) } },
    { ...item, operation_id: { S: 'd'.repeat(32) } }]) {
    assert.deepEqual(await readEpochEvidence(...args(async () => raw({ Item: altered }))), { ...flags, reason: 'invalid' });
  }
  let calls = 0;
  const mismatch = { ...floor, table_arn: table_arn.replace('synthetic-epochs', 'other') };
  assert.deepEqual(await readEpochEvidence(...args(async () => { calls++; return raw({ Item: item }); }, mismatch)), { ...flags, reason: 'invalid' });
  assert.equal(calls, 0);
});

test('absent, revoked, malformed, oversized and untrusted input never authorize', async () => {
  for (const value of [{}, { Item: { ...item, revoked: { BOOL: true } } }, { Item: { ...item, epoch: { N: '07' } } },
    { Item: { ...item, epoch: { N: '9007199254740992' } } }, { Item: { ...item, private: { S: 'private-value' } } }]) {
    const result = await readEpochEvidence(...args(async () => raw(value)));
    assert.equal(result.state, 'unknown');
    assert.equal(result.capture_authorized, false);
    assert.doesNotMatch(JSON.stringify(result), /private-value/);
  }
  assert.deepEqual(await readEpochEvidence(...args(async () => Buffer.alloc(8193))), { ...flags, reason: 'invalid' });
  assert.deepEqual(await readEpochEvidence(...args(async () => { throw new Error('private'); })), { ...flags, reason: 'invalid' });
});

test('empty, duplicate keys, shared backing and shadowed byte length cannot hide invalid bytes', async () => {
  const shared = new Uint8Array(new SharedArrayBuffer(1));
  const huge = Buffer.alloc(8193); Object.defineProperty(huge, 'byteLength', { value: 1 });
  const duplicate = Buffer.from('{"Item":{},"Item":{}}');
  for (const bytes of [Buffer.alloc(0), duplicate, shared, huge]) {
    assert.deepEqual(await readEpochEvidence(...args(async () => bytes)), { ...flags, reason: 'invalid' });
  }
});

test('response byte cap refuses an oversized valid JSON view before allocating its copy', async () => {
  const json = JSON.stringify({ Item: item });
  const bytes = Buffer.from(json + ' '.repeat(8193 - Buffer.byteLength(json)));
  const original = Buffer.allocUnsafe;
  let allocations = 0;
  Buffer.allocUnsafe = (size, ...rest) => { if (size === bytes.length) allocations++; return original(size, ...rest); };
  try {
    Buffer.allocUnsafe(bytes.length);
    assert.equal(allocations, 1, 'allocation probe did not observe its own test');
    allocations = 0;
    assert.deepEqual(await readEpochEvidence(...args(async () => bytes)), { ...flags, reason: 'invalid' });
    assert.equal(allocations, 0, 'oversized response was copied before refusal');
  } finally { Buffer.allocUnsafe = original; }
});

test('unsettled transport times out without making a freshness claim', async () => {
  let signal;
  const result = await readEpochEvidence(...args(async (_query, s) => { signal = s; return new Promise(() => {}); }, floor, { ...expected, timeout_ms: 10 }));
  assert.deepEqual(result, { ...flags, reason: 'invalid' });
  assert.equal(signal.aborted, true);
});

test('response parsing that crosses the deadline never reports a fresh observation', async () => {
  const response = JSON.stringify({ Item: item });
  const requestArgs = args(async () => Buffer.from(response), floor, { ...expected, timeout_ms: 20 });
  const originalParse = JSON.parse;
  let stalled = false;
  JSON.parse = (...values) => {
    if (values[0] === response) {
      stalled = true;
      const until = performance.now() + 50;
      while (performance.now() < until) { /* synthetic synchronous stall */ }
    }
    return originalParse(...values);
  };
  let observed;
  try { observed = await readEpochEvidence(...requestArgs); }
  finally { JSON.parse = originalParse; }
  assert.equal(stalled, true);
  assert.deepEqual(observed, { ...flags, reason: 'invalid' });
});

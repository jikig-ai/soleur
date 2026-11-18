import { test } from 'node:test';
import assert from 'node:assert/strict';
import { simulateWorkerSts } from './holder-worker-sts-synthetic.mjs';

const token = { access_token: 'synthetic-token', issued_token_type: 'urn:ietf:params:oauth:token-type:access_token',
  token_type: 'Bearer', expires_in: 300 };
const response = (value, status = 200) => new Response(typeof value === 'string' ? value : JSON.stringify(value), { status });
const empty = { state: 'unknown', capture_authorized: false, cleanup_authorized: false, identity_verified: false };

test('a synthetic mTLS binding receives the fixed X.509 STS exchange shape', async () => {
  let request;
  const result = await simulateWorkerSts({ fetch: async (url, init) => { request = { url, init }; return response(token); } });
  assert.deepEqual(result, { ...empty, state: 'synthetic_match' });
  assert.equal(request.url, 'https://sts.mtls.googleapis.com/v1/token');
  assert.equal(request.init.method, 'POST');
  assert.equal(request.init.redirect, 'error');
  assert.deepEqual(request.init.headers, { 'content-type': 'application/json' });
  const body = JSON.parse(request.init.body);
  assert.equal(body.subject_token_type, 'urn:ietf:params:oauth:token-type:mtls');
  assert.equal(body.grant_type, 'urn:ietf:params:oauth:grant-type:token-exchange');
  assert.equal(body.requested_token_type, 'urn:ietf:params:oauth:token-type:access_token');
  assert.equal(body.scope, 'https://www.googleapis.com/auth/cloud-platform');
  assert.equal(body.audience, '//iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/synthetic-pool/providers/synthetic-provider');
  assert.equal(typeof body.subject_token, 'string');
  assert.deepEqual(JSON.parse(body.subject_token), ['c3ludGhldGljLW5vdC1jZXJ0aWZpY2F0ZQ==']);
  assert.doesNotMatch(JSON.stringify(result), /synthetic-token/);
});

test('provider-shaped failure, unknown fields, and nonfixture credentials never surface', async () => {
  for (const [value, status] of [[{ ...token, access_token: 'private-real-shaped-token' }, 200],
    [{ ...token, extra: 'private-extra' }, 200], [{ ...token, expires_in: 0 }, 200],
    [{ ...token, token_type: 'private-type' }, 200], ['private-provider-error', 403], ['private malformed', 200]]) {
    const result = await simulateWorkerSts({ fetch: async () => response(value, status) });
    assert.deepEqual(result, empty);
    assert.doesNotMatch(JSON.stringify(result), /private|synthetic-token/);
  }
});

test('oversize, shared-backed, too many chunks and stream failures refuse', async () => {
  for (const chunks of [[new Uint8Array(65537)], [new Uint8Array(new SharedArrayBuffer(1))],
    [...Array.from({ length: 1025 }, () => new Uint8Array(0)), new TextEncoder().encode(JSON.stringify(token))]]) {
    let index = 0;
    const reader = { async read() { return index < chunks.length ? { done: false, value: chunks[index++] } : { done: true }; },
      async cancel() {}, releaseLock() {} };
    const result = await simulateWorkerSts({ fetch: async () => ({ status: 200, redirected: false, body: { getReader: () => reader } }) });
    assert.deepEqual(result, empty);
  }
  assert.deepEqual(await simulateWorkerSts({ fetch: async () => { throw new Error('private failure'); } }), empty);
});

test('snapshot isolates mutable stream chunks before the next await', async () => {
  const chunk = new TextEncoder().encode(JSON.stringify(token));
  let count = 0;
  const reader = { async read() { if (count++ === 0) return { done: false, value: chunk }; chunk.fill(120); return { done: true }; },
    async cancel() {}, releaseLock() {} };
  const result = await simulateWorkerSts({ fetch: async () => ({ status: 200, redirected: false, body: { getReader: () => reader } }) });
  assert.equal(result.state, 'synthetic_match');
});

test('reader cleanup failure never reports an apparently successful exchange', async () => {
  let count = 0;
  const reader = { async read() { return count++ ? { done: true } : { done: false, value: new TextEncoder().encode(JSON.stringify(token)) }; },
    async cancel() {}, releaseLock() { throw new Error('private-cleanup'); } };
  assert.deepEqual(await simulateWorkerSts({ fetch: async () => ({ status: 200, redirected: false, body: { getReader: () => reader } }) }), empty);
});

test('cumulative byte limit stops reading before the next chunk', async () => {
  const chunks = [new Uint8Array(65536), new Uint8Array(1)];
  let reads = 0, canceled = false;
  const reader = { async read() { reads++; return chunks.length ? { done: false, value: chunks.shift() } : { done: true }; },
    async cancel() { canceled = true; }, releaseLock() {} };
  assert.deepEqual(await simulateWorkerSts({ fetch: async () => ({ status: 200, redirected: false, body: { getReader: () => reader } }) }), empty);
  assert.equal(reads, 2);
  assert.equal(canceled, true);
});

test('timeout and late response cannot establish identity or emit token', async () => {
  let signal;
  const result = await simulateWorkerSts({ fetch: async (_url, init) => { signal = init.signal; return new Promise(() => {}); } }, 10);
  assert.deepEqual(result, empty);
  assert.equal(signal.aborted, true);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { receiveSyntheticRequest, runSyntheticWorker } from './holder-synthetic-identity-path.mjs';

const claims = () => ({ issuer: 'synthetic-issuer', audience: 'https://synthetic.invalid/receiver', subject: 'synthetic-worker' });
const request = () => JSON.stringify({ token: 'synthetic-id-token', command: 'synthetic-probe', nonce: '0123456789abcdef0123456789abcdef' });
const verifier = async () => claims();
const binding = async () => true;

test('receiver refuses absent or mismatched verified identity and malformed commands', async () => {
  assert.equal((await receiveSyntheticRequest(request())).state, 'unknown');
  for (const key of Object.keys(claims())) {
    const altered = claims(); altered[key] += '-wrong';
    assert.equal((await receiveSyntheticRequest(request(), async () => altered, binding)).state, 'unknown', key);
  }
  assert.equal((await receiveSyntheticRequest(request().replace('synthetic-probe', 'other'), verifier, binding)).state, 'unknown');
  assert.equal((await receiveSyntheticRequest(request().replace('0123456789abcdef', '1123456789abcdef'), verifier, binding)).state, 'unknown');
  assert.equal((await receiveSyntheticRequest(request().replace('synthetic-id-token', 'actual-token'), verifier, binding)).state, 'unknown');
  assert.equal((await receiveSyntheticRequest(request() + ' ', verifier, binding)).state, 'unknown');
  assert.equal((await receiveSyntheticRequest(request(), async () => { throw Error('private'); }, binding)).state, 'unknown');
  assert.equal((await receiveSyntheticRequest(request(), verifier, binding)).state, 'synthetic_match');
});

test('worker sends only fixed requests and accepts only fixed receiver response', async () => {
  const calls = [];
  const exchange = async req => { calls.push(req); return 'synthetic-id-token'; };
  const transport = async req => { calls.push(req); return receiveSyntheticRequest(req.body, verifier, binding); };
  assert.equal((await runSyntheticWorker(exchange, transport)).state, 'synthetic_match');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].audience, 'https://synthetic.invalid/receiver');
  assert.equal(calls[1].body, request());
  assert.equal((await runSyntheticWorker(async () => 'real-secret', transport)).state, 'unknown');
  assert.equal((await runSyntheticWorker(exchange, async () => ({ state: 'synthetic_match', extra: 'private' }))).state, 'unknown');
  assert.equal((await runSyntheticWorker(exchange, async () => { throw Error('private'); })).state, 'unknown');
  assert.equal((await runSyntheticWorker()).state, 'unknown');
});

test('unresponsive dependencies are bounded and never authorize', async () => {
  const never = () => new Promise(() => {});
  assert.deepEqual(await receiveSyntheticRequest(request(), never, binding, 10), { state: 'unknown', capture_authorized: false, cleanup_authorized: false });
  assert.deepEqual(await runSyntheticWorker(never, never, 10), { state: 'unknown', capture_authorized: false, cleanup_authorized: false });
});

test('binding seam is required and models one-use replay refusal independently', async () => {
  assert.equal((await receiveSyntheticRequest(request(), verifier)).state, 'unknown');
  let used = false;
  const oneUse = async input => {
    assert.equal(input.subject, 'synthetic-worker');
    assert.equal(input.command, 'synthetic-probe');
    assert.equal(input.nonce, '0123456789abcdef0123456789abcdef');
    if (used) return false;
    used = true; return true;
  };
  assert.equal((await receiveSyntheticRequest(request(), verifier, oneUse)).state, 'synthetic_match');
  assert.equal((await receiveSyntheticRequest(request(), verifier, oneUse)).state, 'unknown');
});

test('timed out verifier result is never inspected or sent to binding', async () => {
  let resolveVerifier, inspected = false, called = false;
  const pending = new Promise(resolve => { resolveVerifier = resolve; });
  const result = await receiveSyntheticRequest(request(), () => pending, () => { called = true; return true; }, 10);
  assert.equal(result.state, 'unknown');
  resolveVerifier({ toJSON() { inspected = true; return claims(); } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(inspected, false);
  assert.equal(called, false);
});

test('worker does not send or inspect a response after a synchronous deadline crossing', async () => {
  const block = () => { const end = performance.now() + 30; while (performance.now() < end) {} };
  let sends = 0, inspections = 0;
  const expiredExchange = () => { block(); return 'synthetic-id-token'; };
  const send = () => { sends++; return { toJSON() { inspections++; return {}; } }; };
  assert.equal((await runSyntheticWorker(expiredExchange, send, 10)).state, 'unknown');
  assert.equal(sends, 0);
  const expiredSend = () => { block(); return { toJSON() { inspections++; return {}; } }; };
  assert.equal((await runSyntheticWorker(() => 'synthetic-id-token', expiredSend, 10)).state, 'unknown');
  assert.equal(inspections, 0);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createAuthorityHttpHandler } from './holder-authority-http-boundary.mjs';
const subject = '123456789012345678901', audience = 'https://synthetic.invalid/authority';
const config = JSON.stringify({ audience, subjects: [{ subject, role: 'administrator' }] });
const pair = await generateKeyPair('RS256', { extractable: true, modulusLength: 2048 });
const key = { ...(await exportJWK(pair.publicKey)), kid: 'synthetic-key', alg: 'RS256', use: 'sig' };
const jwks = JSON.stringify({ keys: [key] });
const token = await new SignJWT({ role: 'supervisor' }).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' }).setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).setIssuedAt().setExpirationTime('1m').sign(pair.privateKey);
const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32), manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
const command = { action: 'arm', operation_id: base.operation_id, generation: base.generation, manifest_sha256: base.manifest_sha256, command_id: '1'.repeat(32), expected_revision: 0, expected_state: 'unarmed' };
const body = JSON.stringify({ base, command, clock: { lower_ms: 90000, upper_ms: 90010 } });
const headers = ['Authorization', `Bearer ${token}`, 'Content-Type', 'application/json'];
const request = (text = body, overrides = {}) => ({ method: 'POST', url: '/v1/intent', rawHeaders: headers, async *[Symbol.asyncIterator]() { yield Buffer.from(text); }, ...overrides });
async function call(handler, req = request()) { let status, payload; const response = { writeHead(s) { status = s; }, end(text) { payload = JSON.parse(text); } }; await handler(req, response); return { status, payload }; }
const accept = async () => true, keys = async () => jwks;

test('signed identity, allowed role and replay seam produce only unverified intent', async () => {
  const handler = createAuthorityHttpHandler(config, keys, accept);
  const out = await call(handler);
  assert.equal(out.status, 200); assert.equal(out.payload.state, 'prepared_unverified');
  assert.match(out.payload.intent_sha256, /^[0-9a-f]{64}$/); assert.equal(out.payload.capture_authorized, false); assert.equal(out.payload.cleanup_authorized, false);
  assert.equal(JSON.stringify(out).includes(token), false);
});

test('default dependencies, wrong role, invalid headers and noncanonical body refuse', async () => {
  for (const h of [createAuthorityHttpHandler(), createAuthorityHttpHandler(config, keys), createAuthorityHttpHandler(config, keys, async () => false)])
    assert.equal((await call(h)).status, 403);
  const handler = createAuthorityHttpHandler(config, keys, accept);
  const disallowed = JSON.stringify({ base, command: { ...command, action: 'seal', expected_state: 'capturing', expected_revision: 2 }, clock: { lower_ms: 90000, upper_ms: 90010 } });
  for (const req of [request(disallowed), request(body + ' '), request(body, { method: 'GET' }), request(body, { url: '/v1/intent?x=1' }), request(body, { rawHeaders: [...headers, 'authorization', `Bearer ${token}`] }), request(body, { rawHeaders: ['Authorization', 'Bearer fake', 'Content-Type', 'application/json'] })])
    assert.equal((await call(handler, req)).status, 403);
});

test('replay refusal, bounded streams and dependency failures remain unverified', async () => {
  let used = false;
  const handler = createAuthorityHttpHandler(config, keys, async () => { if (used) return false; used = true; return true; });
  assert.equal((await call(handler)).status, 200); assert.equal((await call(handler)).status, 403);
  const broken = createAuthorityHttpHandler(config, async () => { throw Error('private'); }, accept);
  assert.equal((await call(broken)).status, 403);
  const oversized = request('x'.repeat(16385));
  assert.equal((await call(createAuthorityHttpHandler(config, keys, accept), oversized)).status, 403);
});

test('late or malformed key-source output never reaches replay seam', async () => {
  let replayCalls = 0;
  const replay = async () => { replayCalls++; return true; };
  const bad = createAuthorityHttpHandler(config, async () => ({ toString() { throw Error('private'); } }), replay);
  assert.equal((await call(bad)).status, 403);
  const blocked = createAuthorityHttpHandler(config, () => new Promise(() => {}), replay);
  assert.equal((await call(blocked)).status, 403);
  assert.equal(replayCalls, 0);
});

test('chunk limit refuses before reading subsequent valid input', async () => {
  let reads = 0;
  const req = request(body, { async *[Symbol.asyncIterator]() { for (let i = 0; i < 1025; i++) { reads++; yield Buffer.alloc(0); } reads++; yield Buffer.from(body); } });
  const out = await call(createAuthorityHttpHandler(config, keys, accept), req);
  assert.equal(out.status, 403); assert.equal(reads, 1025);
});

test('fixed role/action partition permits only its documented combinations', async () => {
  const states = { prepare: ['unprepared', 0], arm: ['unarmed', 0], revoke: ['unarmed', 0], begin_capture: ['armed', 1], seal: ['capturing', 2], report_attempt: ['sealed', 3], report_verified: ['deleting', 4] };
  const allowed = { administrator: ['prepare', 'arm', 'revoke'], collector: ['begin_capture', 'seal'], worker: ['report_attempt'], verifier: ['report_verified'] };
  for (const [role, actions] of Object.entries(allowed)) {
    const pins = JSON.stringify({ audience, subjects: [{ subject, role }] });
    const handler = createAuthorityHttpHandler(pins, keys, accept);
    for (const [action, [expected_state, expected_revision]] of Object.entries(states)) {
      const text = JSON.stringify({ base, command: { ...command, action, expected_state, expected_revision }, clock: { lower_ms: 90000, upper_ms: 90010 } });
      assert.equal((await call(handler, request(text))).status, actions.includes(action) ? 200 : 403, `${role}/${action}`);
    }
  }
});

test('a parse crossing the deadline never invokes key source', async () => {
  const original = JSON.parse; let calls = 0, blocked = false;
  JSON.parse = function (value, ...args) {
    if (value === body) { blocked = true; const until = performance.now() + 1050; while (performance.now() < until) {} }
    return original.call(this, value, ...args);
  };
  try {
    const handler = createAuthorityHttpHandler(config, async () => { calls++; return jwks; }, accept);
    assert.equal((await call(handler)).status, 403); assert.equal(blocked, true); assert.equal(calls, 0);
  } finally { JSON.parse = original; }
});

test('rejects ambiguous or inconsistent HTTP framing headers', async () => {
  const handler = createAuthorityHttpHandler(config, keys, accept);
  const byteLength = String(Buffer.byteLength(body));
  assert.equal((await call(handler, request(body, { rawHeaders: [...headers, 'Content-Length', byteLength] }))).status, 200);
  for (const extra of [['Content-Length', byteLength, 'content-length', byteLength], ['Content-Length', byteLength, 'Transfer-Encoding', 'chunked'], ['Transfer-Encoding', 'chunked', 'transfer-encoding', 'chunked'], ['Content-Length', '1'], ['Transfer-Encoding', 'gzip']])
    assert.equal((await call(handler, request(body, { rawHeaders: [...headers, ...extra] }))).status, 403);
});

test('timeout destroys a hung request and late iterator data cannot reach key source', async () => {
  let destroyed = 0, release, keyCalls = 0;
  const pending = new Promise(resolve => { release = resolve; });
  const req = request(body, { destroy() { destroyed++; }, async *[Symbol.asyncIterator]() { await pending; yield Buffer.from(body); } });
  const handler = createAuthorityHttpHandler(config, async () => { keyCalls++; return jwks; }, accept);
  assert.equal((await call(handler, req)).status, 403);
  assert.equal(destroyed, 1);
  release(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(keyCalls, 0);
});

test('early refusal destroys request without exposing cleanup errors', async () => {
  let destroyed = 0;
  const req = request(body, { method: 'GET', destroy() { destroyed++; throw Error('private cleanup'); } });
  const result = await call(createAuthorityHttpHandler(config, keys, accept), req);
  assert.equal(result.status, 403); assert.equal(destroyed, 1);
  assert.equal(JSON.stringify(result).includes('private cleanup'), false);
});

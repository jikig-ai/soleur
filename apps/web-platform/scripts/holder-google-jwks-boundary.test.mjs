import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { prepareGoogleJwksVerifier } from './holder-google-jwks-boundary.mjs';
const url = 'https://www.googleapis.com/oauth2/v3/certs';
const audience = 'https://synthetic.invalid/authority';
const subject = '123456789012345678901';
const config = JSON.stringify({ audience, subjects: [{ subject, role: 'collector' }] });
const { publicKey, privateKey } = await generateKeyPair('RS256', { extractable: true, modulusLength: 2048 });
const key = { ...(await exportJWK(publicKey)), kid: 'synthetic-key', alg: 'RS256', use: 'sig' };
const body = JSON.stringify({ keys: [key] });
const response = (overrides = {}) => ({ status: 200, url, redirected: false,
  headers: new Headers({ 'content-type': 'application/json', 'cache-control': 'public, max-age=3600', date: new Date().toUTCString(), age: '0' }),
  body: new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode(body)); controller.close(); } }), ...overrides });
const transport = async () => response();
const token = await new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' }).setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).setIssuedAt().setExpirationTime('1m').sign(privateKey);

test('fetches only fixed endpoint and verifies synthetic key snapshot, with no authorization', async () => {
  let request;
  const prepared = await prepareGoogleJwksVerifier(config, async (u, opts) => { request = { u, opts }; return response(); });
  assert.equal(request.u, url); assert.equal(request.opts.redirect, 'error'); assert.equal(request.opts.method, 'GET');
  assert.equal(request.opts.credentials, 'omit');
  assert.equal(prepared.state, 'prepared_untrusted_transport');
  assert.equal((await prepared.verifier.verify(token)).state, 'signature_verified_untrusted_keys');
});

test('refuses spoofed endpoint, redirect, stale or malformed responses', async () => {
  for (const r of [response({ url: 'https://evil.invalid/' }), response({ redirected: true }), response({ status: 302 }),
    response({ headers: new Headers({ 'content-type': 'application/json', 'cache-control': 'max-age=10', date: new Date(Date.now()-60000).toUTCString() }) }),
    response({ headers: new Headers({ 'content-type': 'application/json', 'cache-control': 'no-cache="field", max-age=3600', date: new Date().toUTCString() }) }),
    response({ headers: new Headers({ 'content-type': 'application/json', 'cache-control': 'max-age=3600, max-age=bogus', date: new Date().toUTCString() }) }),
    response({ body: new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('{bad')); c.close(); } }) })]) {
    assert.equal((await prepareGoogleJwksVerifier(config, async () => r)).state, 'unknown');
  }
  assert.equal((await prepareGoogleJwksVerifier(config)).state, 'unknown');
  assert.equal((await prepareGoogleJwksVerifier({}, transport)).state, 'unknown');
});

test('rotation uses fresh snapshot and outage never serves prior keys', async () => {
  const first = await prepareGoogleJwksVerifier(config, transport);
  assert.equal((await first.verifier.verify(token)).state, 'signature_verified_untrusted_keys');
  const rotated = await generateKeyPair('RS256', { extractable: true, modulusLength: 2048 });
  const rotatedKey = { ...(await exportJWK(rotated.publicKey)), kid: 'other-key', alg: 'RS256', use: 'sig' };
  const r = response({ body: new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(JSON.stringify({keys:[rotatedKey]}))); c.close(); } }) });
  const second = await prepareGoogleJwksVerifier(config, async () => r);
  assert.equal((await second.verifier.verify(token)).state, 'unknown');
  assert.equal((await prepareGoogleJwksVerifier(config, async () => { throw Error('secret'); })).state, 'unknown');
});

test('bounds hung transport, empty chunks and oversized input', async () => {
  assert.equal((await prepareGoogleJwksVerifier(config, () => new Promise(() => {}), 10)).state, 'unknown');
  const empty = response({ body: new ReadableStream({ pull(c) { c.enqueue(new Uint8Array(0)); } }) });
  assert.equal((await prepareGoogleJwksVerifier(config, async () => empty)).state, 'unknown');
  const big = response({ body: new ReadableStream({ start(c) { c.enqueue(new Uint8Array(65537)); c.close(); } }) });
  assert.equal((await prepareGoogleJwksVerifier(config, async () => big)).state, 'unknown');
});

test('a prepared verifier refuses keys after their freshness interval', async () => {
  const prepared = await prepareGoogleJwksVerifier(config, transport);
  assert.equal(prepared.state, 'prepared_untrusted_transport');
  const realNow = Date.now;
  try {
    Date.now = () => realNow() + 3601000;
    assert.equal((await prepared.verifier.verify(token)).state, 'unknown');
  } finally { Date.now = realNow; }
});

test('refuses hostile chunk size and synchronous transport beyond deadline', async () => {
  const chunk = new Uint8Array(32769);
  Object.defineProperty(chunk, 'byteLength', { value: 1 });
  const r = response({ body: new ReadableStream({ start(c) { c.enqueue(chunk); c.close(); } }) });
  assert.equal((await prepareGoogleJwksVerifier(config, async () => r)).state, 'unknown');
  let read = false;
  const slow = () => {
    const end = performance.now() + 30;
    while (performance.now() < end) {}
    return { get status() { read = true; return 200; } };
  };
  assert.equal((await prepareGoogleJwksVerifier(config, slow, 10)).state, 'unknown');
  assert.equal(read, false);
});

test('response transit consumes freshness even when Age dominates Date', async () => {
  const futureDate = new Date(Date.now() + 30000).toUTCString();
  const prepared = await prepareGoogleJwksVerifier(config, async () => {
    await new Promise(resolve => setTimeout(resolve, 200));
    return response({ headers: new Headers({ 'content-type': 'application/json', 'cache-control': 'max-age=1', date: futureDate, age: '0' }) });
  });
  assert.equal(prepared.state, 'prepared_untrusted_transport');
  const realNow = Date.now;
  try {
    Date.now = () => realNow() + 900;
    assert.equal((await prepared.verifier.verify(token)).state, 'unknown');
  } finally { Date.now = realNow; }
});

test('chunk cap prevents reading a subsequent valid JSON body', async () => {
  let reads = 0;
  const reader = { async read() { reads++; return reads <= 1025 ? { done: false, value: new Uint8Array(0) } : reads === 1026 ? { done: false, value: new TextEncoder().encode(body) } : { done: true }; }, cancel() {}, releaseLock() {} };
  const prepared = await prepareGoogleJwksVerifier(config, async () => response({ body: { getReader: () => reader } }));
  assert.equal(prepared.state, 'unknown');
  assert.equal(reads, 1025);
});

test('byte cap refuses before allocating an oversized valid JSON snapshot', async () => {
  const bytes = new TextEncoder().encode(body + ' '.repeat(32769 - body.length));
  assert.equal(JSON.parse(new TextDecoder().decode(bytes)).keys.length, 1);
  const original = Buffer.allocUnsafe;
  let oversizedAllocations = 0;
  Buffer.allocUnsafe = function (size, ...rest) { if (size > 32768) oversizedAllocations++; return original.call(this, size, ...rest); };
  try {
    Buffer.allocUnsafe(32769);
    assert.equal(oversizedAllocations, 1);
    oversizedAllocations = 0;
    const r = response({ body: new ReadableStream({ start(c) { c.enqueue(bytes); c.close(); } }) });
    assert.equal((await prepareGoogleJwksVerifier(config, async () => r)).state, 'unknown');
    assert.equal(oversizedAllocations, 0);
  } finally { Buffer.allocUnsafe = original; }
});

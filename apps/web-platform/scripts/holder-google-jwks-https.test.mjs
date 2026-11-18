import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createGoogleJwksHttpsTransport } from './holder-google-jwks-https.mjs';
import { prepareGoogleJwksVerifier } from './holder-google-jwks-boundary.mjs';
const url = 'https://www.googleapis.com/oauth2/v3/certs';
const config = JSON.stringify({ audience: 'https://synthetic.invalid/authority', subjects: [{ subject: '123456789', role: 'collector' }] });
const options = signal => ({ method: 'GET', redirect: 'error', credentials: 'omit', signal });
function stub({ status = 200, chunks = [Buffer.from('{"keys":[{}]}')], headers = { 'content-type': 'application/json', 'cache-control': 'public, max-age=3600', date: new Date().toUTCString(), age: '0' }, hang = false } = {}) {
  const calls = [];
  const request = (opts, callback) => {
    calls.push(opts);
    const req = new EventEmitter(); req.destroy = () => {}; req.end = () => {
      if (hang) return;
      queueMicrotask(() => { const res = new EventEmitter(); res.statusCode = status; res.headers = headers; res.destroy = () => {};
        callback(res); for (const chunk of chunks) res.emit('data', chunk); res.emit('end'); });
    };
    return req;
  };
  return { request, calls };
}

test('uses pinned TLS endpoint without ambient credentials or proxy', async () => {
  const s = stub(); const fetcher = createGoogleJwksHttpsTransport(s.request);
  const result = await fetcher(url, options(new AbortController().signal));
  assert.equal(result.url, url); assert.equal(result.redirected, false); assert.equal(result.status, 200);
  assert.deepEqual(s.calls[0], { protocol: 'https:', hostname: 'www.googleapis.com', port: 443, servername: 'www.googleapis.com', path: '/oauth2/v3/certs', method: 'GET', agent: false, rejectUnauthorized: true, headers: { accept: 'application/json' } });
  assert.equal((await prepareGoogleJwksVerifier(config, fetcher)).state, 'prepared_untrusted_transport');
});

test('rejects target, method, redirect and status before consumption', async () => {
  const s = stub(); const fetcher = createGoogleJwksHttpsTransport(s.request); const signal = new AbortController().signal;
  await assert.rejects(fetcher('https://evil.invalid', options(signal)), { message: 'jwks_transport_failed' });
  await assert.rejects(fetcher(url, { ...options(signal), method: 'POST' }), { message: 'jwks_transport_failed' });
  assert.equal(s.calls.length, 0);
  for (const status of [301, 302, 403, 500]) await assert.rejects(createGoogleJwksHttpsTransport(stub({ status }).request)(url, options(signal)), { message: 'jwks_transport_failed' });
});

test('bounds timeout, chunks, actual byte lengths and sanitizes exceptions', async () => {
  const signal = new AbortController().signal;
  const chunk = Buffer.alloc(32769); Object.defineProperty(chunk, 'byteLength', { value: 1 });
  for (const input of [{ chunks: [chunk] }, { chunks: Array.from({ length: 1025 }, () => Buffer.alloc(0)) }, { hang: true }])
    await assert.rejects(createGoogleJwksHttpsTransport(stub(input).request)(url, options(signal)), { message: 'jwks_transport_failed' });
  await assert.rejects(createGoogleJwksHttpsTransport(() => { throw Error('secret'); })(url, options(signal)), { message: 'jwks_transport_failed' });
  const controller = new AbortController(); controller.abort();
  const s = stub(); await assert.rejects(createGoogleJwksHttpsTransport(s.request)(url, options(controller.signal)), { message: 'jwks_transport_failed' });
  assert.equal(s.calls.length, 0);
});

test('refuses fake signal and destroys a synchronously returned request after early failure', async () => {
  const s = stub();
  await assert.rejects(createGoogleJwksHttpsTransport(s.request)(url, options({ aborted: false })), { message: 'jwks_transport_failed' });
  assert.equal(s.calls.length, 0);
  let destroyed = false;
  const early = (_opts, callback) => {
    const res = new EventEmitter(); res.statusCode = 302; res.destroy = () => {};
    callback(res);
    const req = new EventEmitter(); req.destroy = () => { destroyed = true; }; req.end = () => { throw Error('must not start'); };
    return req;
  };
  await assert.rejects(createGoogleJwksHttpsTransport(early)(url, options(new AbortController().signal)), { message: 'jwks_transport_failed' });
  assert.equal(destroyed, true);
});

test('does not resolve after synchronous response construction crosses deadline', async () => {
  const original = Buffer.concat; let blocked = false;
  Buffer.concat = function (...args) {
    blocked = true; const until = performance.now() + 1050; while (performance.now() < until) {}
    return original.apply(this, args);
  };
  try {
    await assert.rejects(createGoogleJwksHttpsTransport(stub().request)(url, options(new AbortController().signal)), { message: 'jwks_transport_failed' });
    assert.equal(blocked, true);
  } finally { Buffer.concat = original; }
});

test('synthetic HTTPS through JWKS to a valid RSA identity signature', async () => {
  const pair = await generateKeyPair('RS256', { extractable: true, modulusLength: 2048 });
  const key = { ...(await exportJWK(pair.publicKey)), kid: 'synthetic-key', alg: 'RS256', use: 'sig' };
  const payload = Buffer.from(JSON.stringify({ keys: [key] }));
  const token = await new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' }).setIssuer('https://accounts.google.com')
    .setAudience('https://synthetic.invalid/authority').setSubject('123456789').setIssuedAt().setExpirationTime('1m').sign(pair.privateKey);
  const prepared = await prepareGoogleJwksVerifier(config, createGoogleJwksHttpsTransport(stub({ chunks: [payload] }).request));
  assert.equal(prepared.state, 'prepared_untrusted_transport');
  assert.deepEqual(await prepared.verifier.verify(token), { state: 'signature_verified_untrusted_keys', subject: '123456789', role: 'collector', capture_authorized: false, cleanup_authorized: false });
});

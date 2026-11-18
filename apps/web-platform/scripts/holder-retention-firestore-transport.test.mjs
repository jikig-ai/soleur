import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createHash } from 'node:crypto';
import { makeFirestoreTransport } from './holder-retention-firestore-transport.mjs';
import { validateRestrictedCommit } from './holder-retention-firestore-ledger.mjs';

const apiRoot = ['v1', 'projects'].join('/');
const url = `https://firestore.googleapis.com/${apiRoot}/synthetic-project/databases/holder-ledger/documents/holder_evidence_operations/${'a'.repeat(32)}`;
const expectedBase = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32),
  manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
const target = { projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase };
function syntheticCreateBody() {
  const record = { ...expectedBase,
    schema_version: 1, state: 'unarmed', revision: 0, late: false, receipts: [] };
  return JSON.stringify({ writes: [{ update: { name: `projects/${target.projectId}/databases/${target.databaseId}/documents/holder_evidence_operations/${record.operation_id}`,
    fields: { payload: { stringValue: JSON.stringify(record) } } }, currentDocument: { exists: false } }] });
}

function syntheticForgedArmingBody() {
  const event = { command_id: '1'.repeat(32), from: 'unarmed', to: 'armed', revision: 1,
    lower_ms: 90000, upper_ms: 90000, late: false };
  event.intent_sha256 = createHash('sha256').update(JSON.stringify(['holder-ledger-intent-v1',
    ...Object.values(expectedBase), event.command_id, event.from, event.to, event.revision,
    event.lower_ms, event.upper_ms, event.late])).digest('hex');
  const record = { ...expectedBase, schema_version: 1, state: 'armed', revision: 1, late: false, receipts: [event] };
  return JSON.stringify({ writes: [{ update: { name: `projects/${target.projectId}/databases/${target.databaseId}/documents/holder_evidence_operations/${record.operation_id}`,
    fields: { payload: { stringValue: JSON.stringify(record) } } }, currentDocument: { updateTime: '2026-10-28T00:00:01.000000Z' } }] });
}

function fakeRequest(chunks, status = 200) {
  const calls = [];
  const open = (options, callback) => {
    calls.push(options);
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = () => { request.destroyed = true; };
    request.end = (body) => { options.sentBody = body; process.nextTick(() => {
      const response = new EventEmitter();
      response.statusCode = status;
      response.destroy = () => { response.destroyed = true; };
      callback(response);
      for (const chunk of chunks) { if (!response.destroyed) response.emit('data', Buffer.from(chunk)); }
      if (!response.destroyed) response.emit('end');
    }); };
    return request;
  };
  return { open, calls };
}

test('only the fixed Firestore endpoint receives the token and returns a bounded response', async () => {
  const fake = fakeRequest(['{"ok":true}']);
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: fake.open });
  const result = await transport({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal });
  assert.deepEqual(result, { status: 200, body: '{"ok":true}' });
  assert.equal(fake.calls[0].hostname, 'firestore.googleapis.com');
  assert.equal(fake.calls[0].headers.authorization, 'Bearer synthetic-token');
  assert.equal(JSON.stringify(result).includes('synthetic-token'), false);
});

test('invalid destinations are refused before credentials are requested', async () => {
  let tokenCalls = 0;
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => { tokenCalls++; return 'synthetic-token'; }, requestImpl: () => { throw new Error('private'); } });
  for (const destination of [url.replace('firestore.googleapis.com', 'example.com'), `${url}?extra=1`, url.replace('https:', 'http:'), url.replace('synthetic-project', 'another-project'), url.replace('a'.repeat(32), '9'.repeat(32))]) {
    await assert.rejects(transport({ method: 'GET', url: destination, maxResponseBytes: 65536, signal: new AbortController().signal }), /transport_failed/);
  }
  assert.equal(tokenCalls, 0);
});

test('arbitrary Firestore writes are refused before credentials are requested', async () => {
  let tokenCalls = 0;
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => { tokenCalls++; return 'synthetic-token'; }, requestImpl: () => { throw new Error('private'); } });
  const commit = url.replace(/\/holder_evidence_operations\/.+$/, ':commit');
  const valid = syntheticCreateBody();
  const wrongName = JSON.parse(valid);
  wrongName.writes[0].update.name = wrongName.writes[0].update.name.replace('a'.repeat(32), '9'.repeat(32));
  const badPayload = JSON.parse(valid);
  const record = JSON.parse(badPayload.writes[0].update.fields.payload.stringValue);
  record.raw = 'private';
  badPayload.writes[0].update.fields.payload.stringValue = JSON.stringify(record);
  const otherOperation = JSON.parse(valid);
  const otherRecord = JSON.parse(otherOperation.writes[0].update.fields.payload.stringValue);
  otherRecord.operation_id = '9'.repeat(32);
  otherOperation.writes[0].update.name = otherOperation.writes[0].update.name.replace('a'.repeat(32), otherRecord.operation_id);
  otherOperation.writes[0].update.fields.payload.stringValue = JSON.stringify(otherRecord);
  const otherVault = JSON.parse(valid);
  const otherVaultRecord = JSON.parse(otherVault.writes[0].update.fields.payload.stringValue);
  otherVaultRecord.vault_id = '9'.repeat(32);
  otherVault.writes[0].update.fields.payload.stringValue = JSON.stringify(otherVaultRecord);
  for (const body of ['{"raw":"private"}', JSON.stringify(wrongName), JSON.stringify(badPayload), JSON.stringify(otherOperation), JSON.stringify(otherVault),
    valid.replace('{"writes":', '{"writes":[],"writes":')]) {
    assert.equal(validateRestrictedCommit(body, target.projectId, target.databaseId, expectedBase), false);
    await assert.rejects(transport({ method: 'POST', url: commit, body,
      maxResponseBytes: 65536, signal: new AbortController().signal }), /transport_failed/);
  }
  assert.equal(tokenCalls, 0);
});

test('a fabricated but structurally valid arming write cannot reach credentials or the network', async () => {
  let tokenCalls = 0;
  const fake = fakeRequest(['{}']);
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => { tokenCalls++; return 'synthetic-token'; }, requestImpl: fake.open });
  const commit = url.replace(/\/holder_evidence_operations\/.+$/, ':commit');
  const body = syntheticForgedArmingBody();
  assert.equal(validateRestrictedCommit(body, target.projectId, target.databaseId, expectedBase), true);
  await assert.rejects(transport({ method: 'POST', url: commit, body,
    maxResponseBytes: 65536, signal: new AbortController().signal }), /transport_failed/);
  assert.equal(tokenCalls, 0);
  assert.equal(fake.calls.length, 0);
});

test('oversized responses and provider errors never expose their bodies', async () => {
  const large = fakeRequest(['x'.repeat(65537)]);
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: large.open });
  await assert.rejects(transport({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal }), /transport_failed/);
  const denied = fakeRequest(['private-provider-body'], 403);
  const other = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: denied.open });
  assert.deepEqual(await other({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal }), { status: 403, body: '{}' });
});

test('asynchronous response setup and cleanup errors fail closed without leaking', async () => {
  for (const failure of ['destroy', 'status', 'registration']) {
    let escaped;
    const escape = new Promise(resolve => { escaped = resolve; });
    const open = (_options, callback) => {
      const req = new EventEmitter(); req.setTimeout = () => req; req.destroy = () => {};
      req.end = () => process.nextTick(() => {
        const res = new EventEmitter(); res.statusCode = 403; res.destroy = () => {};
        if (failure === 'destroy') res.destroy = () => { throw new Error('private-destroy'); };
        if (failure === 'status') Object.defineProperty(res, 'statusCode', { get() { throw new Error('private-status'); } });
        if (failure === 'registration') res.on = () => { throw new Error('private-registration'); };
        try { callback(res); } catch { escaped('escaped'); }
      });
      return req;
    };
    const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: open });
    const outcome = await Promise.race([escape, transport({ method: 'GET', url, maxResponseBytes: 16, signal: new AbortController().signal })
      .then(() => 'resolved', e => e.message)]);
    assert.equal(outcome, 'transport_failed', failure);
  }
});

test('the response bounds data events even when they contain zero bytes', async () => {
  const exact = fakeRequest([...Array(1023).fill(''), '{}']);
  const allowed = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: exact.open });
  assert.deepEqual(await allowed({ method: 'GET', url, maxResponseBytes: 2, signal: new AbortController().signal }),
    { status: 200, body: '{}' });
  for (const chunks of [[...Array(1024).fill(''), '{}'], Array(1025).fill('x')]) {
    const source = fakeRequest(chunks);
    const limited = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: source.open });
    await assert.rejects(limited({ method: 'GET', url, maxResponseBytes: 2048, signal: new AbortController().signal }),
      { message: 'transport_failed' });
  }
});

test('streamed chunks use the real view, not shadowed length or valueOf', async () => {
  const directRequest = (chunk) => (_options, callback) => {
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = () => {};
    request.end = () => process.nextTick(() => {
      const response = new EventEmitter(); response.statusCode = 200; response.destroy = () => {};
      callback(response); response.emit('data', chunk); response.emit('end');
    });
    return request;
  };
  const oversized = Buffer.from('123456');
  Object.defineProperty(oversized, 'byteLength', { value: 1 });
  const first = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: directRequest(oversized) });
  await assert.rejects(first({ method: 'GET', url, maxResponseBytes: 5, signal: new AbortController().signal }), /transport_failed/);
  const actual = Buffer.from('good');
  actual.valueOf = () => Buffer.from('evil');
  const second = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: directRequest(actual) });
  assert.equal((await second({ method: 'GET', url, maxResponseBytes: 5, signal: new AbortController().signal })).body, 'good');
});

test('redirects are not followed and streamed byte limits and UTF-8 are enforced', async () => {
  const redirect = fakeRequest(['private'], 302);
  const redirected = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: redirect.open });
  assert.deepEqual(await redirected({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal }), { status: 302, body: '{}' });
  assert.equal(redirect.calls.length, 1);
  const exact = fakeRequest(['123', '45']);
  const exactTransport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: exact.open });
  assert.equal((await exactTransport({ method: 'GET', url, maxResponseBytes: 5, signal: new AbortController().signal })).body, '12345');
  for (const chunks of [['123', '456'], [Buffer.from([0xff])]]) {
    const fake = fakeRequest(chunks);
    const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: fake.open });
    await assert.rejects(transport({ method: 'GET', url, maxResponseBytes: 5, signal: new AbortController().signal }), /transport_failed/);
  }
});

test('an aborted credential lookup never starts a request after it resolves', async () => {
  let release, calls = 0;
  const gate = new Promise((resolve) => { release = resolve; });
  const controller = new AbortController();
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => gate, requestImpl: () => { calls++; } });
  const pending = transport({ method: 'GET', url, maxResponseBytes: 65536, signal: controller.signal });
  controller.abort(); release('synthetic-token');
  await assert.rejects(pending, /transport_failed/);
  assert.equal(calls, 0);
});

test('aborting before the credential microtask prevents both credential and network access', async () => {
  let tokenCalls = 0, requestCalls = 0;
  const controller = new AbortController();
  const transport = makeFirestoreTransport({ ...target,
    getAccessToken: async () => { tokenCalls++; return 'synthetic-token'; },
    requestImpl: () => { requestCalls++; throw new Error('private'); } });
  const pending = transport({ method: 'GET', url, maxResponseBytes: 5, signal: controller.signal });
  controller.abort();
  await assert.rejects(pending, { message: 'transport_failed' });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(tokenCalls, 0);
  assert.equal(requestCalls, 0);
});

test('invalid signal setup is sanitized before credentials or network access', async () => {
  let tokens = 0, requests = 0;
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => { tokens++; return 'synthetic-token'; },
    requestImpl: () => { requests++; throw new Error('private'); } });
  const signal = Object.create(AbortSignal.prototype);
  signal.addEventListener = () => { throw new Error('private-signal-setup'); };
  await assert.rejects(transport({ method: 'GET', url, maxResponseBytes: 5, signal }), { message: 'transport_failed' });
  assert.equal(tokens, 0);
  assert.equal(requests, 0);
});

test('signal own properties cannot alter abort checks, setup or cleanup', async () => {
  const signal = new AbortController().signal;
  Object.defineProperty(signal, 'aborted', { get() { throw new Error('private-abort-getter'); } });
  signal.addEventListener = () => { throw new Error('private-add'); };
  signal.removeEventListener = () => { throw new Error('private-remove'); };
  const fake = fakeRequest(['{}']);
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: fake.open });
  assert.deepEqual(await transport({ method: 'GET', url, maxResponseBytes: 5, signal }), { status: 200, body: '{}' });
});

test('a response that closes before completion is refused without exposing data', async () => {
  const open = (_options, callback) => {
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = () => {};
    request.end = () => process.nextTick(() => {
      const response = new EventEmitter(); response.statusCode = 200; response.destroy = () => {};
      callback(response); response.emit('data', Buffer.from('private')); response.emit('close');
    });
    return request;
  };
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => 'synthetic-token', requestImpl: open });
  let settled = false;
  const pending = transport({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal })
    .then(() => 'unexpected', (failure) => { settled = true; return failure.message; });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(settled, true);
  assert.equal(await pending, 'transport_failed');
});

test('request method, destination and limits cannot change during credential lookup', async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const fake = fakeRequest(['123456']);
  const transport = makeFirestoreTransport({ ...target, getAccessToken: async () => gate, requestImpl: fake.open });
  const input = { method: 'GET', url, maxResponseBytes: 5, signal: new AbortController().signal };
  const pending = transport(input);
  input.method = 'DELETE'; input.url = 'https://example.com/private'; input.maxResponseBytes = 65536;
  release('synthetic-token');
  await assert.rejects(pending, /transport_failed/);
  assert.equal(fake.calls[0].method, 'GET');
  assert.equal(fake.calls[0].hostname, 'firestore.googleapis.com');
});

test('the abort signal stays bound to its validated snapshot', async () => {
  let releaseAgain, calls = 0;
  const secondGate = new Promise((resolve) => { releaseAgain = resolve; });
  const original = new AbortController();
  const next = makeFirestoreTransport({ ...target, getAccessToken: async () => secondGate, requestImpl: () => { calls++; } });
  const nextInput = { method: 'GET', url, maxResponseBytes: 65536, signal: original.signal };
  const canceled = next(nextInput);
  nextInput.signal = new AbortController().signal; original.abort(); releaseAgain('synthetic-token');
  await assert.rejects(canceled, /transport_failed/);
  assert.equal(calls, 0);
});

test('the expected operation base is snapshotted at transport construction', async () => {
  const base = { ...expectedBase };
  const fake = fakeRequest(['{}']);
  const transport = makeFirestoreTransport({ ...target, expectedBase: base, getAccessToken: async () => 'synthetic-token', requestImpl: fake.open });
  base.operation_id = '9'.repeat(32);
  const result = await transport({ method: 'GET', url, maxResponseBytes: 65536, signal: new AbortController().signal });
  assert.equal(result.status, 200);
  await assert.rejects(transport({ method: 'GET', url: url.replace('a'.repeat(32), base.operation_id),
    maxResponseBytes: 65536, signal: new AbortController().signal }), /transport_failed/);
});

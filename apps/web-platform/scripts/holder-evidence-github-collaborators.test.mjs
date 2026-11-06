import { test } from 'node:test';
import assert from 'node:assert/strict';
import { collectCollaborators, parseCollaboratorPage } from './holder-evidence-github-collaborators.mjs';

const endpoint = 'https://api.github.com/repos/jikig-ai/soleur/collaborators';
const options = { perPage: 2, maxPages: 3, maxRows: 6, maxBytes: 4096, timeoutMs: 100 };
const row = (id) => ({ id, login: 'private-login', email: 'private-email', permissions: { admin: false, maintain: false, push: true, triage: false, pull: true } });
const bytes = (v) => new TextEncoder().encode(JSON.stringify(v));
const link = (page) => `<${endpoint}?per_page=2&page=${page}>; rel="next"`;
const response = (data, next = null, status = 200) => ({ status, redirected: false, headers: new Headers(next ? { link: next } : {}), body: new ReadableStream({ start(c) { c.enqueue(bytes(data)); c.close(); } }) });
const fake = (pages) => async (url, init) => { assert.equal(init.method, 'GET'); assert.equal(init.redirect, 'error'); assert.ok(init.signal instanceof AbortSignal); assert.match(url, /^https:\/\/api\.github\.com\/repos\/jikig-ai\/soleur\/collaborators\?per_page=2&page=[12]$/); return pages.shift(); };

test('projects only numeric ids and permission flags', () => {
  const result = parseCollaboratorPage(bytes([row(1)]), null, { ...options, page: 1 });
  assert.deepEqual(result, { collaborators: [{ id: 1, permissions: { admin: false, maintain: false, push: true, triage: false, pull: true } }], next: false, lastPage: null });
  assert.doesNotMatch(JSON.stringify(result), /private/);
});

test('validates data, links, bounds and repository binding', () => {
  for (const bad of [bytes([{ ...row(1), id: 0 }]), bytes([{ ...row(1), permissions: { push: 'yes' } }]), bytes([row(1), row(1)]), new Uint8Array([255])]) assert.throws(() => parseCollaboratorPage(bad, null, { ...options, page: 1 }), /collaborator_page_invalid/);
  for (const bad of [`<https://evil.example/repos/jikig-ai/soleur/collaborators?per_page=2&page=2>; rel="next"`, `<${endpoint}?per_page=2&page=3>; rel="next"`, `<${endpoint}?per_page=2&page=2&token=x>; rel="next"`]) assert.throws(() => parseCollaboratorPage(bytes([row(1), row(2)]), bad, { ...options, page: 1 }), /collaborator_page_invalid/);
  assert.throws(() => parseCollaboratorPage(bytes([row(1)]), null, { ...options, page: 1, maxBytes: 1 }), /collaborator_page_invalid/);
});

test('actual page bytes cannot hide behind shadowed byteLength', () => {
  const input = bytes([]);
  Object.defineProperty(input, 'byteLength', { value: 1 });
  assert.throws(() => parseCollaboratorPage(input, null, { ...options, page: 1, maxBytes: 1 }), /collaborator_page_invalid/);
});

test('collaborator parser refuses changing accessor options without invoking them', () => {
  let reads = 0;
  const input = { ...options, page: 1 };
  Object.defineProperty(input, 'maxBytes', { get() { return ++reads === 1 ? 1 : 4096; } });
  assert.throws(() => parseCollaboratorPage(bytes([]), null, input), /collaborator_page_invalid/);
  assert.equal(reads, 0);
});

test('each traversal snapshots a chunk before awaiting the next one', async () => {
  const fetchPage = async () => {
    const chunk = bytes([]);
    let calls = 0;
    const reader = { async read() { if (calls++ === 0) return { done: false, value: chunk }; chunk.fill(0x78); return { done: true }; },
      async cancel() {}, releaseLock() {} };
    return { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  };
  const result = await collectCollaborators(fetchPage, options);
  assert.equal(result.state, 'complete');
  assert.deepEqual(result.collaborators, []);
  assert.equal(result.writer_clearance, false);
});

test('reader rejects oversized streamed views with shadowed byteLength', async () => {
  const chunk = bytes([]);
  Object.defineProperty(chunk, 'byteLength', { value: 1 });
  let calls = 0;
  const reader = { async read() { return calls++ ? { done: true } : { done: false, value: chunk }; }, async cancel() {}, releaseLock() {} };
  const fetchPage = async () => ({ status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } });
  const result = await collectCollaborators(fetchPage, { ...options, maxBytes: 1 });
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.collaborators, []);
});

test('collection pins limits before an asynchronous fetch can change them', async () => {
  const mutable = { ...options, maxBytes: 2, timeoutMs: 1000 };
  const fetchPage = async () => {
    mutable.maxBytes = 4096;
    mutable.maxRows = 10000;
    mutable.perPage = 100;
    mutable.maxPages = 100;
    mutable.timeoutMs = 60000;
    return response([row(1)]);
  };
  const result = await collectCollaborators(fetchPage, mutable);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.collaborators, []);
});

test('collection separately pins page and row limits across reader calls', async () => {
  for (const field of ['perPage', 'maxRows']) {
    const mutable = { ...options, perPage: field === 'perPage' ? 1 : 2, maxRows: field === 'maxRows' ? 1 : 2, timeoutMs: 1000 };
    const fetchPage = async () => {
      mutable[field] = 2;
      return response([row(1), row(2)]);
    };
    const result = await collectCollaborators(fetchPage, mutable);
    assert.equal(result.state, 'partial', field);
    assert.deepEqual(result.collaborators, [], field);
  }
  const mutable = { ...options, maxPages: 1, timeoutMs: 1000 };
  let calls = 0;
  const fetchPage = async () => {
    calls++;
    mutable.maxPages = 3;
    return response([row(1), row(2)], link(2));
  };
  const result = await collectCollaborators(fetchPage, mutable);
  assert.equal(result.state, 'partial');
  assert.equal(calls, 1);
});

test('reader bounds empty chunks and accepts a short finite prefix', async () => {
  let reads = 0, canceled = false;
  const fetchPage = (emptyCount) => async () => {
    let count = 0;
    const reader = { async read() { reads++; count++; if (count <= emptyCount) return { done: false, value: new Uint8Array(0) };
      return count === emptyCount + 1 ? { done: false, value: bytes([]) } : { done: true }; },
    async cancel() { canceled = true; }, releaseLock() {} };
    return { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  };
  assert.equal((await collectCollaborators(fetchPage(3), { ...options, timeoutMs: 1000 })).state, 'complete');
  reads = 0;
  const result = await collectCollaborators(fetchPage(5000), { ...options, timeoutMs: 1000 });
  assert.equal(result.state, 'partial');
  assert.equal(reads, 4097);
  assert.equal(canceled, true);
});

test('reader release errors make observation partial without exposing text', async () => {
  const fetchPage = async () => {
    let reads = 0;
    const reader = { async read() { return reads++ ? { done: true } : { done: false, value: bytes([]) }; },
      async cancel() {}, releaseLock() { throw new Error('private-release'); } };
    return { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  };
  const result = await collectCollaborators(fetchPage, options);
  assert.equal(result.state, 'partial');
  assert.doesNotMatch(JSON.stringify(result), /private-release/);
});

test('two matching traversals project metadata without granting clearance', async () => {
  const pages = [response([row(1), row(2)], link(2)), response([row(3)]), response([row(1), row(2)], link(2)), response([row(3)])];
  const result = await collectCollaborators(fake(pages), options);
  assert.equal(result.state, 'complete'); assert.deepEqual(result.collaborators.map(x => x.id), [1, 2, 3]);
  assert.equal(result.holder_coverage, 'unknown'); assert.equal(result.workflow_admission, 'unknown'); assert.equal(result.writer_clearance, false);
  assert.doesNotMatch(JSON.stringify(result), /private/);
});

test('duplicates, changed traversals and authorization failures cannot be complete', async () => {
  for (const pages of [
    [response([row(1), row(2)], link(2)), response([row(2)]), response([row(1), row(2)], link(2)), response([row(2)])],
    [response([row(1)]), response([row(2)])],
    [response([], null, 403)],
    [response([row(1), row(2)], link(2)), response([], null, 401)],
  ]) { const result = await collectCollaborators(fake(pages), options); assert.notEqual(result.state, 'complete'); assert.equal(result.holder_coverage, 'unknown'); assert.equal(result.writer_clearance, false); }
});

test('a last link to an unvisited page without next cannot report complete', async () => {
  const last = `<${endpoint}?per_page=2&page=2>; rel="last"`;
  const result = await collectCollaborators(fake([response([row(1), row(2)], last), response([row(1), row(2)], last)]), options);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.collaborators, []);
  assert.equal(result.writer_clearance, false);
  for (const bad of [
    `<${endpoint}?per_page=2&page=1>; rel="next", <${endpoint}?per_page=2&page=2>; rel="last"`,
    `<${endpoint}?per_page=2&page=2>; rel="first"`,
    `<${endpoint}?per_page=2&page=1>; rel="prev"`,
    `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=1>; rel="last"`,
  ]) assert.throws(() => parseCollaboratorPage(bytes([row(1), row(2)]), bad, { ...options, page: 1 }), /collaborator_page_invalid/);
  assert.equal(parseCollaboratorPage(bytes([row(1), row(2)]), `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=2>; rel="last"`, { ...options, page: 1 }).next, true);
});

test('a repeated traversal with contradictory last-page bounds is partial', async () => {
  const first = `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=5>; rel="last"`;
  const second = `<${endpoint}?per_page=2&page=2>; rel="last"`;
  const pages = [response([row(1), row(2)], first), response([row(3)], second),
    response([row(1), row(2)], first), response([row(3)], second)];
  const result = await collectCollaborators(fake(pages), options);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.collaborators, []);
  const withoutLast = link(2);
  const withLast = `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=2>; rel="last"`;
  const changed = [response([row(1), row(2)], withoutLast), response([row(3)]),
    response([row(1), row(2)], withLast), response([row(3)])];
  assert.equal((await collectCollaborators(fake(changed), options)).state, 'partial');
});

test('changed pagination shape cannot be complete even with identical rows', async () => {
  const pages = [response([row(1), row(2)], link(2)), response([]), response([row(1), row(2)])];
  const result = await collectCollaborators(fake(pages), options);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.collaborators, []);
  const shifted = [response([row(1), row(2)], link(2)), response([row(3)]),
    response([row(1), row(3)], link(2)), response([row(2)])];
  assert.equal((await collectCollaborators(fake(shifted), options)).state, 'partial');
});

test('page, row, byte and time limits fail closed', async () => {
  assert.notEqual((await collectCollaborators(fake([response([row(1), row(2)], link(2))]), { ...options, maxPages: 1 })).state, 'complete');
  assert.notEqual((await collectCollaborators(fake([response([row(1), row(2)], link(2)), response([row(3)])]), { ...options, maxRows: 2 })).state, 'complete');
  assert.notEqual((await collectCollaborators(fake([response([row(1)])]), { ...options, maxBytes: 1 })).state, 'complete');
  const result = await collectCollaborators(() => new Promise(() => {}), { ...options, timeoutMs: 10 });
  assert.notEqual(result.state, 'complete');
});

test('a blocked event loop cannot start a second request after the deadline', async () => {
  let calls = 0;
  const result = await collectCollaborators(async () => {
    calls++;
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return response([row(1)]);
  }, { ...options, timeoutMs: 10 });
  assert.notEqual(result.state, 'complete');
  assert.equal(calls, 1);
});

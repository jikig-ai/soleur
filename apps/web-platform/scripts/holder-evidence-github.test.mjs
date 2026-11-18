import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseWorkflowRunPage, readWorkflowRunPage, collectWorkflowRuns, parseWorkflowAdmission, readWorkflowAdmission, collectWorkflowEvidence } from './holder-evidence-github.mjs';

const endpoint = 'https://api.github.com/repos/jikig-ai/soleur/actions/workflows/277913850/runs';
const encode = (runs, total = runs.length) => new TextEncoder().encode(JSON.stringify({ total_count: total, workflow_runs: runs }));
const run = (id, status) => ({ id, status });
const limits = { maxBytes: 4096, page: 1, perPage: 2, endpoint };

test('projects fields before returning a valid first page', () => {
  const bytes = encode([{ id: 1, status: 'queued', secret: 'private' }, { id: 2, status: 'completed' }], 3);
  const link = `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=2>; rel="last"`;
  const result = parseWorkflowRunPage(bytes, link, limits);
  assert.deepEqual(result.workflow_runs, [{ id: 1, status: 'queued' }, { id: 2, status: 'completed' }]);
  assert.equal(result.next, true);
  assert.equal(result.total_count, 3);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('refuses oversized, malformed and unexpected bodies', () => {
  assert.throws(() => parseWorkflowRunPage(new Uint8Array(4097), null, limits));
  assert.throws(() => parseWorkflowRunPage(new TextEncoder().encode('private bad json'), null, limits));
  assert.throws(() => parseWorkflowRunPage(encode([{ id: 1, status: 'secret' }]), null, limits));
  assert.throws(() => parseWorkflowRunPage(encode([], 5), null, limits));
});

test('parsers refuse actual bytes beyond cap even with forged byteLength', () => {
  for (const [bytes, parse] of [[encode([]), b => parseWorkflowRunPage(b, null, { ...limits, maxBytes: 1 })],
    [new TextEncoder().encode(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' })),
      b => parseWorkflowAdmission(b, 277913850, 1)]]) {
    Object.defineProperty(bytes, 'byteLength', { value: 1 });
    assert.throws(() => parse(bytes), /github_page_invalid/);
  }
});

test('workflow parser refuses changing accessor options without invoking them', () => {
  let reads = 0;
  const options = { ...limits };
  Object.defineProperty(options, 'maxBytes', { get() { return ++reads <= 3 ? 1 : 4096; } });
  assert.throws(() => parseWorkflowRunPage(encode([]), null, options), /github_page_invalid/);
  assert.equal(reads, 0);
});

test('reader copies each chunk before awaiting the next read', async () => {
  const chunk = encode([]);
  let calls = 0;
  const reader = { async read() { if (calls++ === 0) return { done: false, value: chunk }; chunk.fill(0x78); return { done: true }; },
    async cancel() {}, releaseLock() {} };
  const response = { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  const result = await readWorkflowRunPage(async () => response, limits, new AbortController().signal);
  assert.deepEqual(result.workflow_runs, []);
});

test('reader rejects oversized streamed views with shadowed byteLength', async () => {
  const chunk = encode([]);
  Object.defineProperty(chunk, 'byteLength', { value: 1 });
  let calls = 0;
  const reader = { async read() { return calls++ ? { done: true } : { done: false, value: chunk }; }, async cancel() {}, releaseLock() {} };
  const response = { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  await assert.rejects(readWorkflowRunPage(async () => response, { ...limits, maxBytes: 1 }, new AbortController().signal), /github_page_invalid/);
});

test('workflow page parsing uses the same per-page limit used to construct its request', async () => {
  const mutable = { ...limits, perPage: 1 };
  let requested;
  const fetchPage = async (url) => {
    requested = url;
    mutable.perPage = 2;
    return new Response(encode([run(1, 'queued'), run(2, 'queued')], 2));
  };
  await assert.rejects(readWorkflowRunPage(fetchPage, mutable, new AbortController().signal), { message: 'github_page_invalid' });
  assert.match(requested, /per_page=1&page=1$/);
});

test('workflow boundaries refuse coercible endpoint objects before any fetch', async () => {
  let calls = 0;
  const endpointObject = () => {
    let coercions = 0;
    return { toString() { return coercions++ === 0 ? endpoint : 'https://attacker.example/runs'; } };
  };
  const fetchPage = async () => { calls++; return new Response(encode([])); };
  await assert.rejects(readWorkflowRunPage(fetchPage, { ...limits, endpoint: endpointObject() }, new AbortController().signal),
    { message: 'github_page_invalid' });
  assert.equal(calls, 0);
  const result = await collectWorkflowRuns(fetchPage, { ...limits, endpoint: endpointObject(), maxPages: 2, maxRuns: 10, timeoutMs: 1000 });
  assert.equal(result.state, 'failed');
  assert.equal(calls, 0);
  assert.throws(() => parseWorkflowRunPage(encode([]), null, { ...limits, endpoint: endpointObject() }), /github_page_invalid/);
});

test('workflow traversal retains its original run cap after a fetch mutates options', async () => {
  const mutable = { ...limits, maxPages: 3, maxRuns: 1, timeoutMs: 1000 };
  const result = await collectWorkflowRuns(async () => {
    mutable.maxRuns = 10;
    mutable.maxPages = 100;
    mutable.timeoutMs = 60000;
    return new Response(encode([run(1, 'queued'), run(2, 'queued')]));
  }, mutable);
  assert.equal(result.state, 'partial');
  assert.equal(result.runs.length, 1);
});

test('reader bounds empty chunk count and permits a small finite empty prefix', async () => {
  async function run(emptyCount) {
    let reads = 0, canceled = false;
    const reader = { async read() { reads++; if (reads <= emptyCount) return { done: false, value: new Uint8Array(0) };
      return reads === emptyCount + 1 ? { done: false, value: encode([]) } : { done: true }; },
    async cancel() { canceled = true; }, releaseLock() {} };
    const response = { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
    const work = readWorkflowRunPage(async () => response, limits, new AbortController().signal);
    return { work, reads: () => reads, canceled: () => canceled };
  }
  const normal = await run(3);
  assert.deepEqual((await normal.work).workflow_runs, []);
  const excessive = await run(5000);
  await assert.rejects(excessive.work, { message: 'github_page_invalid' });
  assert.equal(excessive.reads(), 4097);
  assert.equal(excessive.canceled(), true);
});

test('release failures replace success and never expose arbitrary text', async () => {
  let reads = 0;
  const reader = { async read() { return reads++ ? { done: true } : { done: false, value: encode([]) }; },
    async cancel() {}, releaseLock() { throw new Error('private-release'); } };
  const response = { status: 200, redirected: false, headers: new Headers(), body: { getReader: () => reader } };
  await assert.rejects(readWorkflowRunPage(async () => response, limits, new AbortController().signal), { message: 'github_page_invalid' });
});

test('refuses hostile and ambiguous next links', () => {
  const bytes = encode([{ id: 1, status: 'queued' }, { id: 2, status: 'queued' }], 3);
  for (const link of [
    '<https://attacker.example/runs?page=2>; rel="next"',
    `<${endpoint}?per_page=2&page=3>; rel="next"`,
    `<${endpoint}?per_page=2&page=2&status=queued>; rel="next"`,
    `<${endpoint}?per_page=2&page=2>; rel="next", <${endpoint}?per_page=2&page=2>; rel="next"`,
    'private malformed link',
  ]) assert.throws(() => parseWorkflowRunPage(bytes, link, limits));
});

test('missing next link cannot hide extra results and invalid targets are refused', () => {
  assert.throws(() => parseWorkflowRunPage(encode([{ id: 1, status: 'queued' }, { id: 2, status: 'queued' }], 3), null, limits));
  assert.throws(() => parseWorkflowRunPage(encode([]), null, { ...limits, endpoint: 'https://example.com/runs' }));
  assert.deepEqual(parseWorkflowRunPage(encode([]), null, limits), { workflow_runs: [], details: [], next: false, total_count: 0 });
});

test('contradictory last link is rejected even when total count matches', () => {
  const link = `<${endpoint}?per_page=2&page=2>; rel="last"`;
  assert.throws(() => parseWorkflowRunPage(encode([run(1, 'queued'), run(2, 'queued')]), link, limits));
});

test('run detail projection retains allowlisted metadata and never raw arbitrary strings', async () => {
  const record = { id: 9, status: 'queued', event: 'workflow_dispatch', conclusion: null,
    head_branch: 'private-token-like-branch', triggering_actor: { id: 42, login: 'private-name' },
    actor: { id: 41, login: 'private-name-2' }, secret: 'secret-field' };
  const result = await collectWorkflowRuns(async () => new Response(encode([record])),
    { endpoint, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 5, timeoutMs: 1000 });
  assert.equal(result.state, 'complete');
  assert.equal(result.details_coverage, 'partial');
  assert.equal(result.projection_state, 'complete');
  assert.deepEqual(result.details[0], { id: 9, event: 'workflow_dispatch', conclusion: 'none',
    actor_id: 41, triggering_actor_id: 42, ref_digest: '5fbcbf2b5e066bd70f1629429a3aece076a376993c2944a28fd2874b0085d64e' });
  for (const secret of ['private-token-like-branch', 'private-name', 'secret-field']) assert.equal(JSON.stringify(result).includes(secret), false);
});

test('missing and unrecognized run details remain unknown without echoing values', async () => {
  const record = { id: 10, status: 'queued', event: 'secret-event', conclusion: 'secret-conclusion',
    head_branch: 'x'.repeat(1025), triggering_actor: { id: 'private' } };
  const result = await collectWorkflowRuns(async () => new Response(encode([record])),
    { endpoint, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 5, timeoutMs: 1000 });
  assert.equal(result.details_coverage, 'partial');
  assert.equal(result.projection_state, 'partial');
  assert.deepEqual(result.details[0], { id: 10, event: 'unknown', conclusion: 'unknown', actor_id: 'unknown', triggering_actor_id: 'unknown', ref_digest: 'unknown' });
  assert.equal(JSON.stringify(result).includes('secret-event'), false);
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('reader bounds bytes as they stream and does not return error bodies', async () => {
  const chunks = [new Uint8Array(3000), new Uint8Array(3000)];
  let canceled = false;
  const body = new ReadableStream({ pull(c) { if (chunks.length) c.enqueue(chunks.shift()); else c.close(); }, cancel() { canceled = true; } }, { highWaterMark: 0 });
  const response = new Response(body, { status: 200 });
  await assert.rejects(readWorkflowRunPage(async () => response, limits, new AbortController().signal), { message: 'github_page_invalid' });
  assert.equal(canceled, true);
  await assert.rejects(readWorkflowRunPage(async () => new Response('private error', { status: 403 }), limits, new AbortController().signal), { message: 'github_page_invalid' });
});

test('reader calls only the bound URL with GET and refuses redirects', async () => {
  let requested;
  const response = new Response(encode([]), { status: 200 });
  const result = await readWorkflowRunPage(async (url, init) => { requested = { url, init }; return response; }, limits, new AbortController().signal);
  assert.equal(requested.url, `${endpoint}?per_page=2&page=1`);
  assert.equal(requested.init.method, 'GET');
  assert.equal(requested.init.redirect, 'error');
  assert.deepEqual(result.workflow_runs, []);
  await assert.rejects(readWorkflowRunPage(async () => new Response(null, { status: 302 }), limits, new AbortController().signal), { message: 'github_page_invalid' });
});

test('workflow walk refuses changing totals and duplicate runs across pages', async () => {
  const execute = async (secondTotal, secondId, firstTotal = 3) => collectWorkflowRuns(async (url) => {
    if (url.endsWith('page=1')) return new Response(encode([{ id: 1, status: 'queued' }, { id: 2, status: 'queued' }], firstTotal), {
      headers: { link: `<${endpoint}?per_page=2&page=2>; rel="next"` },
    });
    return new Response(encode([{ id: secondId, status: 'completed' }], secondTotal));
  }, { endpoint, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 5, timeoutMs: 1000 });
  assert.equal((await execute(3, 3)).state, 'complete');
  assert.notEqual((await execute(4, 3)).state, 'complete');
  assert.notEqual((await execute(3, 3, 4)).state, 'complete');
  assert.notEqual((await execute(3, 2)).state, 'complete');
  const threePages = async (change) => collectWorkflowRuns(async (url) => {
    const n = Number(new URL(url).searchParams.get('page'));
    const records = n === 3 ? [run(5, 'queued')] : [run(2 * n - 1, 'queued'), run(2 * n, 'queued')];
    const headers = n < 3 ? { link: `<${endpoint}?per_page=2&page=${n + 1}>; rel="next"` } : {};
    return new Response(encode(records, change && n === 2 ? 6 : 5), { headers });
  }, { endpoint, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 5, timeoutMs: 1000 });
  assert.equal((await threePages(false)).state, 'complete');
  assert.notEqual((await threePages(true)).state, 'complete');
});

test('admission projection binds workflow ID to its exact expected path', () => {
  const payload = { id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active', secret: 'do-not-output' };
  const bytes = new TextEncoder().encode(JSON.stringify(payload));
  const projected = parseWorkflowAdmission(bytes, 277913850, 4096);
  assert.deepEqual(projected, { id: 277913850, path: payload.path, state: 'active' });
  assert.equal(JSON.stringify(projected).includes('do-not-output'), false);
  assert.deepEqual(parseWorkflowAdmission(new TextEncoder().encode(JSON.stringify({ ...payload, state: 'disabled_manually' })), 277913850, 4096).state, 'disabled_manually');
  for (const [id, path] of [[380964769, '.github/workflows/scheduled-integration-suites.yml'], [365691492, '.github/workflows/dev-ledger-reconcile.yml']]) {
    assert.deepEqual(parseWorkflowAdmission(new TextEncoder().encode(JSON.stringify({ id, path, state: 'active' })), id, 4096), { id, path, state: 'active' });
  }
});

test('admission projection refuses mismatched identity, path, state and size', () => {
  const payload = { id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' };
  const bytes = (value) => new TextEncoder().encode(JSON.stringify(value));
  assert.throws(() => parseWorkflowAdmission(bytes(payload), 380964769, 4096));
  assert.throws(() => parseWorkflowAdmission(bytes({ ...payload, id: 380964769 }), 277913850, 4096));
  assert.throws(() => parseWorkflowAdmission(bytes({ ...payload, path: '.github/workflows/other.yml' }), 277913850, 4096));
  assert.throws(() => parseWorkflowAdmission(bytes({ ...payload, state: 'private' }), 277913850, 4096));
  assert.throws(() => parseWorkflowAdmission(bytes(payload), 277913850, 2));
  assert.throws(() => parseWorkflowAdmission(bytes(payload), 999, 4096));
});

test('admission reader uses the fixed read-only endpoint and fails before requests for invalid identity', async () => {
  const payload = { id: 380964769, path: '.github/workflows/scheduled-integration-suites.yml', state: 'active' };
  const calls = [];
  const fetchPage = async (url, init) => { calls.push({ url, init }); return new Response(JSON.stringify(payload)); };
  const signal = new AbortController().signal;
  const result = await readWorkflowAdmission(fetchPage, 380964769, 4096, signal);
  assert.deepEqual(result, payload);
  assert.equal(calls[0].url, 'https://api.github.com/repos/jikig-ai/soleur/actions/workflows/380964769');
  assert.equal(calls[0].init.method, 'GET');
  assert.equal(calls[0].init.redirect, 'error');
  await assert.rejects(readWorkflowAdmission(fetchPage, 999, 4096, signal));
  assert.equal(calls.length, 1);
});

test('workflow evidence checks admission before and after the page walk', async () => {
  let reads = 0;
  const fetchPage = async (url) => {
    if (url.includes('/runs?')) return new Response(encode([]));
    reads++;
    return new Response(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' }));
  };
  const result = await collectWorkflowEvidence(fetchPage, { id: 277913850, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 4, timeoutMs: 1000 });
  assert.equal(reads, 2);
  assert.equal(result.admission.state, 'complete');
  assert.equal(result.runs.state, 'complete');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
});

test('workflow evidence pins its workflow identity across asynchronous reads', async () => {
  const mutable = { id: 277913850, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 4, timeoutMs: 1000 };
  const urls = [];
  const fetchPage = async (url) => {
    urls.push(url);
    mutable.id = 380964769;
    if (url.includes('/runs?')) return new Response(encode([]));
    return new Response(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' }));
  };
  const result = await collectWorkflowEvidence(fetchPage, mutable);
  assert.equal(result.admission.state, 'complete');
  assert.equal(result.runs.state, 'complete');
  assert.equal(urls.length, 3);
  assert.ok(urls.every(url => url.includes('/277913850')));
});

test('workflow evidence keeps drift and failed run collection separately visible', async () => {
  let reads = 0;
  const fetchPage = async (url) => {
    if (url.includes('/runs?')) throw new Error('do-not-emit');
    reads++;
    return new Response(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: reads === 1 ? 'active' : 'disabled_manually' }));
  };
  const result = await collectWorkflowEvidence(fetchPage, { id: 277913850, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 4, timeoutMs: 1000 });
  assert.equal(result.admission.state, 'partial');
  assert.equal(result.runs.state, 'failed');
  assert.equal(result.writer_clearance, false);
  assert.equal(JSON.stringify(result).includes('do-not-emit'), false);
});

test('an uncooperative timed-out admission cannot start later requests', async () => {
  let release;
  let calls = 0;
  const pending = new Promise((resolve) => { release = resolve; });
  const result = await collectWorkflowEvidence(async () => { calls++; return pending; },
    { id: 277913850, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 4, timeoutMs: 10 });
  assert.equal(result.admission.state, 'failed');
  release(new Response(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' })));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls, 1);
});

test('a blocked admission cannot start later requests after the deadline', async () => {
  let calls = 0;
  const result = await collectWorkflowEvidence(() => {
    calls++;
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return new Response(JSON.stringify({ id: 277913850, path: '.github/workflows/tenant-integration.yml', state: 'active' }));
  }, { id: 277913850, maxBytes: 4096, perPage: 2, maxPages: 3, maxRuns: 4, timeoutMs: 10 });
  assert.equal(result.admission.state, 'failed');
  assert.equal(calls, 1);
});

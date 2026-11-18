import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarizeRunPages, collectRunPages, summarizeCoverage } from './holder-evidence-core.mjs';

const page = (runs, next = false) => ({ workflow_runs: runs, next });
const run = (id, status) => ({ id, status });

test('complete pagination projects only numeric IDs and known status', () => {
  const result = summarizeRunPages([
    page([{ ...run(1, 'queued'), secret: 'never-persist-me' }], true),
    page([run(2, 'completed')]),
  ], { maxPages: 3, maxRuns: 4 });
  assert.equal(result.state, 'complete');
  assert.equal(result.scope, 'supplied_page_walk');
  assert.equal(result.writer_clearance, false);
  assert.deepEqual(result.runs, [run(1, 'queued'), run(2, 'completed')]);
  assert.equal(JSON.stringify(result).includes('never-persist-me'), false);
});

test('missing final page or page limit is partial, never complete', () => {
  assert.equal(summarizeRunPages([page([run(1, 'queued')], true)], { maxPages: 3, maxRuns: 4 }).state, 'partial');
  assert.equal(summarizeRunPages([page([run(1, 'queued')], true)], { maxPages: 1, maxRuns: 4 }).state, 'partial');
});

test('invalid response and unknown statuses fail closed without echoing input', () => {
  for (const pages of [[], [{}], [page([run(1, 'sensitive-unknown')])], [page([run('1', 'queued')])]]) {
    const result = summarizeRunPages(pages, { maxPages: 3, maxRuns: 4 });
    assert.notEqual(result.state, 'complete');
    assert.equal(JSON.stringify(result).includes('sensitive-unknown'), false);
  }
});

test('repeated IDs and run caps cannot produce complete census', () => {
  assert.equal(summarizeRunPages([page([run(1, 'queued')], true), page([run(1, 'completed')])], { maxPages: 3, maxRuns: 4 }).state, 'partial');
  assert.equal(summarizeRunPages([page([run(1, 'queued'), run(2, 'queued')])], { maxPages: 3, maxRuns: 1 }).state, 'partial');
});

test('malformed limits and pages after the last page fail closed', () => {
  assert.equal(summarizeRunPages([page([])], { maxPages: 0, maxRuns: 4 }).state, 'failed');
  assert.equal(summarizeRunPages([page([]), page([])], { maxPages: 3, maxRuns: 4 }).state, 'failed');
});

test('page reader follows bounded pages and never returns provider extras', async () => {
  const calls = [];
  const result = await collectRunPages(async (index) => {
    calls.push(index);
    return index === 0 ? page([{ ...run(3, 'queued'), token: 'secret' }], true) : page([run(4, 'completed')]);
  }, { maxPages: 3, maxRuns: 4, timeoutMs: 1000 });
  assert.deepEqual(calls, [0, 1]);
  assert.equal(result.state, 'complete');
  assert.equal(result.writer_clearance, false);
  assert.equal(JSON.stringify(result).includes('secret'), false);
});

test('page reader reports failures without exposing provider exceptions', async () => {
  const result = await collectRunPages(async () => { throw new Error('private credential'); },
    { maxPages: 3, maxRuns: 4, timeoutMs: 1000 });
  assert.equal(result.state, 'failed');
  assert.equal(JSON.stringify(result).includes('private credential'), false);
});

test('page reader stops at page cap and marks unfinished walk partial', async () => {
  let calls = 0;
  const result = await collectRunPages(async () => { calls++; return page([run(calls, 'queued')], true); },
    { maxPages: 2, maxRuns: 4, timeoutMs: 1000 });
  assert.equal(calls, 2);
  assert.equal(result.state, 'partial');
});

test('page reader pins run and page caps before invoking the reader', async () => {
  const limits = { maxPages: 1, maxRuns: 1, timeoutMs: 1000 };
  const result = await collectRunPages(async () => {
    limits.maxRuns = 10;
    limits.maxPages = 10;
    limits.timeoutMs = 60000;
    return page([run(1, 'queued'), run(2, 'queued')]);
  }, limits);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.runs, [run(1, 'queued')]);
});

test('deadline aborts the reader and never treats timeout as an empty census', async () => {
  let aborted = false;
  const result = await collectRunPages((_index, signal) => new Promise((_resolve, reject) => {
    signal.addEventListener('abort', () => { aborted = true; reject(new Error('private timeout')); });
  }), { maxPages: 2, maxRuns: 4, timeoutMs: 10 });
  assert.equal(aborted, true);
  assert.equal(result.state, 'failed');
  assert.equal(JSON.stringify(result).includes('private timeout'), false);
});

test('a blocked event loop cannot produce a complete page walk after the deadline', async () => {
  let calls = 0;
  const result = await collectRunPages(() => {
    calls++;
    const until = performance.now() + 30;
    while (performance.now() < until) { /* synthetic event-loop stall */ }
    return page([]);
  }, { maxPages: 2, maxRuns: 4, timeoutMs: 10 });
  assert.equal(result.state, 'failed');
  assert.equal(calls, 1);
});

test('coverage preserves each missing or failed source as unknown', () => {
  const result = summarizeCoverage({ github_actions: 'complete', database_roles: 'failed' });
  assert.equal(result.sources.github_actions, 'complete');
  assert.equal(result.sources.database_roles, 'failed');
  assert.equal(result.sources.database_sessions, 'unsupported');
  assert.equal(result.sources.supabase, 'unsupported');
  assert.equal(result.sources.doppler, 'unsupported');
  assert.equal(result.sources.deployed_consumers, 'unsupported');
  assert.equal(result.sources.local_agents, 'unsupported');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
});

test('coverage never copies arbitrary fields or accepts malformed source state', () => {
  const result = summarizeCoverage({ github_actions: 'secret', password: 'private credential' });
  assert.equal(result.sources.github_actions, 'failed');
  assert.equal(JSON.stringify(result).includes('secret'), false);
  assert.equal(JSON.stringify(result).includes('private credential'), false);
  assert.equal(summarizeCoverage(null).holder_coverage, 'unknown');
});

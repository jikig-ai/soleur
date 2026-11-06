import { collectRunPages, summarizeRunPages } from './holder-evidence-core.mjs';
import { createHash } from 'node:crypto';
import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Offline parser only. It neither fetches nor accepts credentials; a transport
// must limit bytes while streaming, before it hands a buffer to this function.
const ENDPOINT = /^https:\/\/api\.github\.com\/repos\/jikig-ai\/soleur\/actions\/workflows\/(?:277913850|380964769|365691492)\/runs$/;
const WORKFLOWS = new Map([
  [277913850, '.github/workflows/tenant-integration.yml'],
  [380964769, '.github/workflows/scheduled-integration-suites.yml'],
  [365691492, '.github/workflows/dev-ledger-reconcile.yml'],
]);
const EVENTS = new Set(['push', 'pull_request', 'pull_request_target', 'workflow_dispatch', 'workflow_run', 'schedule', 'repository_dispatch', 'issue_comment', 'issues', 'create', 'delete', 'release', 'merge_group']);
const CONCLUSIONS = new Set(['success', 'failure', 'neutral', 'cancelled', 'skipped', 'timed_out', 'action_required', 'stale', 'startup_failure']);
const MAX_CHUNKS = 4096;
const refuse = () => { throw new Error('github_page_invalid'); };

function projectRunDetails(run) {
  const identity = (value) => Number.isSafeInteger(value?.id) && value.id > 0 ? value.id : 'unknown';
  const branch = typeof run.head_branch === 'string' && Buffer.byteLength(run.head_branch, 'utf8') > 0 && Buffer.byteLength(run.head_branch, 'utf8') <= 1024
    ? createHash('sha256').update(run.head_branch, 'utf8').digest('hex') : 'unknown';
  return {
    id: run.id,
    event: EVENTS.has(run.event) ? run.event : 'unknown',
    conclusion: run.conclusion === null ? 'none' : CONCLUSIONS.has(run.conclusion) ? run.conclusion : 'unknown',
    actor_id: identity(run.actor), triggering_actor_id: identity(run.triggering_actor), ref_digest: branch,
  };
}

export function parseWorkflowAdmission(bytes, expectedId, maxBytes) {
  if (!(bytes instanceof Uint8Array) || !WORKFLOWS.has(expectedId) ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 1048576) refuse();
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(snapshotBytes(bytes, maxBytes))); }
  catch { refuse(); }
  if (!data || data.id !== expectedId || data.path !== WORKFLOWS.get(expectedId) ||
      !['active', 'disabled_manually'].includes(data.state)) refuse();
  return { id: expectedId, path: data.path, state: data.state };
}

function checkOptions(options) {
  if (!options || typeof options.endpoint !== 'string' || !ENDPOINT.test(options.endpoint) ||
      !Number.isSafeInteger(options.maxBytes) || options.maxBytes < 1 || options.maxBytes > 1048576 ||
      !Number.isSafeInteger(options.page) || options.page < 1 || options.page > 100 ||
      !Number.isSafeInteger(options.perPage) || options.perPage < 1 || options.perPage > 100) refuse();
}

export function parseWorkflowRunPage(bytes, link, options) {
  try {
    const keys = ['endpoint', 'maxBytes', 'page', 'perPage'];
    const descriptors = Object.getOwnPropertyDescriptors(options);
    if (!keys.every(key => Object.hasOwn(descriptors[key] ?? {}, 'value'))) refuse();
    options = Object.fromEntries(keys.map(key => [key, descriptors[key].value]));
  } catch { refuse(); }
  checkOptions(options);
  if (!(bytes instanceof Uint8Array)) refuse();
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(snapshotBytes(bytes, options.maxBytes))); }
  catch { refuse(); }
  if (!data || !Number.isSafeInteger(data.total_count) || data.total_count < 0 ||
      !Array.isArray(data.workflow_runs) || data.workflow_runs.length > options.perPage) refuse();
  const projected = summarizeRunPages([{ workflow_runs: data.workflow_runs, next: false }],
    { maxPages: 1, maxRuns: options.perPage });
  if (projected.state !== 'complete') refuse();

  let next = false;
  if (link !== null && link !== undefined) {
    if (typeof link !== 'string' || link.length > 8192 || !link.length) refuse();
    const relations = new Set();
    let lastPage;
    for (const part of link.split(',')) {
      const match = /^\s*<([^<>]+)>;\s*rel="(next|prev|first|last)"\s*$/.exec(part);
      if (!match || relations.has(match[2])) refuse();
      relations.add(match[2]);
      let target;
      try { target = new URL(match[1]); } catch { refuse(); }
      if (`${target.origin}${target.pathname}` !== options.endpoint || target.hash || target.username || target.password ||
          [...target.searchParams.keys()].length !== 2 || target.searchParams.getAll('page').length !== 1 ||
          target.searchParams.getAll('per_page').length !== 1 || target.searchParams.get('per_page') !== String(options.perPage) ||
          !/^[1-9][0-9]*$/.test(target.searchParams.get('page') ?? '')) refuse();
      if (match[2] === 'next') {
        if (target.searchParams.get('page') !== String(options.page + 1)) refuse();
        next = true;
      }
      const page = Number(target.searchParams.get('page'));
      if (!Number.isSafeInteger(page) || (match[2] === 'first' && page !== 1) ||
          (match[2] === 'prev' && page !== options.page - 1)) refuse();
      if (match[2] === 'last') lastPage = page;
    }
    if (lastPage !== undefined && (lastPage < options.page || (lastPage > options.page) !== next ||
        lastPage !== Math.max(1, Math.ceil(data.total_count / options.perPage)))) refuse();
  }
  const end = (options.page - 1) * options.perPage + data.workflow_runs.length;
  if (end > data.total_count || (next && data.total_count <= end) || (!next && data.total_count > end)) refuse();
  return { workflow_runs: projected.runs, details: data.workflow_runs.map(projectRunDetails), next, total_count: data.total_count };
}

async function readBounded(fetchPage, url, maxBytes, signal) {
  if (typeof fetchPage !== 'function' || !(signal instanceof AbortSignal) || signal.aborted) refuse();
  let reader;
  let response;
  try {
    response = await fetchPage(url, { method: 'GET', redirect: 'error', signal });
    if (!response || response.status !== 200 || response.redirected || !response.body) refuse();
    reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    let count = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (signal.aborted) refuse();
      if (done) break;
      if (++count > MAX_CHUNKS) refuse();
      const chunk = snapshotBytes(value, maxBytes - size);
      size += chunk.length;
      if (chunk.length) chunks.push(chunk);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return { bytes, link: response.headers.get('link') };
  } catch {
    if (reader) { try { await reader.cancel(); } catch { /* fixed refusal below */ } }
    else if (response?.body) { try { await response.body.cancel(); } catch { /* fixed refusal below */ } }
    refuse();
  } finally {
    if (reader) { try { reader.releaseLock(); } catch { refuse(); } }
  }
}

// fetchPage is supplied by the caller; this module has no built-in transport or
// credential acquisition. The caller must bind authentication and cancellation.
export async function readWorkflowRunPage(fetchPage, options, signal) {
  try { options = { endpoint: options?.endpoint, maxBytes: options?.maxBytes, page: options?.page, perPage: options?.perPage }; }
  catch { refuse(); }
  checkOptions(options);
  const url = `${options.endpoint}?per_page=${options.perPage}&page=${options.page}`;
  const { bytes, link } = await readBounded(fetchPage, url, options.maxBytes, signal);
  return parseWorkflowRunPage(bytes, link, options);
}

export async function readWorkflowAdmission(fetchPage, expectedId, maxBytes, signal) {
  if (!WORKFLOWS.has(expectedId) || !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 1048576) refuse();
  const url = `https://api.github.com/repos/jikig-ai/soleur/actions/workflows/${expectedId}`;
  const { bytes } = await readBounded(fetchPage, url, maxBytes, signal);
  return parseWorkflowAdmission(bytes, expectedId, maxBytes);
}

export async function collectWorkflowRuns(fetchPage, options) {
  try {
    options = { endpoint: options?.endpoint, maxBytes: options?.maxBytes, perPage: options?.perPage,
      maxPages: options?.maxPages, maxRuns: options?.maxRuns, timeoutMs: options?.timeoutMs };
  } catch {
    return { scope: 'supplied_page_walk', state: 'failed', runs: [], writer_clearance: false,
      details: [], projection_state: 'partial', details_coverage: 'partial' };
  }
  let firstTotal;
  let count = 0;
  const details = new Map();
  const result = await collectRunPages(async (index, signal) => {
    const page = await readWorkflowRunPage(fetchPage, { ...options, page: index + 1 }, signal);
    if (firstTotal === undefined) firstTotal = page.total_count;
    if (page.total_count !== firstTotal || (page.next && page.workflow_runs.length !== options.perPage)) refuse();
    count += page.workflow_runs.length;
    if (!page.next && count !== firstTotal) refuse();
    for (const detail of page.details) if (!details.has(detail.id)) details.set(detail.id, detail);
    return page;
  }, options);
  const selected = result.runs.map((run) => details.get(run.id)).filter(Boolean);
  const detailsCoverage = selected.length === result.runs.length && selected.every((detail) => Object.values(detail).every((value) => value !== 'unknown')) ? 'complete' : 'partial';
  // Ref hashes are not resolvable refs; full requested detail coverage is open.
  return { ...result, details: selected, projection_state: result.state === 'complete' ? detailsCoverage : 'partial', details_coverage: 'partial' };
}

// Per-workflow interval observation only; even matching samples are not a fence.
export async function collectWorkflowEvidence(fetchPage, options) {
  const failed = () => ({ admission: { state: 'failed' }, runs: { state: 'failed' }, holder_coverage: 'unknown', writer_clearance: false });
  try {
    options = { id: options?.id, maxBytes: options?.maxBytes, perPage: options?.perPage,
      maxPages: options?.maxPages, maxRuns: options?.maxRuns, timeoutMs: options?.timeoutMs };
  } catch { return failed(); }
  if (!options || !WORKFLOWS.has(options.id) || !Number.isSafeInteger(options.timeoutMs) || options.timeoutMs < 1 || options.timeoutMs > 60000) return failed();
  const controller = new AbortController();
  const deadlineAt = performance.now() + options.timeoutMs;
  let timer;
  const deadline = new Promise((resolve) => { timer = setTimeout(() => { controller.abort(); resolve(failed()); }, options.timeoutMs); });
  const work = async () => {
    let before;
    let after;
    try { before = await readWorkflowAdmission(fetchPage, options.id, options.maxBytes, controller.signal); } catch { /* source remains failed */ }
    if (controller.signal.aborted || performance.now() >= deadlineAt) return failed();
    const endpoint = `https://api.github.com/repos/jikig-ai/soleur/actions/workflows/${options.id}/runs`;
    const abortableFetch = (url, init) => {
      const signal = AbortSignal.any([controller.signal, init.signal]);
      if (signal.aborted || performance.now() >= deadlineAt) refuse();
      return fetchPage(url, { ...init, signal });
    };
    const runs = await collectWorkflowRuns(abortableFetch, { ...options, endpoint });
    if (controller.signal.aborted || performance.now() >= deadlineAt) return failed();
    try { after = await readWorkflowAdmission(fetchPage, options.id, options.maxBytes, controller.signal); } catch { /* source remains failed */ }
    if (controller.signal.aborted || performance.now() >= deadlineAt) return failed();
    const admission = !before || !after ? { state: 'failed' } : {
      state: before.state === after.state ? 'complete' : 'partial', before, after,
    };
    return { admission, runs, holder_coverage: 'unknown', writer_clearance: false };
  };
  try { return await Promise.race([work().catch(failed), deadline]); }
  finally { clearTimeout(timer); controller.abort(); }
}

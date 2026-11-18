import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Offline-only: callers supply transport; this module has no credentials or network client.
const ENDPOINT = 'https://api.github.com/repos/jikig-ai/soleur/collaborators';
const FLAGS = ['admin', 'maintain', 'push', 'triage', 'pull'];
const MAX_CHUNKS = 4096;
const refuse = () => { throw new Error('collaborator_page_invalid'); };
const integer = (n, min, max) => Number.isSafeInteger(n) && n >= min && n <= max;

function validate(options, page) {
  if (!options || !integer(options.perPage, 1, 100) || !integer(options.maxPages, 1, 100) ||
      !integer(options.maxRows, 1, 10000) || !integer(options.maxBytes, 1, 1048576) ||
      !integer(options.timeoutMs, 1, 60000) || !integer(page, 1, options.maxPages)) refuse();
}

export function parseCollaboratorPage(bytes, link, options) {
  try {
    const keys = ['perPage', 'maxPages', 'maxRows', 'maxBytes', 'timeoutMs', 'page'];
    const descriptors = Object.getOwnPropertyDescriptors(options);
    if (!keys.every(key => Object.hasOwn(descriptors[key] ?? {}, 'value'))) refuse();
    options = Object.fromEntries(keys.map(key => [key, descriptors[key].value]));
  } catch { refuse(); }
  validate(options, options?.page);
  if (!(bytes instanceof Uint8Array)) refuse();
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(snapshotBytes(bytes, options.maxBytes))); } catch { refuse(); }
  if (!Array.isArray(data) || data.length > options.perPage) refuse();
  const ids = new Set();
  const collaborators = data.map((entry) => {
    if (!entry || !integer(entry.id, 1, Number.MAX_SAFE_INTEGER) || ids.has(entry.id) ||
        !entry.permissions || FLAGS.some(flag => typeof entry.permissions[flag] !== 'boolean')) refuse();
    ids.add(entry.id);
    return { id: entry.id, permissions: Object.fromEntries(FLAGS.map(flag => [flag, entry.permissions[flag]])) };
  });
  let next = false;
  let lastPage = null;
  if (link != null) {
    if (typeof link !== 'string' || !link.length || link.length > 8192) refuse();
    const relations = new Set();
    for (const part of link.split(',')) {
      const match = /^\s*<([^<>]+)>;\s*rel="(next|prev|first|last)"\s*$/.exec(part);
      if (!match || relations.has(match[2])) refuse();
      relations.add(match[2]);
      let url;
      try { url = new URL(match[1]); } catch { refuse(); }
      if (`${url.origin}${url.pathname}` !== ENDPOINT || url.username || url.password || url.hash ||
          [...url.searchParams.keys()].length !== 2 || url.searchParams.getAll('page').length !== 1 ||
          url.searchParams.getAll('per_page').length !== 1 || url.searchParams.get('per_page') !== String(options.perPage) ||
          !/^[1-9][0-9]*$/.test(url.searchParams.get('page') ?? '')) refuse();
      if (match[2] === 'next') {
        if (url.searchParams.get('page') !== String(options.page + 1) || data.length !== options.perPage) refuse();
        next = true;
      }
      const target = Number(url.searchParams.get('page'));
      if (!Number.isSafeInteger(target) || (match[2] === 'first' && target !== 1) ||
          (match[2] === 'prev' && target !== options.page - 1)) refuse();
      if (match[2] === 'last') lastPage = target;
    }
    if (lastPage !== null && (lastPage < options.page || (lastPage > options.page) !== next)) refuse();
  }
  return { collaborators, next, lastPage };
}

async function readPage(fetchPage, options, page, signal, deadlineAt) {
  validate(options, page);
  let response, reader;
  try {
    if (signal.aborted || performance.now() >= deadlineAt) refuse();
    response = await fetchPage(`${ENDPOINT}?per_page=${options.perPage}&page=${page}`, { method: 'GET', redirect: 'error', signal });
    if (signal.aborted || performance.now() >= deadlineAt || !response || response.status !== 200 || response.redirected || !response.body) refuse();
    reader = response.body.getReader();
    let size = 0;
    let count = 0;
    const chunks = [];
    for (;;) {
      const { value, done } = await reader.read();
      if (signal.aborted || performance.now() >= deadlineAt) refuse();
      if (done) break;
      if (++count > MAX_CHUNKS) refuse();
      const chunk = snapshotBytes(value, options.maxBytes - size);
      size += chunk.length;
      if (chunk.length) chunks.push(chunk);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return parseCollaboratorPage(bytes, response.headers.get('link'), { ...options, page });
  } catch {
    if (reader) { try { await reader.cancel(); } catch { /* fixed error */ } }
    else if (response?.body) { try { await response.body.cancel(); } catch { /* fixed error */ } }
    refuse();
  } finally { if (reader) { try { reader.releaseLock(); } catch { refuse(); } } }
}

async function traverse(fetchPage, options, signal, deadlineAt) {
  const rows = new Map();
  const pages = [];
  let observedLast = null;
  for (let page = 1; page <= options.maxPages; page++) {
    const result = await readPage(fetchPage, options, page, signal, deadlineAt);
    if (page > 1 && result.collaborators.length === 0) refuse();
    pages.push(result.collaborators.map((row) => row.id).sort((a, b) => a - b));
    if (result.lastPage !== null) {
      if (observedLast !== null && observedLast !== result.lastPage) refuse();
      observedLast = result.lastPage;
    }
    if (observedLast !== null && (page > observedLast || (!result.next && page !== observedLast))) refuse();
    for (const row of result.collaborators) {
      if (rows.has(row.id) || rows.size >= options.maxRows) refuse();
      rows.set(row.id, row);
    }
    if (!result.next) return { rows: [...rows.values()].sort((a, b) => a.id - b.id), observedLast, pages };
  }
  refuse();
}

// Two traversals detect observed changes, not changes between observations or hidden holders.
export async function collectCollaborators(fetchPage, options) {
  const incomplete = () => ({ state: 'partial', collaborators: [], holder_coverage: 'unknown', workflow_admission: 'unknown', writer_clearance: false });
  try {
    options = { perPage: options?.perPage, maxPages: options?.maxPages, maxRows: options?.maxRows,
      maxBytes: options?.maxBytes, timeoutMs: options?.timeoutMs };
    validate(options, 1);
    if (typeof fetchPage !== 'function') refuse();
  } catch { return incomplete(); }
  const controller = new AbortController();
  const deadlineAt = performance.now() + options.timeoutMs;
  let timer;
  const deadline = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(incomplete()); }, options.timeoutMs); });
  const work = async () => {
    const first = await traverse(fetchPage, options, controller.signal, deadlineAt);
    const second = await traverse(fetchPage, options, controller.signal, deadlineAt);
    if (controller.signal.aborted || performance.now() >= deadlineAt) return incomplete();
    if (JSON.stringify(first) !== JSON.stringify(second)) return incomplete();
    return { ...incomplete(), state: 'complete', collaborators: second.rows };
  };
  try { return await Promise.race([work().catch(incomplete), deadline]); }
  finally { clearTimeout(timer); controller.abort(); }
}

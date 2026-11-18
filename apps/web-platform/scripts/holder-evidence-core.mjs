// Offline projection of already supplied pages. This is not a live collector.
const STATUSES = new Set(['queued', 'in_progress', 'completed', 'waiting', 'requested', 'pending']);
const SOURCES = ['github_actions', 'database_roles', 'database_sessions', 'supabase', 'doppler', 'deployed_consumers', 'local_agents'];
const SECTION_STATES = new Set(['complete', 'partial', 'failed', 'unsupported']);

// Reporting metadata only: supplied source states are not independently verified.
export function summarizeCoverage(input) {
  const sourceStates = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
  const sources = Object.fromEntries(SOURCES.map((source) => {
    const value = Object.hasOwn(sourceStates, source) ? sourceStates[source] : 'unsupported';
    return [source, SECTION_STATES.has(value) ? value : 'failed'];
  }));
  return { sources, holder_coverage: 'unknown', writer_clearance: false };
}

export function summarizeRunPages(pages, limits) {
  // This state describes only the supplied page walk, never provider coverage.
  const result = (state, runs = []) => ({ scope: 'supplied_page_walk', state, runs, writer_clearance: false });
  if (!Array.isArray(pages) || !limits || !Number.isSafeInteger(limits.maxPages) ||
      limits.maxPages < 1 || !Number.isSafeInteger(limits.maxRuns) || limits.maxRuns < 1) {
    return result('failed');
  }
  if (pages.length === 0) return result('failed');

  const runs = [];
  const ids = new Set();
  for (let i = 0; i < pages.length; i++) {
    if (i >= limits.maxPages) return result('partial', runs);
    const current = pages[i];
    if (!current || !Array.isArray(current.workflow_runs) || typeof current.next !== 'boolean') {
      return result('failed');
    }
    for (const item of current.workflow_runs) {
      if (!item || !Number.isSafeInteger(item.id) || item.id < 1 || !STATUSES.has(item.status)) {
        return result('failed');
      }
      if (ids.has(item.id) || runs.length >= limits.maxRuns) return result('partial', runs);
      ids.add(item.id);
      runs.push({ id: item.id, status: item.status });
    }
    if (!current.next) return i === pages.length - 1 ? result('complete', runs) : result('failed');
  }
  return result('partial', runs);
}

// Only an injected reader is accepted. A real adapter must separately enforce
// transport byte bounds and cancellation; this function makes no network calls.
export async function collectRunPages(readPage, limits) {
  const result = (state, runs = []) => ({ scope: 'supplied_page_walk', state, runs, writer_clearance: false });
  try { limits = { maxPages: limits?.maxPages, maxRuns: limits?.maxRuns, timeoutMs: limits?.timeoutMs }; }
  catch { return result('failed'); }
  if (typeof readPage !== 'function' || !limits ||
      !Number.isSafeInteger(limits.maxPages) || limits.maxPages < 1 || limits.maxPages > 100 ||
      !Number.isSafeInteger(limits.maxRuns) || limits.maxRuns < 1 || limits.maxRuns > 50000 ||
      !Number.isSafeInteger(limits.timeoutMs) || limits.timeoutMs < 1 || limits.timeoutMs > 60000) {
    return result('failed');
  }
  const controller = new AbortController();
  const deadlineAt = performance.now() + limits.timeoutMs;
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => { controller.abort(); reject(new Error('deadline')); }, limits.timeoutMs);
  });
  const runs = [];
  const ids = new Set();
  try {
    for (let i = 0; i < limits.maxPages; i++) {
      if (performance.now() >= deadlineAt) return result('failed');
      const current = await Promise.race([Promise.resolve().then(() => readPage(i, controller.signal)), deadline]);
      if (performance.now() >= deadlineAt) return result('failed');
      if (!current || !Array.isArray(current.workflow_runs) || typeof current.next !== 'boolean') return result('failed');
      const projected = summarizeRunPages([{ workflow_runs: current.workflow_runs, next: false }], limits);
      if (projected.state === 'failed') return result('failed');
      for (const run of projected.runs) {
        if (ids.has(run.id) || runs.length >= limits.maxRuns) return result('partial', runs);
        ids.add(run.id);
        runs.push(run);
      }
      if (projected.state === 'partial') return result('partial', runs);
      if (!current.next) return performance.now() < deadlineAt ? result('complete', runs) : result('failed');
    }
    return result('partial', runs);
  } catch {
    return result('failed');
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}

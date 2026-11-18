// Synthetic-only status projection. The supplied adapter is responsible for
// read-only transactions, server-side caps, byte limits and source binding.
const ARMS = Object.freeze(['roles', 'memberships', 'tables', 'functions', 'sessions', 'relation_acls', 'schema_privileges', 'control_acls', 'triggers', 'policies', 'sequences', 'materialized_views', 'sequence_acls']);
const failed = () => ({ state: 'failed', observed_count: null });
const unsupported = () => ({ state: 'unsupported', observed_count: null });

export async function inspectCatalogArm(readRows, limits) {
  if (typeof readRows !== 'function' || !limits || !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 1 || limits.maxRows > 10000 ||
      !Number.isSafeInteger(limits.timeoutMs) || limits.timeoutMs < 1 || limits.timeoutMs > 60000) return failed();
  const controller = new AbortController();
  const deadlineAt = performance.now() + limits.timeoutMs;
  const markExpired = () => {
    controller.abort();
    if (typeof limits.onTimeout === 'function') { try { limits.onTimeout(); } catch { /* fail closed below */ } }
  };
  let timer;
  const deadline = new Promise((_, reject) => { timer = setTimeout(() => {
    markExpired();
    reject(new Error('deadline'));
  }, limits.timeoutMs); });
  try {
    const rows = await Promise.race([Promise.resolve().then(() => readRows(controller.signal)), deadline]);
    if (performance.now() >= deadlineAt) { markExpired(); return failed(); }
    if (!Array.isArray(rows)) return failed();
    if (limits.arm === 'sessions') {
      const summaries = rows.filter((row) => row?.kind === 'session_summary');
      const sessions = rows.filter((row) => row?.kind === 'session');
      const summary = summaries[0];
      if (summaries.length !== 1 || rows.length !== sessions.length + 1 || !Number.isSafeInteger(summary.observed_count) ||
          summary.observed_count !== sessions.length || typeof summary.capped !== 'boolean' || summary.capped !== (sessions.length > 256) ||
          !['restricted', 'full_stats_privilege'].includes(summary.visibility)) return failed();
      if (summary.capped || sessions.length > limits.maxRows || summary.visibility === 'restricted' ||
          sessions.some((session) => typeof session.role_name !== 'string' || !session.role_name ||
            !Number.isSafeInteger(session.role_oid) || session.role_oid < 1 || session.role_oid > 4294967295 ||
            !['active', 'idle', 'idle in transaction', 'idle in transaction (aborted)', 'fastpath function call'].includes(session.state_class) ||
            session.application_class !== 'other' || !['none_or_hidden', 'under_1m', '1m_to_15m', '15m_or_more'].includes(session.transaction_age_bucket) ||
            session.write_capability !== 'unknown')) return { state: 'partial', observed_count: sessions.length };
      return { state: 'complete', observed_count: sessions.length };
    }
    if (rows.length > limits.maxRows) return { state: 'partial', observed_count: limits.maxRows + 1 };
    if (rows.some((row) => !row || typeof row !== 'object' || Array.isArray(row))) return failed();
    return { state: 'complete', observed_count: rows.length };
  } catch {
    return failed();
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}

export async function inspectCatalogSet(readers, limits) {
  const arms = {};
  const started = performance.now();
  let timedOut = false;
  for (const name of ARMS) {
    const reader = readers && Object.hasOwn(readers, name) ? readers[name] : undefined;
    const remaining = Number.isSafeInteger(limits?.timeoutMs) ? Math.floor(limits.timeoutMs - (performance.now() - started)) : 0;
    if (reader === undefined) arms[name] = unsupported();
    else if (remaining < 1 || timedOut) arms[name] = failed();
    else arms[name] = await inspectCatalogArm(reader, { maxRows: limits.maxRows, timeoutMs: remaining, arm: name, onTimeout: () => { timedOut = true; } });
  }
  return { arms, holder_coverage: 'unknown', writer_clearance: false };
}

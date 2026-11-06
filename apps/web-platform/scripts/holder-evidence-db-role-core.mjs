import { verifiedQuery } from './holder-evidence-db-query-source.mjs';

// Query integrity only: the caller must independently bind the executable,
// adapter, pin and operation. No collection or writer clearance is granted.
const failure = () => ({ state: 'failed', observed_count: null, holder_coverage: 'unknown', writer_clearance: false });

function validRole(value) {
  if (!value || value.kind !== 'role' || typeof value.role_name !== 'string' ||
      !value.role_name || Buffer.byteLength(value.role_name, 'utf8') > 63 ||
      !Number.isSafeInteger(value.role_oid) || value.role_oid < 1 || value.role_oid > 4294967295) return false;
  return ['can_login', 'superuser', 'bypass_rls', 'inherits_by_default', 'can_create_role', 'can_create_database', 'replication']
    .every((key) => typeof value[key] === 'boolean');
}

export async function inspectEmbeddedRoles(database, bytes, expectedSha256, options = {}) {
  let timeoutMs;
  try {
    if (!options || typeof options !== 'object' || Array.isArray(options)) return failure();
    // Proxy descriptor traps can execute or block before the deadline starts.
    const descriptors = Object.getOwnPropertyDescriptors(options);
    if (descriptors.timeoutMs && !Object.hasOwn(descriptors.timeoutMs, 'value')) return failure();
    timeoutMs = descriptors.timeoutMs?.value ?? 15000;
  } catch { return failure(); }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) return failure();
  try {
    if (typeof database?.begin !== 'function') return failure();
    const query = verifiedQuery(bytes, expectedSha256);
    let expired = false;
    let timer;
    const deadlineAt = performance.now() + timeoutMs;
    const ensureActive = () => { if (expired || performance.now() >= deadlineAt) throw new Error('deadline'); };
    const deadline = new Promise((resolve) => { timer = setTimeout(() => { expired = true; resolve(failure()); }, timeoutMs); });
    const task = Promise.resolve().then(() => database.begin('isolation level repeatable read read only', async (tx) => {
      ensureActive();
      await tx.unsafe("SET LOCAL statement_timeout = '10s'; SET LOCAL lock_timeout = '1s'; SET LOCAL idle_in_transaction_session_timeout = '15s'; SET LOCAL search_path = pg_catalog, pg_temp");
      ensureActive();
      const state = await tx.unsafe("SELECT current_setting('transaction_read_only') AS read_only, current_setting('transaction_isolation') AS isolation, current_setting('search_path') AS search_path");
      ensureActive();
      if (!Array.isArray(state) || state.length !== 1 || state[0].read_only !== 'on' || state[0].isolation !== 'repeatable read' || state[0].search_path !== 'pg_catalog, pg_temp') throw new Error('transaction');
      const cursor = tx.unsafe(query).cursor(1);
      let count = 0;
      let totalBytes = 0;
      const roles = [];
      const roleIds = new Set();
      for await (const batch of cursor) {
        ensureActive();
        if (!Array.isArray(batch) || batch.length !== 1) throw new Error('rows');
        const row = batch[0];
        count++;
        if (count > 10000) return { state: 'partial', observed_count: 10001, holder_coverage: 'unknown', writer_clearance: false };
        if (typeof row?.row_to_json !== 'string' || Buffer.byteLength(row.row_to_json, 'utf8') > 4096) throw new Error('rows');
        const role = JSON.parse(row.row_to_json);
        if (!validRole(role) || roleIds.has(role.role_oid)) throw new Error('rows');
        roleIds.add(role.role_oid);
        totalBytes += Buffer.byteLength(row.row_to_json, 'utf8');
        if (totalBytes > 4 * 1024 * 1024) return { state: 'partial', observed_count: count, holder_coverage: 'unknown', writer_clearance: false };
        const { role_oid, can_login, superuser, bypass_rls, inherits_by_default, can_create_role, can_create_database, replication } = role;
        roles.push({ role_oid, can_login, superuser, bypass_rls, inherits_by_default, can_create_role, can_create_database, replication });
      }
      ensureActive();
      return { state: 'complete', observed_count: count, roles, role_names: 'omitted', holder_coverage: 'unknown', writer_clearance: false };
    }));
    try { return await Promise.race([task, deadline]); }
    finally { expired = true; clearTimeout(timer); }
  } catch { return failure(); }
}

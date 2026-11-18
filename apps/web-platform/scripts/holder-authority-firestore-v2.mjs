import { prepareIntent } from './holder-authority-intent.mjs';
import { validateV2History } from './holder-authority-conditional-store.mjs';
import { parseUnique } from './holder-reservation-firestore.mjs';

// Injected transport only: it is not verified to be a mock, a Firestore
// connection, strong read, authenticated principal or durable service. No
// result authorizes side effects. The existing live Firestore POST transport
// remains independently hard-disabled; this module supplies no network client.
const fields = ['operation_id','vault_id','owner_id','generation','manifest_sha256','controller_sha256','capture_start_ms','deadline_ms'];
const keys = (v, names) => v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === names.length && names.every(k => Object.hasOwn(v,k));
const result = state => ({ state, capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const stamp = value => {
  if (typeof value !== 'string' || value.startsWith('0000-')) return null;
  const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{3}|\d{6}|\d{9}))?Z$/.exec(value);
  if (!match || (match[2]?.length === 9 && !match[2].endsWith('000'))) return null;
  const ms = Date.parse(`${match[1]}Z`);
  if (!Number.isFinite(ms) || new Date(ms).toISOString().slice(0,19) !== match[1]) return null;
  return BigInt(ms) * 1000000n + BigInt((match[2] ?? '').padEnd(9,'0'));
};

export function createFirestoreV2Adapter(projectId, databaseId, baseJson, request) {
  if (typeof projectId !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId) ||
      typeof databaseId !== 'string' || !(databaseId === '(default)' || /^[a-z0-9][a-z0-9-]{0,62}$/.test(databaseId)) ||
      typeof baseJson !== 'string' || Buffer.byteLength(baseJson) > 4096 || typeof request !== 'function') throw Error('adapter_configuration');
  let base;
  try { base = JSON.parse(baseJson); if (!keys(base, fields) || JSON.stringify(base) !== baseJson || !/^[a-f0-9]{32}$/.test(base.operation_id)) throw Error(); }
  catch { throw Error('adapter_configuration'); }
  const root = `projects/${projectId}/databases/${databaseId}/documents`;
  const name = `${root}/holder_evidence_operations/${base.operation_id}`;
  const endpoint = `https://firestore.googleapis.com/v1/${root}`;
  // Process-local experiment only: restart or another adapter bypasses this
  // latch. It is neither durable authority nor a cross-process write fence.
  let busy = false;
  let unresolvedIntent = null;
  async function call(ctx, method, url, body) {
    try {
      const work = Promise.resolve().then(() => ctx.expired() ? null : request(Object.freeze({ method, url, body, maxResponseBytes: 100000, signal: ctx.controller.signal }))).catch(() => null);
      const response = await Promise.race([work, ctx.timeout]);
      if (ctx.expired() || !response) return null;
      const status = response.status;
      if (ctx.expired()) return null;
      const raw = response.body;
      if (ctx.expired() || !Number.isInteger(status) || typeof raw !== 'string' || Buffer.byteLength(raw) > 100000 || ctx.expired()) return null;
      return { status, raw };
    } catch { return null; }
  }
  async function read(ctx) {
    const response = await call(ctx, 'GET', `${endpoint}/holder_evidence_operations/${base.operation_id}`, undefined);
    if (ctx.expired()) return null;
    if (response?.status === 404) return { state: 'absent' };
    if (response?.status !== 200) return null;
    try {
      const doc = parseUnique(response.raw);
      if (ctx.expired()) return null;
      if (!doc || typeof doc !== 'object' || Array.isArray(doc) || !['name','fields','updateTime'].every(k => Object.hasOwn(doc,k)) ||
          !Object.keys(doc).every(k => ['name','fields','updateTime','createTime'].includes(k)) || doc.name !== name || stamp(doc.updateTime) === null ||
          (Object.hasOwn(doc,'createTime') && (stamp(doc.createTime) === null || stamp(doc.createTime) > stamp(doc.updateTime))) ||
          !keys(doc.fields,['payload']) || !keys(doc.fields.payload,['stringValue'])) return null;
      const raw = doc.fields.payload.stringValue;
      if (ctx.expired() || !validateV2History(raw, baseJson) || ctx.expired()) return null;
      const record = JSON.parse(raw);
      return ctx.expired() ? null : { state: 'found', raw, record, updateTime: doc.updateTime };
    } catch { return null; }
  }
  return Object.freeze({ submit: async input => {
    if (busy) return result('unknown');
    busy = true;
    const controller = new AbortController();
    const end = performance.now() + 1000;
    let timer;
    const ctx = { controller, expired: () => controller.signal.aborted || performance.now() >= end };
    ctx.timeout = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(null); }, 1000); });
    const work = async () => { try {
      const prepared = prepareIntent(input);
      if (ctx.expired() || prepared.state !== 'prepared_unverified') return result('unknown');
      const intent = JSON.parse(prepared.intent_json);
      if (ctx.expired() || fields.some(k => intent[k] !== base[k])) return result('unknown');
      if (unresolvedIntent !== null && unresolvedIntent !== prepared.intent_json) return result('unknown');
      const receipt = { command_id: intent.command_id, intent_json: prepared.intent_json, intent_sha256: prepared.intent_sha256 };
      const current = await read(ctx);
      if (ctx.expired() || !current) return result('unknown');
      let next, condition;
      if (current.state === 'absent') {
        if (unresolvedIntent !== null) return result('unknown');
        if (intent.action !== 'prepare') return result('unknown');
        next = { schema_version: 2, state: 'unarmed', revision: 0, asserted_late: false, prepare: receipt, receipts: [] };
        condition = { exists: false };
      } else {
        const prior = [current.record.prepare, ...current.record.receipts].find(item => item.command_id === receipt.command_id);
        if (prior) {
          if (JSON.stringify(prior) !== JSON.stringify(receipt)) return result('unknown');
          if (unresolvedIntent === prepared.intent_json) unresolvedIntent = null;
          return result('historical_unverified');
        }
        if (unresolvedIntent !== null) return result('unknown');
        if (intent.action === 'prepare' || current.record.state !== intent.expected_state || current.record.revision !== intent.expected_revision) return result('unknown');
        next = { ...current.record, state: intent.target_state, revision: intent.target_revision,
          asserted_late: current.record.asserted_late || intent.clock_decision === 'at_or_after_deadline', receipts: [...current.record.receipts, receipt] };
        condition = { updateTime: current.updateTime };
      }
      const raw = JSON.stringify(next);
      if (ctx.expired() || !validateV2History(raw, baseJson) || ctx.expired()) return result('unknown');
      const body = JSON.stringify({ writes: [{ update: { name, fields: { payload: { stringValue: raw } } }, currentDocument: condition }] });
      if (ctx.expired() || Buffer.byteLength(body) > 100000 || ctx.expired()) return result('unknown');
      // Ignore all acknowledgements: only a subsequent exact retained receipt
      // can establish the fixture's persisted result. Absence after timeout
      // does not resolve a possibly in-flight commit.
      unresolvedIntent = prepared.intent_json;
      await call(ctx, 'POST', `${endpoint}:commit`, body);
      if (ctx.expired()) return result('unknown');
      const observed = await read(ctx);
      if (ctx.expired() || observed?.state !== 'found') return result('unknown');
      const found = [observed.record.prepare, ...observed.record.receipts].find(item => item.command_id === receipt.command_id);
      const sameHistory = JSON.stringify(observed.record.prepare) === JSON.stringify(next.prepare) &&
        JSON.stringify(observed.record.receipts.slice(0, next.receipts.length)) === JSON.stringify(next.receipts);
      if (!ctx.expired() && found && sameHistory && JSON.stringify(found) === JSON.stringify(receipt) && !ctx.expired()) {
        unresolvedIntent = null;
        return result('persisted_unverified');
      }
      return result('unknown');
    } catch { return result('unknown'); } };
    try {
      const value = await Promise.race([work(), ctx.timeout]);
      return ctx.expired() || !value ? result('unknown') : value;
    } finally { clearTimeout(timer); controller.abort(); busy = false; }
  } });
}

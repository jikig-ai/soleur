import { createHash } from 'node:crypto';

// Persistence boundary only. The injected transport, clock, IAM, vault fencing,
// approved executable and retention controls are NOT established here. No result
// authorizes capture or proves deletion. Do not connect this to live credentials.
const MAX_DAY = 24 * 60 * 60 * 1000;
const LIMIT = 8;
const baseKeys = ['operation_id', 'vault_id', 'owner_id', 'generation', 'manifest_sha256', 'controller_sha256', 'capture_start_ms', 'deadline_ms'];
const recordKeys = [...baseKeys, 'schema_version', 'state', 'revision', 'late', 'receipts'];
const receiptKeys = ['command_id', 'from', 'to', 'revision', 'lower_ms', 'upper_ms', 'late', 'intent_sha256'];
const commandKeys = ['operation_id', 'generation', 'expected_revision', 'expected_state', 'target_state', 'command_id'];
const edges = new Set(['unarmed:armed', 'armed:capturing', 'capturing:sealed', 'sealed:deleting']);
const token = (v) => typeof v === 'string' && /^[a-f0-9]{32}$/.test(v);
const hash = (v) => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const number = (v) => Number.isSafeInteger(v) && v >= 0;
const result = (state) => ({ state, capture_authorized: false, deletion_verified: false });
const keys = (v, expected) => v && typeof v === 'object' && !Array.isArray(v) &&
  Object.keys(v).length === expected.length && expected.every((key) => Object.hasOwn(v, key));
const allowed = (v, required, optional = []) => v && typeof v === 'object' && !Array.isArray(v) &&
  required.every((key) => Object.hasOwn(v, key)) && Object.keys(v).every((key) => required.includes(key) || optional.includes(key));
const snapshot = (v) => JSON.parse(JSON.stringify(v));
const nanoseconds = (v, microsecondAligned) => {
  if (typeof v !== 'string' || v.startsWith('0000-')) return null;
  const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{3}|\d{6}|\d{9}))?Z$/.exec(v);
  if (!match || (microsecondAligned && match[2]?.length === 9 && !match[2].endsWith('000'))) return null;
  const time = Date.parse(`${match[1]}Z`);
  if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 19) !== match[1]) return null;
  return BigInt(time) * 1000000n + BigInt((match[2] ?? '').padEnd(9, '0'));
};
const micros = (v) => nanoseconds(v, true) !== null;

function validBase(v) {
  return baseKeys.slice(0, 4).every((key) => token(v[key])) && hash(v.manifest_sha256) && hash(v.controller_sha256) &&
    number(v.capture_start_ms) && number(v.deadline_ms) && v.deadline_ms > v.capture_start_ms && v.deadline_ms - v.capture_start_ms <= MAX_DAY;
}

export function snapshotExpectedBase(input) {
  const base = snapshot(input);
  if (!keys(base, baseKeys) || !validBase(base)) throw new Error('ledger_base');
  return Object.freeze(base);
}

function receiptHash(record, event) {
  const canonical = ['holder-ledger-intent-v1', ...baseKeys.map((key) => record[key]), event.command_id,
    event.from, event.to, event.revision, event.lower_ms, event.upper_ms, event.late];
  return createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
}

function validRecord(record) {
  if (!keys(record, recordKeys) || !validBase(record) || record.schema_version !== 1 || !number(record.revision) ||
      typeof record.late !== 'boolean' || !Array.isArray(record.receipts) || record.receipts.length > LIMIT || record.receipts.length !== record.revision) return false;
  let state = 'unarmed', late = false, lower = 0, upper = 0;
  const ids = new Set();
  for (const [index, event] of record.receipts.entries()) {
    if (!keys(event, receiptKeys) || !token(event.command_id) || ids.has(event.command_id) || event.from !== state ||
        !edges.has(`${event.from}:${event.to}`) || event.revision !== index + 1 || !number(event.lower_ms) ||
        !number(event.upper_ms) || event.upper_ms < event.lower_ms || event.upper_ms - event.lower_ms > 5000 ||
        event.lower_ms < lower || event.upper_ms < upper || typeof event.late !== 'boolean' ||
        event.late !== (late || event.upper_ms >= record.deadline_ms) ||
        (event.to === 'armed' && event.upper_ms > record.capture_start_ms) ||
        (event.to === 'capturing' && (event.lower_ms < record.capture_start_ms || event.upper_ms >= record.deadline_ms)) ||
        event.intent_sha256 !== receiptHash(record, event)) return false;
    ids.add(event.command_id); state = event.to; late = event.late; lower = event.lower_ms; upper = event.upper_ms;
  }
  return record.state === state && record.late === late;
}

// Validate the only two wire-write shapes currently implemented. This is not
// operation authorization; the caller still needs independently bound IAM,
// executable identity, clock and readiness evidence.
export function validateRestrictedCommit(body, projectId, databaseId, expectedBase) {
  try {
    if (typeof body !== 'string' || Buffer.byteLength(body) > 32768) return false;
    const wire = JSON.parse(body);
    if (JSON.stringify(wire) !== body || !keys(wire, ['writes']) || !Array.isArray(wire.writes) || wire.writes.length !== 1) return false;
    const write = wire.writes[0];
    if (!keys(write, ['update', 'currentDocument']) || !keys(write.update, ['name', 'fields']) ||
        !keys(write.update.fields, ['payload']) || !keys(write.update.fields.payload, ['stringValue']) ||
        typeof write.update.fields.payload.stringValue !== 'string') return false;
    const payload = write.update.fields.payload.stringValue;
    const record = JSON.parse(payload);
    if (JSON.stringify(record) !== payload || !validRecord(record) || !keys(expectedBase, baseKeys) || !validBase(expectedBase) ||
        baseKeys.some((key) => record[key] !== expectedBase[key]) ||
        write.update.name !== `projects/${projectId}/databases/${databaseId}/documents/holder_evidence_operations/${record.operation_id}`) return false;
    if (record.state === 'unarmed') return keys(write.currentDocument, ['exists']) && write.currentDocument.exists === false;
    return record.state === 'armed' && keys(write.currentDocument, ['updateTime']) && micros(write.currentDocument.updateTime);
  } catch { return false; }
}

async function bounded(action) {
  const controller = new AbortController();
  let timer;
  try {
    const deadline = new Promise((resolve) => { timer = setTimeout(() => { controller.abort(); resolve(null); }, 5000); });
    return await Promise.race([Promise.resolve().then(() => action(controller.signal)).catch(() => null), deadline]);
  } finally { clearTimeout(timer); controller.abort(); }
}

export function createLedger({ projectId, databaseId, expectedBase, request, clock }) {
  if (typeof projectId !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId) ||
      typeof databaseId !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(databaseId) ||
      typeof request !== 'function' || typeof clock?.sample !== 'function') throw new Error('ledger_configuration');
  let expected;
  try { expected = snapshotExpectedBase(expectedBase); } catch { throw new Error('ledger_configuration'); }
  const root = `projects/${projectId}/databases/${databaseId}/documents`;
  const url = `https://firestore.googleapis.com/v1/${root}`;
  const name = (operation) => `${root}/holder_evidence_operations/${operation}`;

  async function call(method, target, body) {
    const response = await bounded((signal) => request({ method, url: target, body, maxResponseBytes: 65536, signal }));
    if (!response || !Number.isInteger(response.status) || typeof response.body !== 'string' || Buffer.byteLength(response.body) > 65536) return null;
    try { return { status: response.status, data: JSON.parse(response.body) }; } catch { return null; }
  }

  async function read(operation) {
    const response = await call('GET', `${url}/holder_evidence_operations/${operation}`, undefined);
    if (response?.status !== 200) return null;
    const doc = response.data;
    if (!allowed(doc, ['name', 'fields', 'updateTime'], ['createTime']) ||
        (Object.hasOwn(doc, 'createTime') && (!micros(doc.createTime) || nanoseconds(doc.createTime, true) > nanoseconds(doc.updateTime, true))) || doc.name !== name(operation) ||
        !micros(doc.updateTime) || !keys(doc.fields, ['payload']) ||
        !keys(doc.fields.payload, ['stringValue']) || typeof doc.fields.payload.stringValue !== 'string' || Buffer.byteLength(doc.fields.payload.stringValue) > 16384) return null;
    let record;
    try { record = JSON.parse(doc.fields.payload.stringValue); } catch { return null; }
    if (!validRecord(record) || record.operation_id !== operation || baseKeys.some((key) => record[key] !== expected[key])) return null;
    return { record, updateTime: doc.updateTime };
  }

  async function commit(record, precondition) {
    const payload = JSON.stringify(record);
    if (Buffer.byteLength(payload) > 16384) return false;
    const body = JSON.stringify({ writes: [{ update: { name: name(record.operation_id), fields: { payload: { stringValue: payload } } }, currentDocument: precondition }] });
    const response = await call('POST', `${url}:commit`, body);
    const data = response?.data;
    const write = data?.writeResults?.[0];
    if (!(response?.status === 200 && allowed(data, ['writeResults', 'commitTime']) &&
      Array.isArray(data.writeResults) && data.writeResults.length === 1 && allowed(write, ['updateTime'], ['transformResults']) &&
      (!Object.hasOwn(write, 'transformResults') || (Array.isArray(write.transformResults) && write.transformResults.length === 0)) &&
      micros(write.updateTime))) return false;
    const updated = nanoseconds(write.updateTime, true), committed = nanoseconds(data.commitTime, false);
    if (committed === null || updated > committed) return false;
    return !Object.hasOwn(precondition, 'updateTime') || updated > nanoseconds(precondition.updateTime, true);
  }

  async function armingBeforeStart(reference, start) {
    const after = snapshot(await bounded((signal) => clock.sample(signal)));
    return keys(after, ['lower_ms', 'upper_ms']) && number(after.lower_ms) && number(after.upper_ms) &&
      after.upper_ms >= after.lower_ms && after.upper_ms - after.lower_ms <= 5000 &&
      after.lower_ms >= reference.lower_ms && after.upper_ms >= reference.upper_ms && after.upper_ms <= start;
  }

  return Object.freeze({
    async create(input) {
      try {
        const base = snapshot(input);
        if (!keys(base, baseKeys) || !validBase(base) || baseKeys.some((key) => base[key] !== expected[key])) return result('unknown');
        const record = { ...base, schema_version: 1, state: 'unarmed', revision: 0, late: false, receipts: [] };
        return result(await commit(record, { exists: false }) ? 'applied' : 'unknown');
      } catch { return result('unknown'); }
    },
    async transition(input) {
      try {
        const command = snapshot(input);
        if (!keys(command, commandKeys) || !token(command.operation_id) || !token(command.generation) || !token(command.command_id) ||
            command.operation_id !== expected.operation_id || command.generation !== expected.generation ||
            !number(command.expected_revision) || !edges.has(`${command.expected_state}:${command.target_state}`)) return result('unknown');
        // Persisted arming is not durable readiness proof. Do not advance a
        // capture or cleanup transition until that independent protocol exists.
        if (command.expected_state !== 'unarmed' || command.target_state !== 'armed') return result('unknown');
        const current = await read(command.operation_id);
        if (!current || current.record.generation !== command.generation) return result('unknown');
        const previous = current.record.receipts.find((event) => event.command_id === command.command_id);
        if (previous) {
          if (previous.from !== command.expected_state || previous.to !== command.target_state || previous.revision !== command.expected_revision + 1) return result('unknown');
          if (previous.to === 'armed' && !(await armingBeforeStart(previous, current.record.capture_start_ms))) return result('unknown');
          return result('persisted_unverified');
        }
        if (current.record.revision !== command.expected_revision || current.record.state !== command.expected_state || current.record.receipts.length >= LIMIT) return result('unknown');
        const sample = snapshot(await bounded((signal) => clock.sample(signal)));
        if (!keys(sample, ['lower_ms', 'upper_ms']) || !number(sample.lower_ms) || !number(sample.upper_ms) ||
            sample.upper_ms < sample.lower_ms || sample.upper_ms - sample.lower_ms > 5000) return result('unknown');
        const event = { command_id: command.command_id, from: command.expected_state, to: command.target_state,
          revision: command.expected_revision + 1, lower_ms: sample.lower_ms, upper_ms: sample.upper_ms,
          late: current.record.late || sample.upper_ms >= current.record.deadline_ms };
        event.intent_sha256 = receiptHash(current.record, event);
        const next = { ...current.record, state: event.to, revision: event.revision, late: event.late, receipts: [...current.record.receipts, event] };
        if (!validRecord(next)) return result('unknown');
        const committed = await commit(next, { updateTime: current.updateTime });
        if (!committed) {
          const observed = await read(command.operation_id);
          const found = observed?.record.receipts.find((item) => item.command_id === command.command_id);
          if (!found || JSON.stringify(found) !== JSON.stringify(event) || observed.record.generation !== command.generation ||
              nanoseconds(observed.updateTime, true) <= nanoseconds(current.updateTime, true) ||
              baseKeys.some((key) => observed.record[key] !== current.record[key])) return result('unknown');
        }
        if (event.to === 'armed' && !(await armingBeforeStart(event, current.record.capture_start_ms))) return result('unknown');
        return result('persisted_unverified');
      } catch { return result('unknown'); }
    },
  });
}

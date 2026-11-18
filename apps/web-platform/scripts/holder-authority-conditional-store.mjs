import { createHash } from 'node:crypto';
import { prepareIntent } from './holder-authority-intent.mjs';

// Disposable fake implementing the shape of an atomic conditional store. No
// provider, durability, identity, trusted time, approval or authority exists.
// The validator checks canonical history shape, not authenticated principals,
// trusted time, approved base, durable storage or authority for side effects.
// A missing strong read after unknown is not evidence an in-flight write failed.
const keys = (x, names) => x && typeof x === 'object' && !Array.isArray(x) &&
  Object.keys(x).length === names.length && names.every(k => Object.hasOwn(x, k));
const digest = v => createHash('sha256').update(v).digest('hex');
const receiptKeys = ['command_id', 'intent_json', 'intent_sha256'];
const documentKeys = ['schema_version', 'state', 'revision', 'asserted_late', 'prepare', 'receipts'];
const baseKeys = ['operation_id', 'vault_id', 'owner_id', 'generation', 'manifest_sha256', 'controller_sha256', 'capture_start_ms', 'deadline_ms'];
const edges = { prepare: { unprepared: 'unarmed' }, arm: { unarmed: 'armed' }, begin_capture: { armed: 'capturing' },
  seal: { capturing: 'sealed' }, report_attempt: { sealed: 'deleting', deleting: 'deleting', revoked: 'revoked_deleting' },
  report_verified: { deleting: 'verification_asserted_unverified', revoked_deleting: 'verification_asserted_unverified' },
  revoke: { unarmed: 'revoked', armed: 'revoked', capturing: 'revoked', sealed: 'revoked', deleting: 'revoked' } };
const unknown = () => ({ state: 'unknown' });

function inspect(raw, expected) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > 65536) return null;
  try {
    const record = JSON.parse(raw);
    if (JSON.stringify(record) !== raw || !keys(record, documentKeys) || record.schema_version !== 2 ||
        !Array.isArray(record.receipts) || record.receipts.length > 8 || record.revision !== record.receipts.length ||
        typeof record.asserted_late !== 'boolean') return null;
    const all = [record.prepare, ...record.receipts], ids = new Set();
    let first, last, state = 'unprepared', assertedLate = false;
    for (let index = 0; index < all.length; index++) {
      const receipt = all[index];
      if (!keys(receipt, receiptKeys) || typeof receipt.command_id !== 'string' || !/^[a-f0-9]{32}$/.test(receipt.command_id) ||
          ids.has(receipt.command_id) || typeof receipt.intent_json !== 'string' || Buffer.byteLength(receipt.intent_json) > 8192 ||
          receipt.intent_sha256 !== digest(receipt.intent_json)) return null;
      ids.add(receipt.command_id);
      const intent = JSON.parse(receipt.intent_json);
      const intentKeys = ['domain', ...baseKeys, 'action', 'command_id', 'expected_state', 'target_state', 'expected_revision',
        'target_revision', 'principal_sha256', 'lower_ms', 'upper_ms', 'clock_decision'];
      if (!keys(intent, intentKeys) || JSON.stringify(intent) !== receipt.intent_json || intent.domain !== 'holder-authority-intent-v1' ||
          intent.command_id !== receipt.command_id || typeof intent.action !== 'string' || !Object.hasOwn(edges, intent.action) ||
          !Object.hasOwn(edges[intent.action], state) || intent.expected_state !== state ||
          intent.target_state !== edges[intent.action][state] || intent.expected_revision !== (index ? index - 1 : 0) ||
          intent.target_revision !== index || (index === 0 && intent.action !== 'prepare') ||
          typeof intent.principal_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(intent.principal_sha256) ||
          baseKeys.some(key => intent[key] !== expected[key])) return null;
      // Reuse the sole canonical preparer for shape, edge, reservation and
      // clock-decision validation. The principal digest remains an assertion:
      // the fake has no principal identity or authentication.
      const command = { action: intent.action, operation_id: intent.operation_id, generation: intent.generation,
        manifest_sha256: intent.manifest_sha256, command_id: intent.command_id,
        expected_revision: intent.expected_revision, expected_state: intent.expected_state };
      const base = Object.fromEntries(baseKeys.map(key => [key, intent[key]]));
      const prepared = prepareIntent({ base: JSON.stringify(base), command: JSON.stringify(command),
        principal: JSON.stringify({ issuer: 'https://synthetic.example', subject: 'synthetic' }),
        clock: JSON.stringify({ lower_ms: intent.lower_ms, upper_ms: intent.upper_ms }) });
      if (prepared.state !== 'prepared_unverified') return null;
      const regenerated = JSON.parse(prepared.intent_json);
      regenerated.principal_sha256 = intent.principal_sha256;
      if (JSON.stringify(regenerated) !== receipt.intent_json ||
          (last && (intent.lower_ms < last.lower_ms || intent.upper_ms < last.upper_ms)) ||
          intent.clock_decision === 'uncertain' ||
          (['prepare', 'arm'].includes(intent.action) && intent.clock_decision !== 'before_start') ||
          (intent.action === 'begin_capture' && intent.clock_decision !== 'inside_window') ||
          (['seal', 'report_attempt', 'report_verified'].includes(intent.action) && intent.clock_decision === 'before_start')) return null;
      if (!first) first = intent;
      else if (baseKeys.some(key => intent[key] !== first[key])) return null;
      assertedLate ||= intent.clock_decision === 'at_or_after_deadline';
      last = intent;
      state = intent.target_state;
    }
    return record.state === state && record.asserted_late === assertedLate ? record : null;
  } catch { return null; }
}

// Shared shape validation only; it does not authenticate the base or establish
// durable provider state. Accept strings to avoid caller-owned object mutation.
export function validateV2History(raw, expectedBaseJson) {
  try {
    if (typeof expectedBaseJson !== 'string' || Buffer.byteLength(expectedBaseJson) > 4096) return false;
    const expected = JSON.parse(expectedBaseJson);
    return JSON.stringify(expected) === expectedBaseJson && keys(expected, baseKeys) && !!inspect(raw, expected);
  } catch { return false; }
}

export function createSyntheticConditionalStore(expectedBaseJson) {
  if (typeof expectedBaseJson !== 'string' || Buffer.byteLength(expectedBaseJson, 'utf8') > 4096) throw new Error('fixture_base');
  let expected;
  try { expected = JSON.parse(expectedBaseJson); } catch { throw new Error('fixture_base'); }
  if (JSON.stringify(expected) !== expectedBaseJson || !keys(expected, baseKeys)) throw new Error('fixture_base');
  let document = null, revision = 0, delay = false, pending = null;
  function apply(expected, next) {
    if (revision !== expected) return false;
    document = next; revision++; return true;
  }
  function write(expected, next) {
    if (delay) {
      if (pending) return unknown();
      delay = false; pending = () => apply(expected, next); return unknown();
    }
    return { state: apply(expected, next) ? 'committed_unverified' : 'conflict' };
  }
  return Object.freeze({
    // readStrong is strong only relative to this fake process's local state.
    async readStrong() {
      if (document === null) return { state: 'absent' };
      return inspect(document, expected) ? { state: 'found', version: `v${revision}`, document } : unknown();
    },
    async createIfAbsent(raw) {
      const candidate = inspect(raw, expected);
      if (!candidate || candidate.revision !== 0) return unknown();
      if (document !== null) return { state: 'conflict' };
      return write(revision, raw);
    },
    async compareAndSwap(version, raw) {
      const candidate = inspect(raw, expected);
      if (!candidate || typeof version !== 'string') return unknown();
      if (document === null || version !== `v${revision}`) return { state: 'conflict' };
      const prior = inspect(document, expected);
      if (!prior || candidate.revision !== prior.revision + 1 || JSON.stringify(candidate.prepare) !== JSON.stringify(prior.prepare) ||
          JSON.stringify(candidate.receipts.slice(0, -1)) !== JSON.stringify(prior.receipts)) return unknown();
      return write(revision, raw);
    },
    delayNextWrite() { if (delay || pending) throw new Error('fixture_pending'); delay = true; },
    releaseDelayed() { if (!pending) throw new Error('fixture_pending'); const run = pending; pending = null; return run(); },
    // Test-only corruption injection; no provider or persistent storage exists.
    loadRawFixture(raw) {
      if (typeof raw !== 'string' || Buffer.byteLength(raw) > 65536 || pending || delay) throw new Error('fixture_invalid');
      document = raw; revision++;
    },
  });
}

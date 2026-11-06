import { prepareIntent } from './holder-authority-intent.mjs';

// In-memory fixture only: no provider, credentials, authentication, durable
// storage, trusted clock, incident delivery, vault access or authorization.
// This is not a Firestore adapter and must not be used for real evidence.
const denied = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const result = (state) => ({ state, capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const clone = (value) => value === null ? null : JSON.parse(JSON.stringify(value));
const baseFields = ['operation_id', 'vault_id', 'owner_id', 'generation', 'manifest_sha256', 'controller_sha256', 'capture_start_ms', 'deadline_ms'];

export function createOfflineLedger(expectedBaseJson) {
  let expected;
  try { expected = JSON.parse(expectedBaseJson); } catch { throw new Error('invalid fixture'); }
  if (typeof expectedBaseJson !== 'string' || expectedBaseJson.length > 4096 || JSON.stringify(expected) !== expectedBaseJson ||
      !expected || typeof expected !== 'object' || Array.isArray(expected) || Object.keys(expected).length !== baseFields.length ||
      !baseFields.every((field) => Object.hasOwn(expected, field))) throw new Error('invalid fixture');
  let document = null, version = 0, delay = false, pending = null;

  function compareAndSet(expectedVersion, next) {
    if (version !== expectedVersion) return false;
    document = clone(next); version++;
    return true;
  }
  function commit(expectedVersion, next) {
    if (delay) {
      if (pending) return false;
      delay = false;
      pending = () => compareAndSet(expectedVersion, next);
      return false;
    }
    return compareAndSet(expectedVersion, next);
  }
  return Object.freeze({
    delayNextCommit() { if (pending || delay) throw new Error('fixture already delayed'); delay = true; },
    releaseDelayed() { if (!pending) throw new Error('no fixture commit'); const action = pending; pending = null; return action(); },
    snapshot() { return clone(document); },
    async submit(input) {
      try {
        const prepared = prepareIntent(input);
        if (prepared.state !== 'prepared_unverified') return denied();
        const intent = JSON.parse(prepared.intent_json);
        if (baseFields.some((field) => expected[field] !== intent[field])) return denied();
        const observed = clone(document), observedVersion = version;
        await Promise.resolve(); // Allow concurrent calls to race on the same revision.
        const receipt = { command_id: intent.command_id, intent_json: prepared.intent_json, intent_sha256: prepared.intent_sha256 };
        if (!observed) {
          if (intent.action !== 'prepare' || intent.clock_decision !== 'before_start') return denied();
          const created = { schema_version: 2, state: 'unarmed', revision: 0, asserted_late: false, prepare: receipt, receipts: [] };
          return commit(observedVersion, created) ? result('persisted_unverified') : denied();
        }
        const previous = [observed.prepare, ...observed.receipts].find((entry) => entry.command_id === intent.command_id);
        if (previous) return previous.intent_json === receipt.intent_json && previous.intent_sha256 === receipt.intent_sha256
          ? result('historical_unverified') : denied();
        const last = JSON.parse((observed.receipts.at(-1) ?? observed.prepare).intent_json);
        if (intent.lower_ms < last.lower_ms || intent.upper_ms < last.upper_ms || intent.clock_decision === 'uncertain' ||
            (intent.action === 'arm' && intent.clock_decision !== 'before_start') ||
            (intent.action === 'begin_capture' && intent.clock_decision !== 'inside_window') ||
            (['seal', 'report_attempt', 'report_verified'].includes(intent.action) && intent.clock_decision === 'before_start')) return denied();
        if (intent.action === 'prepare' || observed.state !== intent.expected_state || observed.revision !== intent.expected_revision ||
            observed.receipts.length >= 8) return denied();
        const next = { ...observed, state: intent.target_state, revision: intent.target_revision,
          asserted_late: observed.asserted_late || intent.clock_decision === 'at_or_after_deadline', receipts: [...observed.receipts, receipt] };
        return commit(observedVersion, next) ? result('persisted_unverified') : denied();
      } catch { return denied(); }
    },
  });
}

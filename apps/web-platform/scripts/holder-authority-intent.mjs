import { createHash } from 'node:crypto';

// This pure preparation boundary is intentionally unwired. Its inputs are
// assertions, not evidence of authentication, approval, trusted time, current
// revision or readiness. A hash is not authorization or a replay store.
const MAX_DAY = 24 * 60 * 60 * 1000;
const baseFields = ['operation_id', 'vault_id', 'owner_id', 'generation', 'manifest_sha256', 'controller_sha256', 'capture_start_ms', 'deadline_ms'];
const commandFields = ['action', 'operation_id', 'generation', 'manifest_sha256', 'command_id', 'expected_revision', 'expected_state'];
const principalFields = ['issuer', 'subject'];
const clockFields = ['lower_ms', 'upper_ms'];
const edges = Object.freeze({ prepare: { unprepared: 'unarmed' }, arm: { unarmed: 'armed' },
  begin_capture: { armed: 'capturing' }, seal: { capturing: 'sealed' },
  report_attempt: { sealed: 'deleting', deleting: 'deleting', revoked: 'revoked_deleting' },
  report_verified: { deleting: 'verification_asserted_unverified', revoked_deleting: 'verification_asserted_unverified' },
  revoke: { unarmed: 'revoked', armed: 'revoked', capturing: 'revoked', sealed: 'revoked', deleting: 'revoked' } });
// Initial creation writes unarmed revision zero; each later transition appends
// one receipt. The last three slots are reserved for revoke, post-revoke
// cleanup and verification. This is shape validation, not current-state proof.
const reachable = Object.freeze({ unprepared: [0], unarmed: [0], armed: [1], capturing: [2], sealed: [3], deleting: [4, 5],
  revoked: [1, 2, 3, 4, 5, 6], revoked_deleting: [2, 3, 4, 5, 6, 7] });
const denied = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const hex = (v, n) => typeof v === 'string' && v.length === n && /^[0-9a-f]+$/.test(v);
const integer = (v) => Number.isSafeInteger(v) && v >= 0;
const sha = (v) => createHash('sha256').update(v).digest('hex');

function parse(raw, fields) {
  if (typeof raw !== 'string' || Buffer.byteLength(raw, 'utf8') > 4096) return null;
  const obj = JSON.parse(raw);
  // This excludes duplicate keys, whitespace variants and malformed Unicode.
  if (JSON.stringify(obj) !== raw || !obj || typeof obj !== 'object' || Array.isArray(obj) ||
      Object.keys(obj).length !== fields.length || !fields.every((field) => Object.hasOwn(obj, field))) return null;
  return obj;
}

export function prepareIntent(input) {
  try {
    if (!input || typeof input !== 'object' || Array.isArray(input) ||
        ![Object.prototype, null].includes(Object.getPrototypeOf(input)) || Reflect.ownKeys(input).length !== 4) return denied();
    const descriptors = Object.getOwnPropertyDescriptors(input);
    if (!['base', 'command', 'principal', 'clock'].every((field) => Object.hasOwn(descriptors[field] ?? {}, 'value'))) return denied();
    const base = parse(descriptors.base.value, baseFields);
    const command = parse(descriptors.command.value, commandFields);
    const principal = parse(descriptors.principal.value, principalFields);
    const clock = parse(descriptors.clock.value, clockFields);
    if (!base || !command || !principal || !clock ||
        !['operation_id', 'vault_id', 'owner_id', 'generation'].every((field) => hex(base[field], 32)) ||
        !hex(base.manifest_sha256, 64) || !hex(base.controller_sha256, 64) ||
        !integer(base.capture_start_ms) || !integer(base.deadline_ms) || base.deadline_ms <= base.capture_start_ms ||
        base.deadline_ms - base.capture_start_ms > MAX_DAY ||
        command.operation_id !== base.operation_id || command.generation !== base.generation || command.manifest_sha256 !== base.manifest_sha256 ||
        !hex(command.command_id, 32) || !integer(command.expected_revision) || command.expected_revision >= 8 ||
        typeof command.action !== 'string' || !Object.hasOwn(edges, command.action) ||
        typeof command.expected_state !== 'string' || !Object.hasOwn(edges[command.action], command.expected_state) ||
        !Object.hasOwn(reachable, command.expected_state) || !reachable[command.expected_state].includes(command.expected_revision) ||
        (command.action === 'report_attempt' && command.expected_state === 'deleting' && command.expected_revision >= 5) ||
        typeof principal.issuer !== 'string' || !/^https:\/\/[a-zA-Z0-9.-]{1,128}$/.test(principal.issuer) ||
        typeof principal.subject !== 'string' || !/^[a-zA-Z0-9._-]{1,128}$/.test(principal.subject) ||
        !integer(clock.lower_ms) || !integer(clock.upper_ms) || clock.upper_ms < clock.lower_ms || clock.upper_ms - clock.lower_ms > 5000) return denied();

    let decision = 'uncertain';
    if (clock.upper_ms < base.capture_start_ms) decision = 'before_start';
    else if (clock.lower_ms >= base.deadline_ms) decision = 'at_or_after_deadline';
    else if (clock.lower_ms >= base.capture_start_ms && clock.upper_ms < base.deadline_ms) decision = 'inside_window';

    const intent = { domain: 'holder-authority-intent-v1', ...Object.fromEntries(baseFields.map((field) => [field, base[field]])),
      action: command.action, command_id: command.command_id, expected_state: command.expected_state,
      target_state: edges[command.action][command.expected_state], expected_revision: command.expected_revision,
      target_revision: command.action === 'prepare' ? 0 : command.expected_revision + 1,
      principal_sha256: sha(JSON.stringify(['holder-authority-principal-v1', principal.issuer, principal.subject])),
      lower_ms: clock.lower_ms, upper_ms: clock.upper_ms, clock_decision: decision };
    const intent_json = JSON.stringify(intent);
    return { state: 'prepared_unverified', capture_authorized: false, cleanup_authorized: false, deletion_verified: false,
      intent_json, intent_sha256: sha(intent_json) };
  } catch { return denied(); }
}

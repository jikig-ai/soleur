import { randomBytes, verify } from 'node:crypto';

// Evidence only. The pinned key and injected monotonic source are claims from
// configuration, not proof of an independently operated or accurate clock.
// This cannot authorize capture, cleanup, persistence, or verification.
// The returned interval describes the final monotonic sampling instant only;
// it cannot fence a later mutation, which needs a fresh independent check.
const denied = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const integer = v => Number.isSafeInteger(v) && v >= 0;
const exact = (v, names) => v && typeof v === 'object' && !Array.isArray(v) &&
  Object.keys(v).length === names.length && names.every(k => Object.hasOwn(v, k));
const flags = { capture_authorized: false, cleanup_authorized: false, deletion_verified: false };
function snapshot(value, names) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value)) || Reflect.ownKeys(value).length !== names.length) throw new Error('time_unknown');
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (!names.every(key => Object.hasOwn(descriptors[key] ?? {}, 'value'))) throw new Error('time_unknown');
  return Object.fromEntries(names.map(key => [key, descriptors[key].value]));
}

export function createTimeEvidenceVerifier({ issuer, publicKey, operation, maxTransitMs, maxUncertaintyMs, monotonicNow }) {
  if (typeof issuer !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,79}$/.test(issuer) ||
      typeof operation !== 'string' || !/^[a-f0-9]{32}$/.test(operation) ||
      publicKey?.type !== 'public' || publicKey.asymmetricKeyType !== 'ed25519' ||
      !integer(maxTransitMs) || maxTransitMs < 1 || maxTransitMs > 5000 ||
      !integer(maxUncertaintyMs) || maxUncertaintyMs > 5000 || typeof monotonicNow !== 'function') throw new Error('time_configuration');
  let lastMonotonic = -1, lastLower = 0;
  function monotonic() {
    const now = monotonicNow();
    if (typeof now !== 'number' || !Number.isFinite(now) || now < 0 || now < lastMonotonic) throw new Error('time_unknown');
    lastMonotonic = now;
    return now;
  }
  return Object.freeze({
    begin() {
      let start, nonce;
      try { start = monotonic(); nonce = randomBytes(32).toString('hex'); }
      catch { throw new Error('time_unknown'); }
      let used = false;
      return Object.freeze({ nonce, verify(input, window) {
        if (used) return denied();
        used = true;
        try {
          input = snapshot(input, ['sample', 'signature']);
          window = snapshot(window, ['capture_start_ms', 'deadline_ms']);
          if (!input || typeof input.sample !== 'string' || Buffer.byteLength(input.sample) > 2048 ||
              typeof input.signature !== 'string' || input.signature.length !== 88 || !window ||
              !integer(window.capture_start_ms) || !integer(window.deadline_ms) || window.deadline_ms <= window.capture_start_ms) return denied();
          const sample = JSON.parse(input.sample);
          if (!exact(sample, ['domain', 'issuer', 'operation', 'nonce', 'lower_ms', 'upper_ms']) ||
              JSON.stringify(sample) !== input.sample || sample.domain !== 'holder-time-evidence-v1' || sample.issuer !== issuer ||
              sample.operation !== operation || sample.nonce !== nonce || !integer(sample.lower_ms) || !integer(sample.upper_ms) ||
              sample.upper_ms < sample.lower_ms || sample.upper_ms - sample.lower_ms > maxUncertaintyMs) return denied();
          const signature = Buffer.from(input.signature, 'base64');
          if (signature.length !== 64 || signature.toString('base64') !== input.signature ||
              !verify(null, Buffer.from(input.sample), publicKey, signature)) return denied();
          const end = monotonic(), elapsed = Math.ceil(end - start);
          if (elapsed > maxTransitMs || !Number.isSafeInteger(sample.upper_ms + elapsed)) return denied();
          const lower = sample.lower_ms, upper = sample.upper_ms + elapsed;
          if (upper < lastLower) return denied();
          lastLower = Math.max(lastLower, lower);
          let decision = 'uncertain';
          if (upper < window.capture_start_ms) decision = 'before_start';
          else if (lower >= window.deadline_ms) decision = 'at_or_after_deadline';
          else if (lower >= window.capture_start_ms && upper < window.deadline_ms) decision = 'inside_window';
          return { state: 'verified_evidence_only', lower_ms: lower, upper_ms: upper, decision, ...flags };
        } catch { return denied(); }
      } });
    },
  });
}

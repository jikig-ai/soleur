// Offline identity experiment only. It does not authenticate a real provider,
// bind a request to a token, access a ledger, or authorize any operation.
// Each subject is modeled as holding its own private key; this is not the
// shared issuer signing-key model used by real identity providers.
import { KeyObject, verify } from 'node:crypto';

const actions = Object.freeze({ prepare: 'admin', arm: 'admin', begin_capture: 'collector', seal: 'collector',
  report_attempt: 'worker', report_verified: 'verifier', revoke: 'admin' });
const deny = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const recognized = () => ({ state: 'recognized_unverified', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const identifier = (v) => typeof v === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(v);
const hex = (v, size) => typeof v === 'string' && v.length === size && /^[a-f0-9]+$/.test(v);
const integer = (v) => Number.isSafeInteger(v) && v >= 0;

function snapshot(value, fields) {
  if (!value || typeof value !== 'object' || ![Object.prototype, null].includes(Object.getPrototypeOf(value)) ||
      Reflect.ownKeys(value).length !== fields.length) return null;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (!fields.every((key) => Object.hasOwn(descriptors[key] ?? {}, 'value'))) return null;
  return Object.fromEntries(fields.map((key) => [key, descriptors[key].value]));
}

function decode(part, maxBytes) {
  if (typeof part !== 'string' || !/^[A-Za-z0-9_-]+$/.test(part) || part.length > maxBytes * 2) throw new Error('invalid');
  const bytes = Buffer.from(part, 'base64url');
  if (bytes.length > maxBytes || bytes.toString('base64url') !== part) throw new Error('invalid');
  return bytes;
}

function json(part, maxBytes) {
  const bytes = decode(part, maxBytes);
  const text = bytes.toString('utf8');
  const parsed = JSON.parse(text);
  // A canonical encoding also rules out duplicate keys and invalid UTF-8.
  if (JSON.stringify(parsed) !== text) throw new Error('invalid');
  return parsed;
}

export function createSyntheticAuthority({ identities, audience }) {
  if (!identifier(audience) || !Array.isArray(identities) || identities.length < 1 || identities.length > 16) throw new Error('invalid configuration');
  const bindings = new Map();
  const subjectKeys = new Set();
  for (const item of identities) {
    const entry = snapshot(item, ['issuer', 'subject', 'audience', 'publicKey', 'role']);
    if (!entry || !identifier(entry.issuer) || !identifier(entry.subject) || entry.audience !== audience ||
        !Object.values(actions).includes(entry.role) || !(entry.publicKey instanceof KeyObject) || entry.publicKey.type !== 'public' ||
        entry.publicKey.asymmetricKeyType !== 'ed25519') throw new Error('invalid configuration');
    const key = JSON.stringify([entry.issuer, entry.subject, entry.audience]);
    const publicKeyBytes = entry.publicKey.export({ type: 'spki', format: 'der' }).toString('hex');
    if (bindings.has(key) || subjectKeys.has(publicKeyBytes)) throw new Error('duplicate identity or key');
    subjectKeys.add(publicKeyBytes);
    bindings.set(key, Object.freeze({ role: entry.role, publicKey: entry.publicKey }));
  }
  return Object.freeze({
    inspect(input) {
      try {
        const request = snapshot(input, ['token', 'command', 'now_ms']);
        if (!request || typeof request.token !== 'string' || request.token.length > 4096 || !integer(request.now_ms)) return deny();
        const cmd = snapshot(request.command, ['action', 'operation_id', 'generation', 'manifest_sha256', 'command_id']);
        if (!cmd || !Object.hasOwn(actions, cmd.action) || !hex(cmd.operation_id, 32) || !hex(cmd.generation, 32) ||
            !hex(cmd.manifest_sha256, 64) || !hex(cmd.command_id, 32)) return deny();
        const parts = request.token.split('.');
        if (parts.length !== 3) return deny();
        const header = snapshot(json(parts[0], 256), ['alg', 'typ']);
        const claim = snapshot(json(parts[1], 1024), ['issuer', 'audience', 'subject', 'issued_ms', 'expires_ms']);
        if (!header || header.alg !== 'EdDSA' || header.typ !== 'JWT' || !claim ||
            !identifier(claim.issuer) || !identifier(claim.subject) || claim.audience !== audience ||
            !integer(claim.issued_ms) || !integer(claim.expires_ms) || claim.issued_ms > request.now_ms ||
            request.now_ms >= claim.expires_ms || claim.expires_ms <= claim.issued_ms ||
            claim.expires_ms - claim.issued_ms > 300000) return deny();
        const binding = bindings.get(JSON.stringify([claim.issuer, claim.subject, claim.audience]));
        if (!binding || binding.role !== actions[cmd.action]) return deny();
        const signature = decode(parts[2], 64);
        if (signature.length !== 64 || !verify(null, Buffer.from(`${parts[0]}.${parts[1]}`), binding.publicKey, signature)) return deny();
        return recognized();
      } catch { return deny(); }
    },
  });
}

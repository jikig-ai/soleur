// Synthetic signature experiment only. A signature does not establish
// current authority, replay protection, ownership, safe deletion or admission.
import { verify } from 'node:crypto';

const id = (value) => typeof value === 'string' && /^[a-z0-9][a-z0-9._-]{0,79}$/.test(value);
const unknown = () => ({ state: 'unknown', authorizes_cleanup: false });
const fields = ['operation_id', 'vault_id', 'generation', 'owner_id', 'service_id', 'manifest_sha256', 'deadline_ms', 'entries'];

export function capsuleMessage(c) {
  return Buffer.from(JSON.stringify(['holder-synthetic-capsule-v1', c.operation_id, c.vault_id,
    c.generation, c.owner_id, c.service_id, c.manifest_sha256, c.deadline_ms, c.entries]));
}

export function verifyCapsule(c, signature, publicKey) {
  try {
    if (!c || typeof c !== 'object' || ![Object.prototype, null].includes(Object.getPrototypeOf(c)) ||
        Reflect.ownKeys(c).length !== fields.length || !fields.every((key) => Object.hasOwn(c, key))) return unknown();
    const descriptors = Object.getOwnPropertyDescriptors(c);
    if (!fields.every((key) => Object.hasOwn(descriptors[key] ?? {}, 'value'))) return unknown();
    c = Object.fromEntries(fields.map((key) => [key, descriptors[key].value]));
    if (!Array.isArray(c.entries)) return unknown();
    const entryDescriptors = Object.getOwnPropertyDescriptors(c.entries);
    const length = entryDescriptors.length?.value;
    if (!Number.isSafeInteger(length) || length < 1 || length > 16 || Reflect.ownKeys(c.entries).length !== length + 1 ||
        !Array.from({ length }, (_, i) => entryDescriptors[String(i)]).every((entry) => entry && Object.hasOwn(entry, 'value'))) return unknown();
    c.entries = Array.from({ length }, (_, i) => entryDescriptors[String(i)].value);
    if (
        !['operation_id', 'vault_id', 'generation', 'owner_id', 'service_id'].every((key) => id(c[key])) ||
        typeof c.manifest_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(c.manifest_sha256) ||
        !Number.isSafeInteger(c.deadline_ms) || c.deadline_ms < 0 ||
        c.entries.length < 1 || c.entries.length > 16 || !c.entries.every(id) ||
        c.entries.some((entry, index) => index > 0 && c.entries[index - 1] >= entry) ||
        publicKey?.type !== 'public' || publicKey.asymmetricKeyType !== 'ed25519' || typeof signature !== 'string') return unknown();
    const sig = Buffer.from(signature, 'base64');
    if (sig.length !== 64 || sig.toString('base64') !== signature || !verify(null, capsuleMessage(c), publicKey, sig)) return unknown();
    return { state: 'signature_valid_only', authorizes_cleanup: false };
  } catch { return unknown(); }
}

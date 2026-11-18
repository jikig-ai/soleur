// Offline byte-binding experiment only. It does not inspect executable behavior,
// prove that the SQL is embedded in it, bind a runtime, or authorize collection.
import { createHash } from 'node:crypto';
import { types } from 'node:util';

const unknown = () => ({ state: 'unknown', authorizes_collection: false });
const sha = (value) => createHash('sha256').update(value).digest('hex');
const digest = (value) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const backingStore = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const byteOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const byteLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const copyInto = typedArrayPrototype.set;
const snapshot = (value, max) => {
  if (!Buffer.isBuffer(value)) throw new Error('source');
  const backing = backingStore.call(value), offset = byteOffset.call(value), length = byteLength.call(value);
  if (types.isSharedArrayBuffer(backing) || length < 1 || length > max) throw new Error('source');
  const copy = Buffer.allocUnsafe(length);
  copyInto.call(copy, new Uint8Array(backing, offset, length));
  return copy;
};

// The closure owns its snapshots. copyBytes returns fresh, mutable copies;
// a later launcher must protect and execute the exact copies it receives.
export function createSyntheticSnapshot(input) {
  try {
    const manifest = snapshot(input.manifest, 8192);
    const executable = snapshot(input.executable, 1048576);
    const roles = snapshot(input.roles, 1048576);
    const memberships = snapshot(input.memberships, 1048576);
    const approved = input.approvedManifestSha256;
    if (!digest(approved) || sha(manifest) !== approved) return unknown();
    const parsed = JSON.parse(manifest.toString('utf8'));
    if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') return unknown();
    const keys = ['version', 'executable_sha256', 'roles_sha256', 'memberships_sha256', 'max_rows', 'max_bytes', 'timeout_ms'];
    if (Object.keys(parsed).length !== keys.length || !keys.every((key, index) => Object.keys(parsed)[index] === key) ||
        !Buffer.from(JSON.stringify(parsed)).equals(manifest) || parsed.version !== 1 ||
        ![parsed.executable_sha256, parsed.roles_sha256, parsed.memberships_sha256].every(digest) ||
        !Number.isSafeInteger(parsed.max_rows) || parsed.max_rows < 1 || parsed.max_rows > 100000 ||
        !Number.isSafeInteger(parsed.max_bytes) || parsed.max_bytes < 1 || parsed.max_bytes > 1048576 ||
        !Number.isSafeInteger(parsed.timeout_ms) || parsed.timeout_ms < 1 || parsed.timeout_ms > 60000 ||
        sha(executable) !== parsed.executable_sha256 || sha(roles) !== parsed.roles_sha256 ||
        sha(memberships) !== parsed.memberships_sha256) return unknown();
    const limits = Object.freeze({ max_rows: parsed.max_rows, max_bytes: parsed.max_bytes, timeout_ms: parsed.timeout_ms });
    return Object.freeze({ state: 'synthetic_match', authorizes_collection: false, limits,
      copyBytes: () => ({ manifest: Buffer.from(manifest), executable: Buffer.from(executable),
        roles: Buffer.from(roles), memberships: Buffer.from(memberships) }) });
  } catch { return unknown(); }
}

export function verifySyntheticManifest(input) {
  const result = createSyntheticSnapshot(input);
  return { state: result.state, authorizes_collection: false };
}

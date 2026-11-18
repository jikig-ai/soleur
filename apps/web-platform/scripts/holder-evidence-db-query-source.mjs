import { createHash } from 'node:crypto';
import { types } from 'node:util';

const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const backingStore = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const byteOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset').get;
const byteLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const copyInto = typedArrayPrototype.set;

// Verify only the supplied query bytes, not the caller, pin or executable.
export function verifiedQuery(bytes, expectedSha256) {
  if (!(bytes instanceof Uint8Array) || typeof expectedSha256 !== 'string' || !/^[a-f0-9]{64}$/.test(expectedSha256)) throw new Error('source');
  const backing = backingStore.call(bytes), offset = byteOffset.call(bytes), length = byteLength.call(bytes);
  if (types.isSharedArrayBuffer(backing) || length < 1 || length > 1024 * 1024) throw new Error('source');
  const snapshot = Buffer.allocUnsafe(length);
  copyInto.call(snapshot, new Uint8Array(backing, offset, length));
  if (createHash('sha256').update(snapshot).digest('hex') !== expectedSha256 ||
      (snapshot[0] === 0xef && snapshot[1] === 0xbb && snapshot[2] === 0xbf)) throw new Error('source');
  const query = new TextDecoder('utf-8', { fatal: true }).decode(snapshot);
  if (query.includes('\0')) throw new Error('source');
  return query;
}

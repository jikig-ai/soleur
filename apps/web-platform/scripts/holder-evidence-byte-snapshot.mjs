import { types } from 'node:util';

// Bound the real view and copy before yielding control. A private copy does not
// authenticate the source or prove the transport stopped after cancellation.
const prototype = Object.getPrototypeOf(Uint8Array.prototype);
const backingStore = Object.getOwnPropertyDescriptor(prototype, 'buffer').get;
const byteOffset = Object.getOwnPropertyDescriptor(prototype, 'byteOffset').get;
const byteLength = Object.getOwnPropertyDescriptor(prototype, 'byteLength').get;
const copyInto = prototype.set;

export function snapshotBytes(value, maxBytes) {
  if (!types.isUint8Array(value) || !Number.isSafeInteger(maxBytes) || maxBytes < 0) throw new Error('invalid_bytes');
  const backing = backingStore.call(value), offset = byteOffset.call(value), length = byteLength.call(value);
  if (types.isSharedArrayBuffer(backing) || length > maxBytes) throw new Error('invalid_bytes');
  const copy = Buffer.allocUnsafe(length);
  copyInto.call(copy, new Uint8Array(backing, offset, length));
  return copy;
}

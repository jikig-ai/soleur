import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runInNewContext } from 'node:vm';
import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

test('copies only the actual bounded view, without invoking caller conversion', () => {
  const backing = Buffer.from('prefixACTUALsuffix');
  const view = backing.subarray(6, 12);
  Object.defineProperty(view, 'byteLength', { value: 1 });
  view.valueOf = () => Buffer.from('forged');
  assert.throws(() => snapshotBytes(view, 5));
  const copy = snapshotBytes(view, 6);
  backing.fill(0);
  assert.equal(copy.toString(), 'ACTUAL');
});

test('rejects shared backing even across realms and with shadowed buffer', () => {
  for (const shared of [new SharedArrayBuffer(4), runInNewContext('new SharedArrayBuffer(4)')]) {
    const view = Buffer.from(shared);
    Object.defineProperty(view, 'buffer', { value: new ArrayBuffer(4) });
    assert.throws(() => snapshotBytes(view, 4));
  }
});

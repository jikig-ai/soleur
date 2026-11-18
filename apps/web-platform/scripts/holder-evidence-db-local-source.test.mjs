import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readBoundedHandle } from './holder-evidence-db-local-source.mjs';

test('a file growing after stat is bounded and refused', async () => {
  let consumed = 0;
  const handle = {
    async stat() { return { isFile: () => true, size: 1 }; },
    async read(buffer, offset, length) { buffer.fill(97, offset, offset + length); consumed += length; return { bytesRead: length }; },
  };
  await assert.rejects(readBoundedHandle(handle));
  assert.equal(consumed, 2);
});

test('a stable short file reads exactly the declared bytes', async () => {
  const data = Buffer.from('synthetic');
  const handle = {
    async stat() { return { isFile: () => true, size: data.length }; },
    async read(buffer, offset, length, position) {
      const count = Math.min(length, Math.max(0, data.length - position));
      data.copy(buffer, offset, position, position + count);
      return { bytesRead: count };
    },
  };
  assert.deepEqual(await readBoundedHandle(handle), data);
});

test('truncated, nonregular, empty, oversized and invalid reads are refused', async () => {
  const make = (size, regular, bytesRead) => ({
    async stat() { return { isFile: () => regular, size }; },
    async read() { return { bytesRead }; },
  });
  for (const handle of [make(2, true, 0), make(1, false, 0), make(0, true, 0),
    make(1024 * 1024 + 1, true, 0), make(1, true, -1), make(1, true, 3)]) {
    await assert.rejects(readBoundedHandle(handle));
  }
});

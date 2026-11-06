import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createLedger } from './holder-retention-firestore-ledger.mjs';
import { makeFirestoreTransport } from './holder-retention-firestore-transport.mjs';

test('the unwired authority boundary refuses ledger writes before credentials or network', async () => {
  const calls = [];
  let document = null, revision = 0;
  const open = (options, callback) => {
    const request = new EventEmitter();
    request.setTimeout = () => request;
    request.destroy = () => {};
    request.end = (body) => process.nextTick(() => {
      calls.push({ options, body });
      const response = new EventEmitter(); response.statusCode = 200; response.destroy = () => {};
      let output;
      if (options.method === 'GET') output = document;
      else {
        const write = JSON.parse(body).writes[0];
        revision++;
        const time = `2026-10-28T00:00:0${revision}.000000Z`;
        document = { ...write.update, updateTime: time };
        output = { writeResults: [{ updateTime: time }], commitTime: time };
      }
      callback(response); response.emit('data', Buffer.from(JSON.stringify(output))); response.emit('end'); response.emit('close');
    });
    return request;
  };
  const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32),
    manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
  let tokenCalls = 0;
  const request = makeFirestoreTransport({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
    getAccessToken: async () => { tokenCalls++; return 'synthetic-token'; }, requestImpl: open });
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base, request,
    clock: { async sample() { return { lower_ms: 90000, upper_ms: 90000 }; } } });
  const result = await ledger.create(base);
  assert.equal(result.state, 'unknown');
  assert.equal(result.capture_authorized, false);
  assert.equal(result.deletion_verified, false);
  assert.equal(calls.length, 0);
  assert.equal(tokenCalls, 0);
});

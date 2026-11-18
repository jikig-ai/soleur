import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createLedger } from './holder-retention-firestore-ledger.mjs';
import { prepareIntent } from './holder-authority-intent.mjs';

test('current v1 ledger receipt does not attest to the separately prepared arm intent', async () => {
  const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32),
    manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
  const cmd = { operation_id: base.operation_id, generation: base.generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) };
  const input = { base: JSON.stringify(base), command: JSON.stringify({ action: 'arm', operation_id: base.operation_id,
    generation: base.generation, manifest_sha256: base.manifest_sha256, command_id: cmd.command_id,
    expected_revision: cmd.expected_revision, expected_state: cmd.expected_state }),
    principal: JSON.stringify({ issuer: 'https://issuer.example', subject: 'synthetic-subject' }),
    clock: JSON.stringify({ lower_ms: 90000, upper_ms: 90000 }) };
  const prepared = prepareIntent(input);
  assert.equal(prepared.state, 'prepared_unverified');
  let document = null, revision = 0;
  const request = async ({ method, body }) => {
    if (method === 'GET') return { status: 200, body: JSON.stringify(document) };
    const write = JSON.parse(body).writes[0];
    if (revision === 0) assert.deepEqual(write.currentDocument, { exists: false });
    else assert.equal(write.currentDocument.updateTime, document.updateTime);
    revision++;
    const time = `2026-10-28T00:00:0${revision}.000000Z`;
    document = { ...write.update, updateTime: time };
    return { status: 200, body: JSON.stringify({ writeResults: [{ updateTime: time }], commitTime: time }) };
  };
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base, request,
    clock: { async sample() { return { lower_ms: 90000, upper_ms: 90000 }; } } });
  assert.equal((await ledger.create(base)).state, 'applied');
  assert.equal((await ledger.transition(cmd)).state, 'persisted_unverified');
  const record = JSON.parse(document.fields.payload.stringValue);
  assert.equal(record.schema_version, 1);
  assert.equal(record.receipts.length, 1);
  assert.equal(record.receipts[0].command_id, cmd.command_id);
  assert.match(record.receipts[0].intent_sha256, /^[a-f0-9]{64}$/);
  assert.notEqual(record.receipts[0].intent_sha256, prepared.intent_sha256);
  assert.equal(Object.hasOwn(record.receipts[0], 'principal_sha256'), false);
  assert.equal(prepared.capture_authorized, false);
});

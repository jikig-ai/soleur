import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createOfflineLedger } from './holder-authority-ledger-v2-offline.mjs';
import { createSyntheticConditionalStore } from './holder-authority-conditional-store.mjs';

const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32),
  manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
const input = (action, expected_state, expected_revision, id) => Object.fromEntries(Object.entries({ base,
  principal: { issuer: 'https://issuer.example', subject: 'synthetic' }, clock: { lower_ms: 90000, upper_ms: 90000 },
  command: { action, expected_state, expected_revision, command_id: id.repeat(32), operation_id: base.operation_id,
    generation: base.generation, manifest_sha256: base.manifest_sha256 } }).map(([k,v]) => [k, JSON.stringify(v)]));
async function records() {
  const ledger = createOfflineLedger(JSON.stringify(base));
  assert.equal((await ledger.submit(input('prepare', 'unprepared', 0, '1'))).state, 'persisted_unverified');
  const initial = JSON.stringify(ledger.snapshot());
  assert.equal((await ledger.submit(input('arm', 'unarmed', 0, '2'))).state, 'persisted_unverified');
  return [initial, JSON.stringify(ledger.snapshot())];
}

test('base validation refuses nonstrings and oversized UTF-8 before parsing or coercion', () => {
  let coercions = 0, parses = 0;
  const original = JSON.parse;
  JSON.parse = (...args) => { parses++; return original(...args); };
  try {
    assert.throws(() => createSyntheticConditionalStore({ toString() { coercions++; return JSON.stringify(base); } }), /fixture_base/);
    assert.throws(() => createSyntheticConditionalStore('é'.repeat(2049)), /fixture_base/);
    assert.equal(coercions, 0);
    assert.equal(parses, 0);
  } finally { JSON.parse = original; }
});

test('atomic absent create, strong read and compare-and-swap preserve exact bytes', async () => {
  const [initial, armed] = await records();
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  assert.deepEqual(await store.readStrong(), { state: 'absent' });
  assert.equal((await store.createIfAbsent(initial)).state, 'committed_unverified');
  const read = await store.readStrong();
  assert.equal(read.document, initial);
  assert.equal((await store.createIfAbsent(initial)).state, 'conflict');
  const [a, b] = await Promise.all([store.compareAndSwap(read.version, armed), store.compareAndSwap(read.version, armed)]);
  assert.deepEqual([a.state, b.state].sort(), ['committed_unverified', 'conflict']);
  const current = await store.readStrong();
  assert.equal(current.document, armed);
  assert.notEqual(current.version, read.version);
});

test('lost result stays unknown until a strong read observes the exact receipt', async () => {
  const [initial, armed] = await records();
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  store.delayNextWrite();
  assert.equal((await store.createIfAbsent(initial)).state, 'unknown');
  assert.equal((await store.readStrong()).state, 'absent');
  assert.equal(store.releaseDelayed(), true);
  const read = await store.readStrong();
  assert.equal(read.document, initial);
  store.delayNextWrite();
  assert.equal((await store.compareAndSwap(read.version, armed)).state, 'unknown');
  assert.equal((await store.readStrong()).document, initial);
  assert.equal(store.releaseDelayed(), true);
  assert.equal((await store.readStrong()).document, armed);
});

test('refuses v1, tampered receipt and changed historical bytes', async () => {
  const [initial, armed] = await records();
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  const bad = JSON.parse(initial);
  bad.schema_version = 1;
  assert.equal((await store.createIfAbsent(JSON.stringify(bad))).state, 'unknown');
  const tampered = JSON.parse(initial);
  tampered.prepare.intent_json += ' ';
  assert.equal((await store.createIfAbsent(JSON.stringify(tampered))).state, 'unknown');
  assert.equal((await store.createIfAbsent(initial)).state, 'committed_unverified');
  const read = await store.readStrong();
  const changed = JSON.parse(armed);
  changed.prepare.command_id = '9'.repeat(32);
  assert.equal((await store.compareAndSwap(read.version, JSON.stringify(changed))).state, 'unknown');
  assert.equal((await store.readStrong()).document, initial);
});

test('every read and CAS fails closed after synthetic stored-history corruption', async () => {
  const [initial, armed] = await records();
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  assert.equal((await store.createIfAbsent(initial)).state, 'committed_unverified');
  const corrupted = JSON.parse(initial);
  corrupted.schema_version = 1;
  store.loadRawFixture(JSON.stringify(corrupted));
  assert.deepEqual(await store.readStrong(), { state: 'unknown' });
  assert.equal((await store.compareAndSwap('v2', armed)).state, 'unknown');
});

test('refuses rehashed but semantically malformed v2 history', async () => {
  const [initial, armed] = await records();
  for (const mutate of [
    r => { r.asserted_late = true; },
    r => { const i = JSON.parse(r.receipts[0].intent_json); i.clock_decision = 'inside_window'; r.receipts[0].intent_json = JSON.stringify(i); },
    r => { const i = JSON.parse(r.receipts[0].intent_json); i.principal_sha256 = 'private'; r.receipts[0].intent_json = JSON.stringify(i); },
    r => { const i = JSON.parse(r.receipts[0].intent_json); i.lower_ms = 89999; r.receipts[0].intent_json = JSON.stringify(i); },
  ]) {
    const store = createSyntheticConditionalStore(JSON.stringify(base));
    assert.equal((await store.createIfAbsent(initial)).state, 'committed_unverified');
    const before = await store.readStrong();
    const candidate = JSON.parse(armed); mutate(candidate);
    const entry = candidate.receipts[0];
    entry.intent_sha256 = createHash('sha256').update(entry.intent_json).digest('hex');
    assert.equal((await store.compareAndSwap(before.version, JSON.stringify(candidate))).state, 'unknown');
    assert.equal((await store.readStrong()).document, initial);
  }
});

test('refuses a rehashed prepare with malformed base identity', async () => {
  const [initial] = await records();
  const candidate = JSON.parse(initial), intent = JSON.parse(candidate.prepare.intent_json);
  intent.operation_id = 'invalid';
  candidate.prepare.intent_json = JSON.stringify(intent);
  candidate.prepare.intent_sha256 = createHash('sha256').update(candidate.prepare.intent_json).digest('hex');
  const changedExpected = { ...base, operation_id: 'invalid' };
  assert.equal((await createSyntheticConditionalStore(JSON.stringify(changedExpected)).createIfAbsent(JSON.stringify(candidate))).state, 'unknown');
});

test('rejects a correctly linked rehashed attempt that consumes reserved slots', async () => {
  const ledger = createOfflineLedger(JSON.stringify(base));
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  const within = item => ({ ...item, clock: JSON.stringify({ lower_ms: 110000, upper_ms: 110000 }) });
  const commands = [input('prepare', 'unprepared', 0, '0'), input('arm', 'unarmed', 0, '1'),
    within(input('begin_capture', 'armed', 1, '2')), within(input('seal', 'capturing', 2, '3')),
    within(input('report_attempt', 'sealed', 3, '4')), within(input('report_attempt', 'deleting', 4, '5'))];
  for (const [index, command] of commands.entries()) {
    assert.equal((await ledger.submit(command)).state, 'persisted_unverified');
    const document = JSON.stringify(ledger.snapshot());
    const result = index === 0 ? await store.createIfAbsent(document) : await store.compareAndSwap((await store.readStrong()).version, document);
    assert.equal(result.state, 'committed_unverified');
  }
  const before = await store.readStrong();
  const candidate = JSON.parse(before.document);
  const intent = JSON.parse(candidate.receipts.at(-1).intent_json);
  intent.command_id = '6'.repeat(32); intent.expected_revision = 5; intent.target_revision = 6;
  const raw = JSON.stringify(intent);
  candidate.receipts.push({ command_id: intent.command_id, intent_json: raw,
    intent_sha256: createHash('sha256').update(raw).digest('hex') });
  candidate.revision = 6;
  assert.equal((await store.compareAndSwap(before.version, JSON.stringify(candidate))).state, 'unknown');
  assert.equal((await store.readStrong()).document, before.document);
});

test('rejects a rehashed revoke with an invented clock decision', async () => {
  const ledger = createOfflineLedger(JSON.stringify(base));
  const store = createSyntheticConditionalStore(JSON.stringify(base));
  assert.equal((await ledger.submit(input('prepare', 'unprepared', 0, '0'))).state, 'persisted_unverified');
  assert.equal((await store.createIfAbsent(JSON.stringify(ledger.snapshot()))).state, 'committed_unverified');
  assert.equal((await ledger.submit(input('arm', 'unarmed', 0, '1'))).state, 'persisted_unverified');
  assert.equal((await store.compareAndSwap((await store.readStrong()).version, JSON.stringify(ledger.snapshot()))).state, 'committed_unverified');
  const before = await store.readStrong();
  assert.equal((await ledger.submit(input('revoke', 'armed', 1, '2'))).state, 'persisted_unverified');
  const candidate = ledger.snapshot(), entry = candidate.receipts.at(-1), intent = JSON.parse(entry.intent_json);
  intent.clock_decision = 'invalid';
  entry.intent_json = JSON.stringify(intent);
  entry.intent_sha256 = createHash('sha256').update(entry.intent_json).digest('hex');
  assert.equal((await store.compareAndSwap(before.version, JSON.stringify(candidate))).state, 'unknown');
  assert.equal((await store.readStrong()).document, before.document);
});

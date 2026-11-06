import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createOfflineLedger } from './holder-authority-ledger-v2-offline.mjs';
import { prepareIntent } from './holder-authority-intent.mjs';

const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32),
  manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
const principal = { issuer: 'https://issuer.example', subject: 'synthetic' };
const clock = { lower_ms: 90000, upper_ms: 90000 };
const inside = { lower_ms: 110000, upper_ms: 110000 };
const late = { lower_ms: 200000, upper_ms: 200000 };
function input(action, state, revision, id, changes = {}) {
  const command = { action, operation_id: base.operation_id, generation: base.generation, manifest_sha256: base.manifest_sha256,
    command_id: id.repeat(32), expected_revision: revision, expected_state: state };
  return Object.fromEntries(Object.entries({ base, principal, clock, command, ...changes }).map(([k, v]) => [k, JSON.stringify(v)]));
}
const prepare = () => input('prepare', 'unprepared', 0, '0');
const arm = (id = '1') => input('arm', 'unarmed', 0, id);

test('atomic creation stores the exact shared intent and replay has no authority', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  assert.equal((await l.submit(prepare())).state, 'persisted_unverified');
  const stored = l.snapshot();
  assert.equal(stored.revision, 0);
  assert.equal(stored.prepare.intent_json, prepareIntent(prepare()).intent_json);
  assert.equal(stored.prepare.intent_sha256, prepareIntent(prepare()).intent_sha256);
  assert.equal((await l.submit(prepare())).state, 'historical_unverified');
  assert.equal((await l.submit(arm())).capture_authorized, false);
  assert.equal(l.snapshot().receipts[0].intent_json, prepareIntent(arm()).intent_json);
  assert.equal(l.snapshot().receipts[0].intent_sha256, prepareIntent(arm()).intent_sha256);
});

test('lost creation and updates remain unknown until exact receipt appears', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  l.delayNextCommit();
  assert.equal((await l.submit(prepare())).state, 'unknown');
  assert.equal(l.snapshot(), null);
  l.releaseDelayed();
  assert.equal((await l.submit(prepare())).state, 'historical_unverified');
  l.delayNextCommit();
  assert.equal((await l.submit(arm())).state, 'unknown');
  assert.equal(l.snapshot().revision, 0);
  l.releaseDelayed();
  assert.equal((await l.submit(arm())).state, 'historical_unverified');
});

test('same ID with changed canonical intent is never a replay', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  await l.submit(prepare());
  await l.submit(arm());
  for (const changes of [{ principal: { ...principal, subject: 'other' } }, { clock: { lower_ms: 90000, upper_ms: 90001 } }]) {
    assert.equal((await l.submit(input('arm', 'unarmed', 0, '1', changes))).state, 'unknown');
  }
  assert.equal((await l.submit(input('arm', 'unarmed', 0, '0'))).state, 'unknown');
  assert.equal(l.snapshot().revision, 1);
});

test('competing updates cannot both commit the same revision', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  await l.submit(prepare());
  const result = await Promise.all([l.submit(arm('1')), l.submit(arm('2'))]);
  assert.deepEqual(result.map((r) => r.state).sort(), ['persisted_unverified', 'unknown']);
  assert.equal(l.snapshot().receipts.length, 1);
});

test('delayed creation cannot replace a competing creation', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  l.delayNextCommit();
  assert.equal((await l.submit(prepare())).state, 'unknown');
  const other = input('prepare', 'unprepared', 0, '9');
  assert.equal((await l.submit(other)).state, 'persisted_unverified');
  assert.equal(l.releaseDelayed(), false);
  assert.equal((await l.submit(prepare())).state, 'unknown');
  assert.equal(l.snapshot().prepare.intent_json, prepareIntent(other).intent_json);
});

test('ordinary attempts leave three slots for revoke, cleanup and verification', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  for (const item of [prepare(), arm(), input('begin_capture', 'armed', 1, '2', { clock: inside }), input('seal', 'capturing', 2, '3', { clock: inside }),
    input('report_attempt', 'sealed', 3, '4', { clock: inside }), input('report_attempt', 'deleting', 4, '5', { clock: inside })]) {
    assert.equal((await l.submit(item)).state, 'persisted_unverified');
  }
  assert.equal((await l.submit(input('report_attempt', 'deleting', 5, '6', { clock: inside }))).state, 'unknown');
  assert.equal((await l.submit(input('revoke', 'deleting', 5, '6', { clock: inside }))).state, 'persisted_unverified');
  assert.equal((await l.submit(input('report_attempt', 'revoked', 6, '7', { clock: inside }))).state, 'persisted_unverified');
  assert.equal((await l.submit(input('report_verified', 'revoked_deleting', 7, '8', { clock: inside }))).state, 'persisted_unverified');
  assert.equal(l.snapshot().revision, 8);
  assert.equal(l.snapshot().receipts.length, 8);
  assert.equal(l.snapshot().state, 'verification_asserted_unverified');
  assert.equal(l.snapshot().asserted_late, false);
  const historical = await l.submit(arm());
  assert.equal(historical.state, 'historical_unverified');
  assert.equal(historical.capture_authorized, false);
  assert.equal(historical.cleanup_authorized, false);
  assert.equal(historical.deletion_verified, false);
  assert.equal(l.snapshot().revision, 8);
  assert.equal((await l.submit(input('arm', 'unarmed', 0, '1', { principal: { ...principal, subject: 'other' } }))).state, 'unknown');
});

test('the asserted clock cannot advance capture before start, cross a boundary or move backward', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  await l.submit(prepare()); await l.submit(arm());
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2'))).state, 'unknown');
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2', { clock: { lower_ms: 99999, upper_ms: 100000 } }))).state, 'unknown');
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2', { clock: inside }))).state, 'persisted_unverified');
  assert.equal((await l.submit(input('seal', 'capturing', 2, '3', { clock: { lower_ms: 109999, upper_ms: 110000 } }))).state, 'unknown');
  assert.equal(l.snapshot().state, 'capturing');
});

test('capture and arming refuse deadline and start boundary crossings', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  const atStart = { lower_ms: 100000, upper_ms: 100000 };
  assert.equal((await l.submit(input('prepare', 'unprepared', 0, '0', { clock: atStart }))).state, 'unknown');
  await l.submit(prepare());
  assert.equal((await l.submit(input('arm', 'unarmed', 0, '1', { clock: atStart }))).state, 'unknown');
  await l.submit(arm());
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2', { clock: late }))).state, 'unknown');
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2', { clock: { lower_ms: 199999, upper_ms: 200000 } }))).state, 'unknown');
  assert.equal((await l.submit(input('begin_capture', 'armed', 1, '2', { clock: atStart }))).state, 'persisted_unverified');
});

test('every later action rejects an asserted interval crossing the deadline', async () => {
  for (const action of ['seal', 'report_attempt', 'report_verified', 'revoke']) {
    const l = createOfflineLedger(JSON.stringify(base));
    for (const item of [prepare(), arm(), input('begin_capture', 'armed', 1, '2', { clock: inside })]) {
      assert.equal((await l.submit(item)).state, 'persisted_unverified');
    }
    if (['report_attempt', 'report_verified'].includes(action)) {
      assert.equal((await l.submit(input('seal', 'capturing', 2, '3', { clock: inside }))).state, 'persisted_unverified');
    }
    if (action === 'report_verified') {
      assert.equal((await l.submit(input('report_attempt', 'sealed', 3, '4', { clock: inside }))).state, 'persisted_unverified');
    }
    const before = l.snapshot();
    const crossing = { lower_ms: 199999, upper_ms: 200000 };
    assert.equal((await l.submit(input(action, before.state, before.revision, '9', { clock: crossing }))).state, 'unknown', action);
    assert.deepEqual(l.snapshot(), before, action);
  }
});

test('asserted verification at deadline stays unverified and is marked late', async () => {
  const l = createOfflineLedger(JSON.stringify(base));
  for (const item of [prepare(), arm(), input('begin_capture', 'armed', 1, '2', { clock: inside }),
    input('seal', 'capturing', 2, '3', { clock: inside }), input('report_attempt', 'sealed', 3, '4', { clock: inside })]) {
    const result = await l.submit(item);
    assert.equal(result.state, 'persisted_unverified');
    assert.equal(result.deletion_verified, false);
  }
  assert.equal(l.snapshot().asserted_late, false);
  const crossing = { lower_ms: 199999, upper_ms: 200000 };
  assert.equal((await l.submit(input('report_verified', 'deleting', 4, '5', { clock: crossing }))).state, 'unknown');
  assert.equal(l.snapshot().state, 'deleting');
  assert.equal(l.snapshot().asserted_late, false);
  const result = await l.submit(input('report_verified', 'deleting', 4, '5', { clock: late }));
  assert.equal(result.state, 'persisted_unverified');
  assert.equal(result.deletion_verified, false);
  assert.equal(l.snapshot().state, 'verification_asserted_unverified');
  assert.equal(l.snapshot().asserted_late, true);
});

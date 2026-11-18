import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createLedger } from './holder-retention-firestore-ledger.mjs';

const op = 'a'.repeat(32), vault = 'b'.repeat(32), owner = 'c'.repeat(32), generation = 'd'.repeat(32);
const base = { operation_id: op, vault_id: vault, owner_id: owner, generation,
  manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };

function mockFirestore() {
  let document = null, revision = 0, loseNextResponse = false, failBeforeCommit = false, delayNext = false, pending = null;
  let freezeNext = false, hideAfterWrite = false, readsHidden = false;
  const requests = [];
  const timestamp = () => `2026-10-28T00:00:0${revision}.000000Z`;
  const request = async (item) => {
    requests.push(item);
    if (item.method === 'GET') return readsHidden ? { status: 403, body: '{}' } : document ? { status: 200, body: JSON.stringify(document) } : { status: 404, body: '{}' };
    if (failBeforeCommit) { failBeforeCommit = false; throw new Error('private'); }
    const write = JSON.parse(item.body).writes[0];
    if ((write.currentDocument.exists === false && document) ||
        (write.currentDocument.updateTime && write.currentDocument.updateTime !== document?.updateTime)) return { status: 409, body: '{}' };
    if (delayNext) {
      delayNext = false;
      pending = () => { revision++; document = { ...write.update, updateTime: timestamp() }; };
      throw new Error('private');
    }
    const oldTime = document?.updateTime;
    revision++;
    const updateTime = freezeNext ? oldTime : timestamp();
    if (freezeNext && hideAfterWrite) readsHidden = true;
    freezeNext = false;
    document = { ...write.update, updateTime };
    if (loseNextResponse) { loseNextResponse = false; throw new Error('private'); }
    return { status: 200, body: JSON.stringify({ writeResults: [{ updateTime }], commitTime: timestamp() }) };
  };
  return { request, requests, lose() { loseNextResponse = true; }, failBefore() { failBeforeCommit = true; },
    delay() { delayNext = true; }, release() { pending(); pending = null; }, extra() { document.unexpected = 'private'; },
    freeze(hide = false) { freezeNext = true; hideAfterWrite = hide; },
    futureCreateTime() { document.createTime = '2026-10-28T00:00:01.000001Z'; },
    changeVault() { const record = JSON.parse(document.fields.payload.stringValue); record.vault_id = '9'.repeat(32);
      document.fields.payload.stringValue = JSON.stringify(record); } };
}

function setup(clock = { async sample() { return { lower_ms: 90000, upper_ms: 90000 }; } }) {
  const service = mockFirestore();
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base, request: service.request, clock });
  return { ledger, service };
}

test('create uses an absent-document precondition and never grants admission', async () => {
  const { ledger, service } = setup();
  const result = await ledger.create(base);
  assert.equal(result.state, 'applied');
  assert.equal(result.capture_authorized, false);
  const request = service.requests[0];
  assert.equal(request.url, `https://firestore.googleapis.com/${['v1', 'projects'].join('/')}/synthetic-project/databases/holder-ledger/documents:commit`);
  assert.deepEqual(JSON.parse(request.body).writes[0].currentDocument, { exists: false });
});

test('capture transitions remain refused until durable arming proof exists', async () => {
  let now = 90000;
  const { ledger } = setup({ async sample() { return { lower_ms: now, upper_ms: now }; } });
  assert.equal((await ledger.create(base)).state, 'applied');
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'persisted_unverified');
  now = 100000;
  const command = { operation_id: op, generation, expected_revision: 1,
    expected_state: 'armed', target_state: 'capturing', command_id: '2'.repeat(32) };
  assert.equal((await ledger.transition(command)).state, 'unknown');
  now = 200000;
  assert.equal((await ledger.transition(command)).state, 'unknown');
});

test('arming that finishes after capture start remains unknown', async () => {
  let calls = 0;
  const { ledger } = setup({ async sample() { calls++; const now = calls === 1 ? 90000 : 100001; return { lower_ms: now, upper_ms: now }; } });
  assert.equal((await ledger.create(base)).state, 'applied');
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
});

test('inverted clock intervals never acknowledge arming', async () => {
  const samples = [{ lower_ms: 90000, upper_ms: 90000 }, { lower_ms: 95000, upper_ms: 94000 }];
  const second = setup({ async sample() { return samples.shift(); } }).ledger;
  assert.equal((await second.create(base)).state, 'applied');
  assert.equal((await second.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
});

test('an uncertain arming cannot be followed by capture from a second caller', async () => {
  const samples = [90000, 100001, 110000, 110000];
  const { ledger, service } = setup({ async sample() { const now = samples.shift(); return { lower_ms: now, upper_ms: now }; } });
  assert.equal((await ledger.create(base)).state, 'applied');
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
  const requests = service.requests.length;
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 1,
    expected_state: 'armed', target_state: 'capturing', command_id: '2'.repeat(32) })).state, 'unknown');
  assert.equal(service.requests.length, requests);
});

test('invalid provider calendar timestamps cannot acknowledge a commit', async () => {
  for (const timestamp of ['2026-02-30T00:00:00.000000Z', '2026-01-01T00:00:60Z',
    '2026-01-01T00:00:00.123456789Z', '2026-01-01T00:00:00+00:00']) {
    const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
      request: async () => ({ status: 200, body: JSON.stringify({ writeResults: [{ updateTime: timestamp }],
        commitTime: timestamp }) }), clock: { async sample() { return { lower_ms: 1, upper_ms: 1 }; } } });
    assert.equal((await ledger.create(base)).state, 'unknown');
  }
});

test('unexpected commit response fields cannot acknowledge persistence', async () => {
  const time = '2026-10-28T00:00:00.000000Z';
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
    request: async () => ({ status: 200, body: JSON.stringify({ writeResults: [{ updateTime: time, extra: 'private' }], commitTime: time }) }),
    clock: { async sample() { return { lower_ms: 1, upper_ms: 1 }; } } });
  assert.equal((await ledger.create(base)).state, 'unknown');
});

test('provider commit timestamps may carry nanoseconds while update preconditions remain microsecond aligned', async () => {
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
    request: async () => ({ status: 200, body: JSON.stringify({ writeResults: [{ updateTime: '2026-10-28T00:00:00.123456Z' }],
      commitTime: '2026-10-28T00:00:00.123456789Z' }) }), clock: { async sample() { return { lower_ms: 1, upper_ms: 1 }; } } });
  assert.equal((await ledger.create(base)).state, 'applied');
});

test('a document update time after commit time cannot acknowledge persistence', async () => {
  for (const [updated, committed] of [
    ['2026-10-29T00:00:00.000000Z', '2026-10-28T00:00:00.000000000Z'],
    ['2026-10-28T00:00:00.123456000Z', '2026-10-28T00:00:00.123455999Z'],
  ]) {
    const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
      request: async () => ({ status: 200, body: JSON.stringify({ writeResults: [{ updateTime: updated }], commitTime: committed }) }),
      clock: { async sample() { return { lower_ms: 1, upper_ms: 1 }; } } });
    assert.equal((await ledger.create(base)).state, 'unknown');
  }
});

test('transition uses exact update time and reconciles a lost response with its receipt', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  service.lose();
  const result = await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) });
  assert.equal(result.state, 'persisted_unverified');
  assert.equal(result.capture_authorized, false);
  const commit = service.requests.filter((r) => r.method === 'POST').at(-1);
  assert.equal(JSON.parse(commit.body).writes[0].currentDocument.updateTime, '2026-10-28T00:00:01.000000Z');
});

test('mismatched generation, invalid metadata and ambiguous failures refuse safely', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create({ ...base, raw_response: 'private' })).state, 'unknown');
  assert.equal(service.requests.length, 0);
  assert.equal((await ledger.create(base)).state, 'applied');
  const before = service.requests.length;
  assert.equal((await ledger.transition({ operation_id: op, generation: '9'.repeat(32), expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
  assert.equal(service.requests.slice(before).filter((r) => r.method === 'POST').length, 0);
});

test('missing receipt after an ambiguous submission stays unknown and never authorizes capture', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  service.failBefore();
  const result = await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) });
  assert.deepEqual(result, { state: 'unknown', capture_authorized: false, deletion_verified: false });
  assert.equal(JSON.stringify(result).includes('private'), false);
});

test('a commit appearing after an ambiguous reread remains unknown until its exact receipt appears', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  const command = { operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) };
  service.delay();
  assert.equal((await ledger.transition(command)).state, 'unknown');
  service.release();
  assert.equal((await ledger.transition(command)).state, 'persisted_unverified');
});

test('reusing a receipt ID for a different transition cannot produce success', async () => {
  const { ledger } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'persisted_unverified');
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 1,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
});

test('competing transitions cannot both win the same revision', async () => {
  const { ledger } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  const common = { operation_id: op, generation, expected_revision: 0, expected_state: 'unarmed', target_state: 'armed' };
  const results = await Promise.all([
    ledger.transition({ ...common, command_id: '1'.repeat(32) }),
    ledger.transition({ ...common, command_id: '2'.repeat(32) }),
  ]);
  assert.deepEqual(results.map((r) => r.state).sort(), ['persisted_unverified', 'unknown']);
  assert.ok(results.every((r) => r.capture_authorized === false && r.deletion_verified === false));
});

test('a missing or malformed provider document never becomes an empty ledger', async () => {
  for (const response of [{ status: 404, body: '{}' }, { status: 403, body: '{"secret":"private"}' },
    { status: 200, body: '{"name":"wrong","fields":{},"updateTime":"2026-10-28T00:00:00Z"}' }]) {
    const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase: base,
      request: async () => response, clock: { async sample() { return { lower_ms: 1, upper_ms: 1 }; } } });
    const result = await ledger.transition({ operation_id: op, generation, expected_revision: 0,
      expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) });
    assert.deepEqual(result, { state: 'unknown', capture_authorized: false, deletion_verified: false });
  }
});

test('an unexpected provider document field prevents a conditional write', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  service.extra();
  const before = service.requests.length;
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
  assert.equal(service.requests.slice(before).filter((r) => r.method === 'POST').length, 0);
});

test('a provider record with a different bound vault cannot advance', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  service.changeVault();
  const before = service.requests.length;
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
  assert.equal(service.requests.slice(before).filter((r) => r.method === 'POST').length, 0);
});

test('the ledger snapshots its expected operation base at construction', async () => {
  const service = mockFirestore(), expectedBase = { ...base };
  const ledger = createLedger({ projectId: 'synthetic-project', databaseId: 'holder-ledger', expectedBase, request: service.request,
    clock: { async sample() { return { lower_ms: 90000, upper_ms: 90000 }; } } });
  expectedBase.vault_id = '9'.repeat(32);
  assert.equal((await ledger.create(base)).state, 'applied');
  const before = service.requests.length;
  assert.equal((await ledger.create(expectedBase)).state, 'unknown');
  assert.equal(service.requests.length, before);
});

test('a changed CAS write without an advancing update time cannot be acknowledged', async () => {
  for (const hide of [true, false]) {
    const { ledger, service } = setup();
    assert.equal((await ledger.create(base)).state, 'applied');
    service.freeze(hide);
    const result = await ledger.transition({ operation_id: op, generation, expected_revision: 0,
      expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) });
    assert.equal(result.state, 'unknown');
  }
});

test('a create time later than the update time blocks conditional writes', async () => {
  const { ledger, service } = setup();
  assert.equal((await ledger.create(base)).state, 'applied');
  service.futureCreateTime();
  const before = service.requests.length;
  assert.equal((await ledger.transition({ operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) })).state, 'unknown');
  assert.equal(service.requests.slice(before).filter((r) => r.method === 'POST').length, 0);
});

test('a backwards clock cannot upgrade an uncertain arming to readiness', async () => {
  const samples = [90000, 100001, 90000];
  const { ledger } = setup({ async sample() { const now = samples.shift(); return { lower_ms: now, upper_ms: now }; } });
  assert.equal((await ledger.create(base)).state, 'applied');
  const command = { operation_id: op, generation, expected_revision: 0,
    expected_state: 'unarmed', target_state: 'armed', command_id: '1'.repeat(32) };
  assert.equal((await ledger.transition(command)).state, 'unknown');
  const replay = await ledger.transition(command);
  assert.equal(replay.state, 'persisted_unverified');
  assert.equal(replay.capture_authorized, false);
});

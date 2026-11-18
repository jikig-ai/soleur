import { test } from 'node:test';
import assert from 'node:assert/strict';
import { simulateRetention } from './holder-evidence-retention-model.mjs';

const DAY = 24 * 60 * 60 * 1000;
function fixture() {
  const f = {
    capture_start_ms: 1000000, deadline_ms: 1000000 + DAY, now_ms: 1000100,
    capture_started: true, collector_interrupted: false,
    expected: { operation_id: 'synthetic-op', vault_id: 'synthetic-vault', owner_id: 'synthetic-owner', generation: 'gen-1' },
    observed: { operation_id: 'synthetic-op', vault_id: 'synthetic-vault', owner_id: 'synthetic-owner', generation: 'gen-1' },
    armed_at_ms: 999999, clock_verified: true, ledger_persisted: true, no_untracked_copies: true,
    collector_domain: 'collector', vault_domain: 'vault',
    workers: [{ id: 'worker-1', domain: 'worker-domain-1', registered: true, read_back: true },
      { id: 'worker-2', domain: 'worker-domain-2', registered: true, read_back: true }],
    expected_copies: ['receipt'],
    cleanup: { attempted_at_ms: 1000010, response: 'ok', sealed: true, handles_closed: true,
      copies_accounted: true, interrupted: false, delete_worker_id: 'worker-1' },
    verification: { verifier_id: 'verifier-1', domain: 'verification-domain', independent: true, ready_at_ms: 999999,
      admission_control_read_healthy: true,
      control_read_healthy: true, absence_confirmed: true, checked_copies: ['receipt'], verified_at_ms: 1000020 },
  };
  for (const [index, worker] of f.workers.entries()) Object.assign(worker, {
    identity: { ...f.expected }, job_id: `job-${index}`, scheduler: `scheduler-${index}`,
    credential: `credential-${index}`, network: `network-${index}`,
    read_back_at_ms: 999999, scheduled_at_ms: 1000010,
  });
  Object.assign(f.verification, { identity: { ...f.expected }, scheduler: 'scheduler-v',
    credential: 'credential-v', network: 'network-v', read_back_at_ms: 999999 });
  f.cleanup.identity = { ...f.expected };
  return f;
}
const state = (input) => simulateRetention(input).state;

test('only a complete simulated lifecycle returns the model verification state', () => {
  const output = simulateRetention(fixture());
  assert.equal(output.state, 'model_verified');
  assert.equal(output.scope, 'synthetic_model_only');
  assert.equal(output.independent_deletion_proven, false);
  assert.equal(JSON.stringify(output).includes('synthetic-owner'), false);
});

test('arming must be complete, independent and precede the first captured byte', () => {
  const f = fixture();
  assert.equal(state({ ...f, capture_started: false }), 'model_armed');
  assert.equal(state({ ...f, capture_started: false, ledger_persisted: false }), 'refused');
  assert.equal(state({ ...f, ledger_persisted: false }), 'unknown');
  assert.equal(state({ ...f, armed_at_ms: f.capture_start_ms + 1 }), 'unknown');
  assert.equal(state({ ...f, workers: [f.workers[0], { ...f.workers[1], domain: f.workers[0].domain }] }), 'unknown');
  assert.equal(state({ ...f, workers: [f.workers[0], { ...f.workers[1], id: f.workers[0].id }] }), 'unknown');
  assert.equal(state({ ...f, workers: [f.workers[0], { ...f.workers[1], read_back: false }] }), 'unknown');
  assert.equal(state({ ...f, clock_verified: false }), 'unknown');
  assert.equal(state({ ...f, capture_started: false, verification: { ...f.verification, admission_control_read_healthy: false } }), 'refused');
  assert.equal(state({ ...f, capture_started: false, verification: { ...f.verification, ready_at_ms: f.capture_start_ms + 1 } }), 'refused');
  assert.equal(state({ ...f, capture_started: false, verification: { ...f.verification, domain: 'worker-domain-2' } }), 'refused');
  assert.equal(state({ ...f, capture_started: false, now_ms: f.deadline_ms + 1 }), 'refused');
});

test('every ownership component must match exactly', () => {
  const f = fixture();
  for (const key of Object.keys(f.expected)) {
    assert.equal(state({ ...f, observed: { ...f.observed, [key]: 'wrong' } }), 'unknown', key);
  }
  assert.equal(JSON.stringify(simulateRetention({ ...f, observed: { ...f.observed, owner_id: 'private-secret' } })).includes('private-secret'), false);
});

test('a successful delete is not proof without independent healthy readback', () => {
  const f = fixture();
  for (const change of [{ independent: false }, { control_read_healthy: false }, { absence_confirmed: false },
    { verifier_id: 'worker-1' }, { domain: 'worker-domain-1' }, { checked_copies: [] }, { checked_copies: ['receipt', 'extra'] }]) {
    assert.equal(state({ ...f, verification: { ...f.verification, ...change } }), 'unknown');
  }
});

test('open handles, unaccounted copies and interrupted cleanup remain unknown', () => {
  const f = fixture();
  for (const change of [{ sealed: false }, { handles_closed: false }, { copies_accounted: false }, { interrupted: true }]) {
    assert.equal(state({ ...f, cleanup: { ...f.cleanup, ...change } }), 'unknown');
  }
  assert.equal(state({ ...f, no_untracked_copies: false }), 'unknown');
  assert.equal(state({ ...f, collector_interrupted: true }), 'model_verified');
});

test('lost response needs verified absence; a denied deletion never verifies', () => {
  const f = fixture();
  assert.equal(state({ ...f, cleanup: { ...f.cleanup, response: 'lost' } }), 'model_verified');
  assert.equal(state({ ...f, cleanup: { ...f.cleanup, response: 'lost' }, verification: { ...f.verification, absence_confirmed: false } }), 'unknown');
  assert.equal(state({ ...f, cleanup: { ...f.cleanup, response: 'denied' } }), 'unknown');
});

test('late verification remains late, even if deletion eventually succeeds', () => {
  const f = fixture();
  assert.equal(state({ ...f, now_ms: f.deadline_ms + 1, verification: { ...f.verification, verified_at_ms: f.deadline_ms + 1 } }), 'late');
  assert.equal(state({ ...f, now_ms: f.deadline_ms + 1 }), 'model_verified');
  assert.equal(state({ ...f, now_ms: f.deadline_ms + 1, ledger_persisted: false }), 'late');
  assert.equal(state({ ...f, now_ms: f.deadline_ms, observed: { ...f.observed, generation: 'wrong' } }), 'late');
  assert.equal(state({ ...f, deadline_ms: f.capture_start_ms + DAY + 1 }), 'unknown');
});

test('missing, malformed or future evidence never verifies', () => {
  const f = fixture();
  assert.equal(state(null), 'unknown');
  assert.equal(state({ ...f, expected_copies: [] }), 'unknown');
  assert.equal(state({ ...f, expected_copies: ['receipt', 'receipt'] }), 'unknown');
  assert.equal(state({ ...f, verification: { ...f.verification, checked_copies: ['receipt', 'receipt'] } }), 'unknown');
  assert.equal(state({ ...f, verification: { ...f.verification, verified_at_ms: f.now_ms + 1 } }), 'unknown');
  assert.equal(state({ ...f, cleanup: { ...f.cleanup, attempted_at_ms: f.verification.verified_at_ms + 1 } }), 'unknown');
  assert.equal(state({ ...f, cleanup: { ...f.cleanup, delete_worker_id: 'not-armed' } }), 'unknown');
});

test('review: operation-bound fresh evidence and independent dependencies are required', () => {
  const f = fixture();
  for (const key of Object.keys(f.expected)) {
    assert.equal(state({ ...f, cleanup: { ...f.cleanup, identity: { ...f.expected, [key]: 'wrong' } } }), 'unknown');
    assert.equal(state({ ...f, verification: { ...f.verification, identity: { ...f.expected, [key]: 'wrong' } } }), 'unknown');
    const workers = f.workers.map((w) => ({ ...w, identity: { ...w.identity } }));
    workers[0].identity[key] = 'wrong';
    assert.equal(state({ ...f, workers }), 'unknown');
  }
  for (const field of ['scheduler', 'credential', 'network']) {
    const workers = f.workers.map((w) => ({ ...w })); workers[1][field] = workers[0][field];
    assert.equal(state({ ...f, workers }), 'unknown');
    assert.equal(state({ ...f, verification: { ...f.verification, [field]: workers[0][field] } }), 'unknown');
  }
  for (const change of [{ job_id: undefined }, { read_back_at_ms: f.capture_start_ms + 1 },
    { read_back_at_ms: 0 }, { scheduled_at_ms: f.deadline_ms }]) {
    assert.equal(state({ ...f, workers: [{ ...f.workers[0], ...change }, f.workers[1]] }), 'unknown');
  }
  assert.equal(state({ ...f, now_ms: f.deadline_ms, verification: { ...f.verification, verified_at_ms: f.deadline_ms } }), 'late');
});

test('arming cannot precede either job readback or verifier readiness', () => {
  const f = fixture();
  for (const i of [0, 1]) {
    const workers = f.workers.map((worker, index) => ({ ...worker, read_back_at_ms: index === i ? 1000000 : 999999 }));
    assert.equal(state({ ...f, workers }), 'unknown');
    assert.equal(state({ ...f, workers, capture_started: false }), 'refused');
  }
  for (const field of ['read_back_at_ms', 'ready_at_ms']) {
    const verification = { ...f.verification, [field]: 1000000 };
    assert.equal(state({ ...f, verification }), 'unknown');
    assert.equal(state({ ...f, verification, capture_started: false }), 'refused');
  }
  assert.equal(state({ ...f, verification: undefined, capture_started: false }), 'refused');
});

test('a cleanup attributed to a scheduled worker cannot precede its schedule', () => {
  const f = fixture();
  const workers = f.workers.map((worker, index) => index === 0 ? { ...worker, scheduled_at_ms: 1000020 } : worker);
  assert.equal(state({ ...f, workers }), 'unknown');
});

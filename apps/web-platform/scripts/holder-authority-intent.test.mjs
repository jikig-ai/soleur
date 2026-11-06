import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prepareIntent } from './holder-authority-intent.mjs';

const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32),
  generation: 'd'.repeat(32), manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64),
  capture_start_ms: 100000, deadline_ms: 200000 };
const command = { action: 'arm', operation_id: base.operation_id, generation: base.generation,
  manifest_sha256: base.manifest_sha256, command_id: '1'.repeat(32), expected_revision: 0, expected_state: 'unarmed' };
const principal = { issuer: 'https://issuer.example', subject: 'synthetic-subject' };
const clock = { lower_ms: 90000, upper_ms: 90010 };
const input = (overrides = {}) => Object.fromEntries(Object.entries({ base, command, principal, clock, ...overrides }).map(([k, v]) => [k, JSON.stringify(v)]));
const denied = { state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false };

test('preparation binds operation, state, action, identity and clock without authorization', () => {
  const r = prepareIntent(input());
  assert.equal(r.state, 'prepared_unverified');
  assert.equal(r.capture_authorized, false);
  assert.equal(r.cleanup_authorized, false);
  assert.equal(r.deletion_verified, false);
  assert.match(r.intent_sha256, /^[a-f0-9]{64}$/);
  const intent = JSON.parse(r.intent_json);
  assert.equal(intent.action, 'arm');
  assert.equal(intent.expected_state, 'unarmed');
  assert.equal(intent.target_state, 'armed');
  assert.equal(intent.expected_revision, 0);
  assert.equal(intent.target_revision, 1);
  assert.equal(intent.clock_decision, 'before_start');
  assert.equal(prepareIntent(input()).intent_sha256, r.intent_sha256);
});

test('changes to any bound approved base, request identity, action or clock produce another digest', () => {
  const original = prepareIntent(input());
  const changed = (value) => { const result = prepareIntent(value); assert.equal(result.state, 'prepared_unverified'); return result.intent_sha256; };
  for (const [field, value] of Object.entries({ vault_id: '2'.repeat(32), owner_id: '3'.repeat(32),
    controller_sha256: '4'.repeat(64), capture_start_ms: 101000, deadline_ms: 201000 })) {
    assert.notEqual(changed(input({ base: { ...base, [field]: value } })), original.intent_sha256, field);
  }
  for (const [field, value] of Object.entries({ command_id: '5'.repeat(32) })) {
    assert.notEqual(changed(input({ command: { ...command, [field]: value } })), original.intent_sha256, field);
  }
  assert.notEqual(changed(input({ principal: { ...principal, subject: 'another' } })), original.intent_sha256);
  assert.notEqual(changed(input({ clock: { ...clock, upper_ms: 90011 } })), original.intent_sha256);
  const deleting = { ...command, action: 'report_verified', expected_state: 'deleting', expected_revision: 4 };
  assert.notEqual(changed(input({ command: deleting })), changed(input({ command: { ...deleting, expected_revision: 5 } })));
});

test('unknown commands, illegal predecessor, mismatched bindings and unsafe shapes refuse', () => {
  for (const changes of [{ action: 'other' }, { expected_state: 'capturing' }, { operation_id: '0'.repeat(32) },
    { generation: '0'.repeat(32) }, { manifest_sha256: '0'.repeat(64) }, { expected_revision: 8 },
    { command_id: 'private' }, { target_state: 'armed' }]) {
    assert.deepEqual(prepareIntent(input({ command: { ...command, ...changes } })), denied);
  }
  assert.deepEqual(prepareIntent(input({ clock: { lower_ms: 90000, upper_ms: 96000 } })), denied);
  assert.deepEqual(prepareIntent(input({ base: { ...base, deadline_ms: 100000 } })), denied);
  assert.deepEqual(prepareIntent(input({ principal: { ...principal, role: 'admin' } })), denied);
});

test('request grammar rejects duplicate keys, noncanonical encoding and oversize data', () => {
  for (const bad of ['{"action":"arm","action":"arm"}', ' {"action":"arm"}', 'x'.repeat(5000)]) {
    assert.deepEqual(prepareIntent({ ...input(), command: bad }), denied);
  }
});

test('typed action and state transitions have distinct intent and clock crossing is explicit', () => {
  const cases = [['arm', 'unarmed', 'armed', 0], ['begin_capture', 'armed', 'capturing', 1], ['seal', 'capturing', 'sealed', 2],
    ['report_attempt', 'sealed', 'deleting', 3], ['report_attempt', 'deleting', 'deleting', 4],
    ['report_verified', 'deleting', 'verification_asserted_unverified', 4], ['revoke', 'capturing', 'revoked', 2]];
  const digests = new Set();
  for (const [action, expected_state, target, expected_revision] of cases) {
    const r = prepareIntent(input({ command: { ...command, action, expected_state, expected_revision } }));
    assert.equal(r.state, 'prepared_unverified');
    assert.equal(JSON.parse(r.intent_json).target_state, target);
    digests.add(r.intent_sha256);
  }
  assert.equal(digests.size, cases.length);
  for (const [sample, decision] of [[{ lower_ms: 99999, upper_ms: 100000 }, 'uncertain'],
    [{ lower_ms: 100000, upper_ms: 100000 }, 'inside_window'],
    [{ lower_ms: 199999, upper_ms: 200000 }, 'uncertain'],
    [{ lower_ms: 200000, upper_ms: 200000 }, 'at_or_after_deadline']]) {
    assert.equal(JSON.parse(prepareIntent(input({ clock: sample })).intent_json).clock_decision, decision);
  }
});

test('predecessor revision matches the reachable state and creation starts at zero', () => {
  const states = { unprepared: [0], unarmed: [0], armed: [1], capturing: [2], sealed: [3], deleting: [4, 5] };
  const actions = { unprepared: 'prepare', unarmed: 'arm', armed: 'begin_capture', capturing: 'seal', sealed: 'report_attempt', deleting: 'report_verified' };
  for (const [state, valid] of Object.entries(states)) {
    for (let revision = 0; revision <= 7; revision++) {
      const r = prepareIntent(input({ command: { ...command, action: actions[state], expected_state: state, expected_revision: revision } }));
      assert.equal(r.state, valid.includes(revision) ? 'prepared_unverified' : 'unknown', `${state}/${revision}`);
      if (state === 'unprepared' && valid.includes(revision)) assert.equal(JSON.parse(r.intent_json).target_revision, 0);
    }
  }
});

test('ordinary attempts cannot consume the three reserved slots', () => {
  const common = { ...command, expected_state: 'deleting' };
  assert.equal(prepareIntent(input({ command: { ...common, action: 'report_attempt', expected_revision: 4 } })).state, 'prepared_unverified');
  assert.deepEqual(prepareIntent(input({ command: { ...common, action: 'report_attempt', expected_revision: 5 } })), denied);
  assert.equal(prepareIntent(input({ command: { ...common, action: 'report_verified', expected_revision: 5 } })).state, 'prepared_unverified');
  assert.equal(prepareIntent(input({ command: { ...common, action: 'revoke', expected_revision: 5 } })).state, 'prepared_unverified');
});

test('post-revocation cleanup and verification preserve the remaining slots', () => {
  const req = (action, state, revision) => prepareIntent(input({ command: { ...command, action, expected_state: state, expected_revision: revision } }));
  assert.equal(req('revoke', 'deleting', 5).state, 'prepared_unverified');
  assert.equal(req('report_attempt', 'revoked', 6).state, 'prepared_unverified');
  assert.equal(req('report_verified', 'revoked_deleting', 7).state, 'prepared_unverified');
  assert.deepEqual(req('report_attempt', 'revoked', 7), denied);
  assert.deepEqual(req('report_attempt', 'revoked_deleting', 7), denied);
});

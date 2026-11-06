import { generateKeyPairSync, sign } from 'node:crypto';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSyntheticAuthority } from './holder-authority-auth-synthetic.mjs';

const pairs = Object.fromEntries(['admin', 'collector', 'worker', 'verifier'].map((role) => [role, generateKeyPairSync('ed25519')]));
const identities = Object.entries(pairs).map(([role, pair]) => ({ issuer: 'synthetic-issuer', subject: `subject-${role}`,
  audience: 'synthetic-authority', publicKey: pair.publicKey, role }));
const claims = (role) => ({ issuer: 'synthetic-issuer', audience: 'synthetic-authority', subject: `subject-${role}`,
  issued_ms: 1000, expires_ms: 2000 });
const encoded = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const token = (payload, role, header = { alg: 'EdDSA', typ: 'JWT' }) => {
  const unsigned = `${encoded(header)}.${encoded(payload)}`;
  return `${unsigned}.${sign(null, Buffer.from(unsigned), pairs[role].privateKey).toString('base64url')}`;
};
const command = (action) => ({ action, operation_id: 'a'.repeat(32), generation: 'b'.repeat(32),
  manifest_sha256: 'c'.repeat(64), command_id: 'd'.repeat(32) });
const authority = () => createSyntheticAuthority({ identities, audience: 'synthetic-authority' });
const expected = { state: 'recognized_unverified', capture_authorized: false, cleanup_authorized: false, deletion_verified: false };
const denied = { state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false };

test('only the configured identity for each action is recognized and nothing is authorized', () => {
  const mapping = { prepare: 'admin', arm: 'admin', begin_capture: 'collector', seal: 'collector',
    report_attempt: 'worker', report_verified: 'verifier', revoke: 'admin' };
  const a = authority();
  for (const [action, role] of Object.entries(mapping)) {
    for (const candidate of Object.keys(pairs)) {
      assert.deepEqual(a.inspect({ token: token(claims(candidate), candidate), command: command(action), now_ms: 1500 }),
        candidate === role ? expected : denied, `${action}/${candidate}`);
    }
  }
});

test('wrong issuer, subject, audience, signature, key and time are rejected', () => {
  const a = authority();
  for (const changes of [{ issuer: 'other' }, { subject: 'subject-worker' }, { audience: 'other' },
    { issued_ms: 1501 }, { expires_ms: 1500 }, { issued_ms: -1 }, { issued_ms: 1000, expires_ms: 1000 },
    { expires_ms: 1000000 }, { extra: 'secret' }]) {
    assert.deepEqual(a.inspect({ token: token({ ...claims('collector'), ...changes }, 'collector'), command: command('begin_capture'), now_ms: 1500 }), denied);
  }
  assert.deepEqual(a.inspect({ token: token(claims('collector'), 'admin'), command: command('begin_capture'), now_ms: 1500 }), denied);
  assert.deepEqual(a.inspect({ token: token(claims('collector'), 'collector', { alg: 'none', typ: 'JWT' }), command: command('begin_capture'), now_ms: 1500 }), denied);
});

test('rejects command shape changes, extra claims, invalid canonical encoding and getter inputs', () => {
  const a = authority(), good = token(claims('collector'), 'collector');
  for (const bad of [{ ...command('begin_capture'), role: 'admin' }, { ...command('begin_capture'), generation: '../bad' },
    { ...command('begin_capture'), action: 'unknown' }, { ...command('begin_capture'), manifest_sha256: 'A'.repeat(64) }]) {
    assert.deepEqual(a.inspect({ token: good, command: bad, now_ms: 1500 }), denied);
  }
  const parts = good.split('.');
  assert.deepEqual(a.inspect({ token: `${parts[0]}.${parts[1]}=.${parts[2]}`, command: command('begin_capture'), now_ms: 1500 }), denied);
  const c = command('begin_capture');
  Object.defineProperty(c, 'action', { get() { throw new Error('private'); }, enumerable: true });
  assert.deepEqual(a.inspect({ token: good, command: c, now_ms: 1500 }), denied);
});

test('configuration is snapshotted and duplicate identities are rejected', () => {
  assert.throws(() => createSyntheticAuthority({ identities: [...identities, { ...identities[0], role: 'worker' }], audience: 'synthetic-authority' }));
  assert.throws(() => createSyntheticAuthority({ identities: [...identities, { ...identities[0], subject: 'other-subject', role: 'worker' }], audience: 'synthetic-authority' }));
  const input = identities.map((i) => ({ ...i }));
  const a = createSyntheticAuthority({ identities: input, audience: 'synthetic-authority' });
  input.find((i) => i.role === 'collector').role = 'admin';
  assert.deepEqual(a.inspect({ token: token(claims('collector'), 'collector'), command: command('begin_capture'), now_ms: 1500 }), expected);
});

test('signed payloads with duplicate keys, malformed UTF-8, and oversized inputs are refused', () => {
  const a = authority(), header = encoded({ alg: 'EdDSA', typ: 'JWT' });
  const rawToken = (raw) => {
    const unsigned = `${header}.${Buffer.from(raw).toString('base64url')}`;
    return `${unsigned}.${sign(null, Buffer.from(unsigned), pairs.collector.privateKey).toString('base64url')}`;
  };
  const duplicate = '{"issuer":"other","issuer":"synthetic-issuer","audience":"synthetic-authority","subject":"subject-collector","issued_ms":1000,"expires_ms":2000}';
  for (const value of [rawToken(duplicate), rawToken(Buffer.from([0xff])), 'a'.repeat(4097)]) {
    assert.deepEqual(a.inspect({ token: value, command: command('begin_capture'), now_ms: 1500 }), denied);
  }
});

test('recognition never authenticates a command or accepts asserted time as trusted', () => {
  const a = authority(), good = token(claims('collector'), 'collector');
  const result = a.inspect({ token: good, command: { ...command('begin_capture'), command_id: 'f'.repeat(32) }, now_ms: 1500 });
  assert.deepEqual(result, expected);
  assert.equal(JSON.stringify(result).includes('subject-collector'), false);
});

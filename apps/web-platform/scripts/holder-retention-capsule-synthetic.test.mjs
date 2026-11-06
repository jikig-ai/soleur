import { generateKeyPairSync, sign } from 'node:crypto';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { capsuleMessage, verifyCapsule } from './holder-retention-capsule-synthetic.mjs';

function fixture() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const capsule = { operation_id: 'synthetic-op', vault_id: 'synthetic-vault', generation: 'gen-1',
    owner_id: 'synthetic-owner', service_id: 'synthetic-service', manifest_sha256: 'a'.repeat(64),
    deadline_ms: 100000, entries: ['receipt-1', 'receipt-2'] };
  const signature = sign(null, capsuleMessage(capsule), privateKey).toString('base64');
  return { capsule, signature, publicKey, privateKey };
}

test('a valid synthetic signature never grants cleanup authority', () => {
  const { capsule, signature, publicKey } = fixture();
  assert.deepEqual(verifyCapsule(capsule, signature, publicKey), { state: 'signature_valid_only', authorizes_cleanup: false });
});

test('every operation binding and the ordered entry set is signed', () => {
  const f = fixture();
  for (const [field, value] of Object.entries({ operation_id: 'other', vault_id: 'other', generation: 'other',
    owner_id: 'other', service_id: 'other', manifest_sha256: 'b'.repeat(64), deadline_ms: 100001,
    entries: ['receipt-1', 'receipt-3'] })) {
    assert.equal(verifyCapsule({ ...f.capsule, [field]: value }, f.signature, f.publicKey).state, 'unknown', field);
  }
});

test('malformed, duplicate, unsorted and unsafe entries fail closed', () => {
  const f = fixture();
  for (const entries of [[], ['receipt-1', 'receipt-1'], ['receipt-2', 'receipt-1'], ['../private'], ['receipt/other'], ['receipt\n']]) {
    const capsule = { ...f.capsule, entries };
    const signature = sign(null, capsuleMessage(capsule), f.privateKey).toString('base64');
    assert.equal(verifyCapsule(capsule, signature, f.publicKey).state, 'unknown');
  }
  assert.equal(verifyCapsule(f.capsule, Buffer.alloc(64).toString('base64'), f.publicKey).state, 'unknown');
  assert.equal(verifyCapsule(f.capsule, f.signature, null).state, 'unknown');
});

test('unrecognized claims are refused even if a signer signs the represented fields', () => {
  const f = fixture();
  const capsule = { ...f.capsule, not_before_ms: 90000 };
  const signature = sign(null, capsuleMessage(capsule), f.privateKey).toString('base64');
  assert.equal(verifyCapsule(capsule, signature, f.publicKey).state, 'unknown');
  assert.equal(verifyCapsule(capsule, f.signature, f.publicKey).state, 'unknown');
});

test('accessor claims cannot change between validation and signature verification', () => {
  const f = fixture();
  const unsafe = { ...f.capsule, operation_id: '../bad' };
  const signature = sign(null, capsuleMessage(unsafe), f.privateKey).toString('base64');
  const capsule = { ...f.capsule };
  let calls = 0;
  Object.defineProperty(capsule, 'operation_id', { enumerable: true, get() { return calls++ === 0 ? 'safe' : '../bad'; } });
  assert.equal(verifyCapsule(capsule, signature, f.publicKey).state, 'unknown');
  const entries = ['receipt-1'];
  Object.defineProperty(entries, '0', { enumerable: true, configurable: true, get() { throw new Error('private'); } });
  assert.deepEqual(verifyCapsule({ ...f.capsule, entries }, f.signature, f.publicKey), { state: 'unknown', authorizes_cleanup: false });
});

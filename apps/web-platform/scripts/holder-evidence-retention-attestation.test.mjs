import { generateKeyPairSync, sign } from 'node:crypto';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { attestationMessage, verifyRetentionAttestations } from './holder-evidence-retention-attestation.mjs';

function fixture() {
  const contract = { operation_id: 'synthetic-op', vault_id: 'synthetic-vault', owner_id: 'synthetic-owner', generation: 'gen-1',
    manifest_sha256: 'a'.repeat(64), collector_domain: 'collector', vault_domain: 'vault',
    capture_start_ms: 100000, deadline_ms: 100000 + 24 * 60 * 60 * 1000 };
  const trust = {};
  const attestations = [];
  for (const [id, role, domain] of [['w1', 'worker', 'worker-one'], ['w2', 'worker', 'worker-two'], ['v1', 'verifier', 'verifier-one']]) {
    const { publicKey, privateKey } = generateKeyPairSync('ed25519');
    trust[id] = { role, domain, publicKey };
    const entry = { witness_id: id, role, domain, issued_at_ms: 99900, expires_at_ms: 101000,
      job_readback: true, storage_identity: true, copy_controls: true, clock_verified: true, host_loss_rehearsed: true };
    entry.signature = sign(null, attestationMessage(contract, entry), privateKey).toString('base64');
    attestations.push(entry);
  }
  return { contract, trust, attestations, now_ms: 100000 };
}

test('valid synthetic signatures never grant real admission or deletion proof', () => {
  const output = verifyRetentionAttestations(fixture());
  assert.equal(output.state, 'signatures_valid_only');
  assert.equal(output.real_admission, false);
  assert.equal(output.independent_deletion_proven, false);
  assert.equal(output.writer_clearance, false);
  assert.equal(JSON.stringify(output).includes('synthetic-op'), false);
});

test('forgery, replay, expiry and missing witnesses fail closed', () => {
  for (const alter of [
    (f) => { f.attestations[0].signature = Buffer.alloc(64).toString('base64'); },
    (f) => { f.contract.generation = 'other-generation'; },
    (f) => { f.contract.owner_id = 'other-owner'; },
    (f) => { f.now_ms = 101001; },
    (f) => { f.attestations.pop(); },
    (f) => { f.attestations[1] = f.attestations[0]; },
    (f) => { f.contract.deadline_ms++; },
  ]) {
    const f = fixture(); alter(f);
    assert.equal(verifyRetentionAttestations(f).state, 'unknown');
  }
});

test('signed attestations older than the admission freshness window are refused', () => {
  const f = fixture();
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  f.trust.w1.publicKey = publicKey;
  f.attestations[0].issued_at_ms = f.contract.capture_start_ms - 60001;
  f.attestations[0].signature = sign(null, attestationMessage(f.contract, f.attestations[0]), privateKey).toString('base64');
  assert.equal(verifyRetentionAttestations(f).state, 'unknown');
});

test('an attestation is expired at its exact expiry instant', () => {
  const f = fixture();
  f.now_ms = f.attestations[0].expires_at_ms - 1;
  assert.equal(verifyRetentionAttestations(f).state, 'signatures_valid_only');
  f.now_ms = f.attestations[0].expires_at_ms;
  assert.equal(verifyRetentionAttestations(f).state, 'unknown');
});

test('trust and independent failure-domain constraints are enforced', () => {
  for (const alter of [
    (f) => { f.trust.w2 = { ...f.trust.w2, domain: 'worker-one' }; },
    (f) => { f.trust.v1 = { ...f.trust.v1, domain: 'vault' }; },
    (f) => { f.trust.v1 = { ...f.trust.v1, publicKey: f.trust.w1.publicKey }; },
    (f) => { f.attestations[0].job_readback = false; },
    (f) => { f.contract.collector_domain = 'vault'; },
  ]) {
    const f = fixture(); alter(f);
    assert.equal(verifyRetentionAttestations(f).state, 'unknown');
  }
});

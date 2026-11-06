import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { createTimeEvidenceVerifier } from './holder-authority-time-evidence.mjs';

const keys = generateKeyPairSync('ed25519');
const operation = 'a'.repeat(32);
function fixture() {
  let mono = 100;
  const verifier = createTimeEvidenceVerifier({ issuer: 'synthetic-clock', publicKey: keys.publicKey,
    operation, maxTransitMs: 100, maxUncertaintyMs: 20, monotonicNow: () => mono });
  return { verifier, advance(n) { mono += n; }, set(n) { mono = n; } };
}
function signed(challenge, values = {}, key = keys.privateKey) {
  const sample = { domain: 'holder-time-evidence-v1', issuer: 'synthetic-clock', operation,
    nonce: challenge.nonce, lower_ms: 1000, upper_ms: 1010, ...values };
  const raw = JSON.stringify(sample);
  return { sample: raw, signature: sign(null, Buffer.from(raw), key).toString('base64') };
}
const denied = { state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false };

test('verified evidence includes bounded interval and never authorizes action', () => {
  const f = fixture(), challenge = f.verifier.begin();
  f.advance(20);
  assert.deepEqual(challenge.verify(signed(challenge), { capture_start_ms: 900, deadline_ms: 1100 }),
    { state: 'verified_evidence_only', lower_ms: 1000, upper_ms: 1030, decision: 'inside_window',
      capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
  assert.deepEqual(challenge.verify(signed(challenge), { capture_start_ms: 900, deadline_ms: 1100 }), denied);
});

test('wrong issuer, operation, nonce, signature, invalid shape or absent identity are refused', () => {
  for (const changes of [{ issuer: 'other' }, { operation: 'b'.repeat(32) }, { nonce: '0'.repeat(64) },
    { lower_ms: 2000, upper_ms: 1000 }, { extra: 'private' }]) {
    const c = fixture().verifier.begin();
    assert.deepEqual(c.verify(signed(c, changes), { capture_start_ms: 900, deadline_ms: 1100 }), denied);
  }
  const c = fixture().verifier.begin();
  assert.deepEqual(c.verify(signed(c, {}, generateKeyPairSync('ed25519').privateKey), { capture_start_ms: 900, deadline_ms: 1100 }), denied);
  assert.throws(() => createTimeEvidenceVerifier({ issuer: '', publicKey: keys.publicKey, operation, maxTransitMs: 100,
    maxUncertaintyMs: 20, monotonicNow: () => 0 }));
});

test('rejects elapsed-time rollback, stale sample and excessive signed uncertainty', () => {
  for (const values of [{ advance: 101 }, { set: 99 }, { sample: { upper_ms: 1021 } }]) {
    const f = fixture(), c = f.verifier.begin();
    if (values.advance) f.advance(values.advance);
    if (values.set) f.set(values.set);
    assert.deepEqual(c.verify(signed(c, values.sample), { capture_start_ms: 900, deadline_ms: 1100 }), denied);
  }
});

test('deadline and start boundary uncertainty never become inside-window evidence', () => {
  const f = fixture(), c = f.verifier.begin();
  f.advance(20);
  assert.equal(c.verify(signed(c), { capture_start_ms: 900, deadline_ms: 1030 }).decision, 'uncertain');
  const d = fixture().verifier.begin();
  assert.equal(d.verify(signed(d), { capture_start_ms: 1005, deadline_ms: 1100 }).decision, 'uncertain');
});

test('a newer sample cannot move definitively backward', () => {
  const f = fixture(), first = f.verifier.begin();
  assert.equal(first.verify(signed(first), { capture_start_ms: 900, deadline_ms: 1100 }).state, 'verified_evidence_only');
  const second = f.verifier.begin();
  assert.deepEqual(second.verify(signed(second, { lower_ms: 900, upper_ms: 910 }), { capture_start_ms: 900, deadline_ms: 1100 }), denied);
});

test('request and window accessors cannot change between checks', () => {
  const c = fixture().verifier.begin(), proof = signed(c);
  let reads = 0;
  Object.defineProperty(proof, 'sample', { get() { reads++; return 'private'; } });
  assert.deepEqual(c.verify(proof, { capture_start_ms: 900, deadline_ms: 1100 }), denied);
  assert.equal(reads, 0);
  const d = fixture().verifier.begin();
  const window = { capture_start_ms: 900 };
  Object.defineProperty(window, 'deadline_ms', { get() { reads++; return 1100; } });
  assert.deepEqual(d.verify(signed(d), window), denied);
  assert.equal(reads, 0);
});

test('final interval includes time spent parsing and verifying', () => {
  for (const [delay, expectedState, expectedUpper, decision] of [[30, 'verified_evidence_only', 1040, 'uncertain'],
    [101, 'unknown', undefined, undefined]]) {
    const f = fixture(), challenge = f.verifier.begin(), proof = signed(challenge);
    const parse = JSON.parse;
    let result;
    JSON.parse = (...args) => { f.advance(delay); return parse(...args); };
    try { result = challenge.verify(proof, { capture_start_ms: 900, deadline_ms: 1040 }); }
    finally { JSON.parse = parse; }
    assert.equal(result.state, expectedState);
    assert.equal(result.upper_ms, expectedUpper);
    assert.equal(result.decision, decision);
  }
});

test('begin sanitizes clock source exceptions', () => {
  const verifier = createTimeEvidenceVerifier({ issuer: 'synthetic-clock', publicKey: keys.publicKey, operation,
    maxTransitMs: 100, maxUncertaintyMs: 20, monotonicNow() { throw new Error('private-clock-error'); } });
  assert.throws(() => verifier.begin(), { message: 'time_unknown' });
});

test('begin sanitizes random-source exceptions in an isolated process', () => {
  const moduleUrl = new URL('./holder-authority-time-evidence.mjs', import.meta.url).href;
  const code = `
    import crypto from 'node:crypto';
    import { syncBuiltinESMExports } from 'node:module';
    crypto.randomBytes = () => { throw new Error('private-random-error'); };
    syncBuiltinESMExports();
    const { createTimeEvidenceVerifier } = await import(${JSON.stringify(moduleUrl)});
    const { publicKey } = crypto.generateKeyPairSync('ed25519');
    const verifier = createTimeEvidenceVerifier({ issuer: 'synthetic-clock', publicKey, operation: 'a'.repeat(32),
      maxTransitMs: 100, maxUncertaintyMs: 20, monotonicNow: () => 0 });
    try { verifier.begin(); process.exitCode = 2; }
    catch (e) { if (e.message !== 'time_unknown') process.exitCode = 3; }
  `;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8', timeout: 5000 });
  assert.equal(result.status, 0);
  assert.doesNotMatch(result.stderr, /private-random-error/);
});

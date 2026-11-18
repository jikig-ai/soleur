import { test } from 'node:test';
import assert from 'node:assert/strict';
import { X509Certificate, createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { prepareWorkerStsRequest, transmitWorkerSts } from './holder-worker-sts-builder.mjs';

const audience = '//iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/synthetic-pool/providers/synthetic-provider';
function certificate() {
  const dir = mkdtempSync(join(tmpdir(), 'sts-certificate-synthetic-'));
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes', '-days', '1',
      '-subj', '/CN=synthetic-worker', '-addext', 'basicConstraints=critical,CA:FALSE', '-keyout', join(dir, 'key.pem'),
      '-out', join(dir, 'cert.pem')], { stdio: 'ignore' });
    return new X509Certificate(readFileSync(join(dir, 'cert.pem'))).raw.toString('base64');
  } finally { rmSync(dir, { recursive: true, force: true }); }
}
function certificateChain() {
  const dir = mkdtempSync(join(tmpdir(), 'sts-chain-synthetic-'));
  const run = args => execFileSync('openssl', args, { cwd: dir, stdio: 'ignore' });
  try {
    run(['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes', '-days', '1',
      '-subj', '/CN=synthetic-ca', '-addext', 'basicConstraints=critical,CA:TRUE', '-keyout', 'ca.key', '-out', 'ca.pem']);
    run(['req', '-new', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
      '-subj', '/CN=synthetic-worker', '-keyout', 'leaf.key', '-out', 'leaf.csr']);
    writeFileSync(join(dir, 'extensions.cnf'), 'basicConstraints=critical,CA:FALSE\n');
    run(['x509', '-req', '-in', 'leaf.csr', '-CA', 'ca.pem', '-CAkey', 'ca.key', '-CAcreateserial',
      '-days', '1', '-extfile', 'extensions.cnf', '-out', 'leaf.pem']);
    return ['leaf.pem', 'ca.pem'].map(name => new X509Certificate(readFileSync(join(dir, name))).raw.toString('base64'));
  } finally { rmSync(dir, { recursive: true, force: true }); }
}
const sha = value => createHash('sha256').update(Buffer.from(value, 'base64')).digest('hex');
const encoded = value => JSON.stringify(value);
function fixture() {
  const leaf = certificate();
  const pins = { audience, binding_id: 'synthetic-binding', leaf_sha256: sha(leaf) };
  return { pins, config: { ...pins, chain_der_base64: [leaf] } };
}

test('prepares bounded leaf-first X.509 exchange for a pinned audience without granting authority', () => {
  const { config, pins } = fixture();
  const result = prepareWorkerStsRequest(encoded(config), encoded(pins));
  assert.equal(result.state, 'prepared_unverified');
  assert.equal(result.identity_verified, false);
  assert.equal(result.capture_authorized, false);
  assert.equal(result.cleanup_authorized, false);
  assert.equal(result.binding_id, 'synthetic-binding');
  assert.equal(result.request.url, 'https://sts.mtls.googleapis.com/v1/token');
  assert.equal(result.request.method, 'POST');
  assert.equal(result.request.redirect, 'error');
  const body = JSON.parse(result.request.body);
  assert.equal(body.audience, audience);
  assert.deepEqual(JSON.parse(body.subject_token), config.chain_der_base64);
  assert.equal(body.subject_token_type, 'urn:ietf:params:oauth:token-type:mtls');
});

test('pin mismatch, invalid DER and unknown fields refuse without echoing input', () => {
  const { config, pins } = fixture();
  for (const invalid of [{ ...config, audience: audience.replace('synthetic-pool', 'other-pool') },
    { ...config, binding_id: 'other' }, { ...config, leaf_sha256: '0'.repeat(64) },
    { ...config, chain_der_base64: ['cHJpdmF0ZQ=='] }, { ...config, private_field: 'private' },
    { ...config, chain_der_base64: Array(6).fill(config.chain_der_base64[0]) }]) {
    const result = prepareWorkerStsRequest(encoded(invalid), encoded(pins));
    assert.equal(result.state, 'unknown');
    assert.doesNotMatch(JSON.stringify(result), /private/);
  }
  const wrongPin = '0'.repeat(64);
  assert.equal(prepareWorkerStsRequest(encoded({ ...config, leaf_sha256: wrongPin }),
    encoded({ ...pins, leaf_sha256: wrongPin })).state, 'unknown');
  assert.equal(prepareWorkerStsRequest(encoded({ ...config, chain_der_base64: [config.chain_der_base64[0], config.chain_der_base64[0]] }),
    encoded(pins)).state, 'unknown');
});

test('accepts a linked synthetic leaf-first chain and refuses reverse order and unrelated CA', () => {
  const chain = certificateChain(), other = certificateChain();
  const pins = { audience, binding_id: 'synthetic-binding', leaf_sha256: sha(chain[0]) };
  const config = { ...pins, chain_der_base64: chain };
  assert.equal(prepareWorkerStsRequest(encoded(config), encoded(pins)).state, 'prepared_unverified');
  assert.equal(prepareWorkerStsRequest(encoded({ ...config, chain_der_base64: [...chain].reverse() }), encoded(pins)).state, 'unknown');
  assert.equal(prepareWorkerStsRequest(encoded({ ...config, chain_der_base64: [chain[0], other[1]] }), encoded(pins)).state, 'unknown');
  const tamperedLeaf = Buffer.from(chain[0], 'base64');
  tamperedLeaf[tamperedLeaf.length - 1] ^= 1;
  const tampered = tamperedLeaf.toString('base64');
  const tamperedPins = { ...pins, leaf_sha256: sha(tampered) };
  assert.equal(prepareWorkerStsRequest(encoded({ ...tamperedPins, chain_der_base64: [tampered, chain[1]] }),
    encoded(tamperedPins)).state, 'unknown');
});

test('real transmission remains refused before reading injected binding or credentials', async () => {
  const { config, pins } = fixture();
  const prepared = prepareWorkerStsRequest(encoded(config), encoded(pins));
  let touched = 0;
  const binding = { get fetch() { touched++; throw new Error('private'); } };
  assert.deepEqual(await transmitWorkerSts(binding, prepared), { state: 'unknown', identity_verified: false,
    capture_authorized: false, cleanup_authorized: false });
  assert.equal(touched, 0);
});

test('input types and UTF-8 bounds are checked without calling input coercion', () => {
  let calls = 0;
  const hostile = { toString() { calls++; return '{}'; } };
  assert.equal(prepareWorkerStsRequest(hostile, '{}').state, 'unknown');
  assert.equal(prepareWorkerStsRequest('é'.repeat(100001), '{}').state, 'unknown');
  assert.equal(calls, 0);
});

test('oversized valid JSON config and pins are refused before parsing their bytes', () => {
  const { config, pins } = fixture();
  const configJson = encoded({ ...config, binding_id: 'é'.repeat(50000) });
  const pinsJson = encoded({ ...pins, binding_id: 'é'.repeat(2048) });
  assert.ok(configJson.length < 100000 && Buffer.byteLength(configJson) > 100000);
  assert.ok(pinsJson.length < 4096 && Buffer.byteLength(pinsJson) > 4096);
  const originalParse = JSON.parse;
  const parsed = [];
  JSON.parse = (...args) => { parsed.push(args[0]); return originalParse(...args); };
  try {
    assert.equal(prepareWorkerStsRequest(configJson, encoded(pins)).state, 'unknown');
    assert.deepEqual(parsed, []);
    assert.equal(prepareWorkerStsRequest(encoded(config), pinsJson).state, 'unknown');
    assert.deepEqual(parsed, [encoded(config)]);
  } finally { JSON.parse = originalParse; }
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { createSyntheticSnapshot, verifySyntheticManifest } from './holder-evidence-manifest-synthetic.mjs';

const hash = (x) => createHash('sha256').update(x).digest('hex');
function fixture() {
  const executable = Buffer.from('synthetic executable');
  const roles = Buffer.from('synthetic roles query');
  const memberships = Buffer.from('synthetic memberships query');
  const manifest = Buffer.from(JSON.stringify({ version: 1, executable_sha256: hash(executable),
    roles_sha256: hash(roles), memberships_sha256: hash(memberships), max_rows: 25, max_bytes: 4096, timeout_ms: 1000 }));
  return { executable, roles, memberships, manifest, approvedManifestSha256: hash(manifest) };
}

test('only exact reviewed synthetic bytes match, without granting collection authority', () => {
  const f = fixture();
  assert.deepEqual(verifySyntheticManifest(f), { state: 'synthetic_match', authorizes_collection: false });
  for (const field of ['executable', 'roles', 'memberships', 'manifest']) {
    assert.deepEqual(verifySyntheticManifest({ ...f, [field]: Buffer.from('different') }),
      { state: 'unknown', authorizes_collection: false }, field);
  }
  assert.equal(verifySyntheticManifest({ ...f, approvedManifestSha256: '0'.repeat(64) }).state, 'unknown');
});

test('reviewed digest does not admit malformed or ambiguous manifest structure', () => {
  const f = fixture();
  const base = JSON.parse(f.manifest);
  for (const value of [{ ...base, extra: true }, { ...base, max_rows: 0 }, { ...base, max_bytes: 1048577 },
    { ...base, timeout_ms: 1.5 }, { ...base, version: 2 }, { ...base, roles_sha256: 'A'.repeat(64) }]) {
    const manifest = Buffer.from(JSON.stringify(value));
    assert.equal(verifySyntheticManifest({ ...f, manifest, approvedManifestSha256: hash(manifest) }).state, 'unknown');
  }
  const duplicate = Buffer.from(f.manifest.toString().replace('"version":1', '"version":1,"version":1'));
  assert.equal(verifySyntheticManifest({ ...f, manifest: duplicate, approvedManifestSha256: hash(duplicate) }).state, 'unknown');
});

test('rejects non-buffer and oversized inputs without invoking external effects', () => {
  const f = fixture();
  for (const value of ['text', new Uint8Array(2), Buffer.alloc(0), Buffer.alloc(1048577)]) {
    assert.equal(verifySyntheticManifest({ ...f, executable: value }).state, 'unknown');
  }
  assert.equal(verifySyntheticManifest({ ...f, manifest: Buffer.alloc(8193) }).state, 'unknown');
});

test('executable size limit refuses a matching digest just above the cap', () => {
  const f = fixture();
  for (const [length, expected] of [[1048576, 'synthetic_match'], [1048577, 'unknown']]) {
    const executable = Buffer.alloc(length, 0x78);
    Object.defineProperty(executable, 'length', { value: 1 });
    const manifest = Buffer.from(JSON.stringify({ ...JSON.parse(f.manifest), executable_sha256: hash(executable) }));
    const result = verifySyntheticManifest({ ...f, executable, manifest, approvedManifestSha256: hash(manifest) });
    assert.equal(result.state, expected, `actual size ${length}`);
    assert.equal(result.authorizes_collection, false);
  }
});

test('rejects foreign-realm shared backing stores in every byte input', () => {
  for (const key of ['manifest', 'executable', 'roles', 'memberships']) {
    const f = fixture();
    const shared = runInNewContext(`new SharedArrayBuffer(${f[key].length})`);
    const bytes = Buffer.from(shared);
    f[key].copy(bytes);
    assert.equal(verifySyntheticManifest({ ...f, [key]: bytes }).state, 'unknown', key);
  }
});

test('rejects a shared buffer that shadows its backing store property', () => {
  for (const key of ['manifest', 'executable', 'roles', 'memberships']) {
    const f = fixture();
    const bytes = Buffer.from(new SharedArrayBuffer(f[key].length));
    f[key].copy(bytes);
    Object.defineProperty(bytes, 'buffer', { value: new ArrayBuffer(bytes.length) });
    assert.equal(verifySyntheticManifest({ ...f, [key]: bytes }).state, 'unknown', key);
  }
});

test('copies actual views, ignoring overridden valueOf and shadowed lengths', () => {
  for (const key of ['manifest', 'executable', 'roles', 'memberships']) {
    const f = fixture();
    const fake = Buffer.from(new SharedArrayBuffer(f[key].length));
    f[key].copy(fake);
    const actual = Buffer.alloc(f[key].length, 0x78);
    actual.valueOf = () => fake;
    assert.equal(verifySyntheticManifest({ ...f, [key]: actual }).state, 'unknown', key);
    const tooLarge = Buffer.alloc(key === 'manifest' ? 8193 : 1048577, 0x78);
    Object.defineProperty(tooLarge, 'length', { value: 1 });
    assert.equal(verifySyntheticManifest({ ...f, [key]: tooLarge }).state, 'unknown', key);
  }
});

test('verified snapshot isolates bytes from input and previously returned copies', () => {
  const f = fixture();
  const expected = Object.fromEntries(['manifest', 'executable', 'roles', 'memberships'].map((key) => [key, Buffer.from(f[key])]));
  const result = createSyntheticSnapshot(f);
  assert.equal(result.state, 'synthetic_match');
  assert.equal(result.authorizes_collection, false);
  assert.deepEqual(result.limits, { max_rows: 25, max_bytes: 4096, timeout_ms: 1000 });
  assert.ok(Object.isFrozen(result.limits));
  for (const key of Object.keys(expected)) f[key].fill(0);
  const first = result.copyBytes();
  for (const key of Object.keys(expected)) {
    assert.deepEqual(first[key], expected[key], key);
    first[key].fill(1);
  }
  const second = result.copyBytes();
  for (const key of Object.keys(expected)) assert.deepEqual(second[key], expected[key], key);
});

test('a failed pin does not expose snapshot bytes', () => {
  const f = fixture();
  f.roles[0] ^= 1;
  const result = createSyntheticSnapshot(f);
  assert.deepEqual(result, { state: 'unknown', authorizes_collection: false });
  assert.equal(result.copyBytes, undefined);
});

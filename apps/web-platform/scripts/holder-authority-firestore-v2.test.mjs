import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createFirestoreV2Adapter } from './holder-authority-firestore-v2.mjs';
const base = { operation_id: 'a'.repeat(32), vault_id: 'b'.repeat(32), owner_id: 'c'.repeat(32), generation: 'd'.repeat(32), manifest_sha256: 'e'.repeat(64), controller_sha256: 'f'.repeat(64), capture_start_ms: 100000, deadline_ms: 200000 };
const principal = { issuer: 'https://synthetic.example', subject: 'synthetic' };
const clock = { lower_ms: 90000, upper_ms: 90010 };
const input = (action, state, revision, id = '1') => ({ base: JSON.stringify(base), principal: JSON.stringify(principal), clock: JSON.stringify(clock), command: JSON.stringify({ action, operation_id: base.operation_id, generation: base.generation, manifest_sha256: base.manifest_sha256, command_id: id.repeat(32), expected_revision: revision, expected_state: state }) });
function fixture() {
  let doc = null, version = 0, lose = false, delay = false, pending;
  const calls = [];
  const time = v => `2026-01-01T00:00:00.${String(v).padStart(6, '0')}Z`;
  const request = async req => {
    calls.push(req);
    if (req.method === 'GET') return doc === null ? { status: 404, body: '{}' } : { status: 200, body: JSON.stringify({ name: 'projects/demo-project/databases/(default)/documents/holder_evidence_operations/' + base.operation_id, fields: { payload: { stringValue: doc } }, updateTime: time(version) }) };
    const write = JSON.parse(req.body).writes[0];
    const apply = () => {
      if (write.currentDocument.exists === false ? doc !== null : doc === null || write.currentDocument.updateTime !== time(version)) return false;
      doc = write.update.fields.payload.stringValue; version++; return true;
    };
    if (delay) { delay = false; pending = apply; return null; }
    const ok = apply(); if (lose) { lose = false; return null; }
    return { status: ok ? 200 : 409, body: '{}' };
  };
  return { request, calls, loseNext() { lose = true; }, delayNext() { delay = true; }, release() { return pending(); }, raw(value) { doc = value; version++; }, get doc() { return doc; }, get time() { return time(version); } };
}
const adapter = f => createFirestoreV2Adapter('demo-project', '(default)', JSON.stringify(base), f.request);

test('create and CAS pin exact name, precondition and canonical receipts', async () => {
 const f = fixture(), store = adapter(f);
 assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'persisted_unverified');
 const priorTime = f.time;
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'persisted_unverified');
 const posts = f.calls.filter(c => c.method === 'POST');
 assert.deepEqual(JSON.parse(posts[0].body).writes[0].currentDocument, { exists: false });
 assert.deepEqual(JSON.parse(posts[1].body).writes[0].currentDocument, { updateTime: priorTime });
});

test('competing CAS, exact replay and changed intent', async () => {
 const f = fixture(), store = adapter(f); await store.submit(input('prepare','unprepared',0));
 const [a,b] = await Promise.all([store.submit(input('arm','unarmed',0,'2')),store.submit(input('arm','unarmed',0,'3'))]);
 assert.deepEqual([a.state,b.state].sort(), ['persisted_unverified','unknown']);
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, a.state === 'persisted_unverified' ? 'historical_unverified' : 'unknown');
 const changed = input('arm','unarmed',0,'2'); changed.clock = JSON.stringify({ lower_ms: 90001, upper_ms: 90011 });
 assert.equal((await store.submit(changed)).state, 'unknown');
});

test('delayed and lost commits require exact later retained receipt', async () => {
 const f = fixture(), store = adapter(f); f.delayNext();
 assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'unknown');
 assert.equal(f.release(), true);
 assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'historical_unverified');
 f.loseNext();
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'persisted_unverified');
});

test('an unresolved write blocks other commands until exact receipt reconciliation', async () => {
 const f = fixture(), store = adapter(f), first = input('prepare','unprepared',0);
 f.delayNext();
 assert.equal((await store.submit(first)).state, 'unknown');
 const calls = f.calls.length;
 assert.equal((await store.submit(input('prepare','unprepared',0,'2'))).state, 'unknown');
 assert.equal(f.calls.length, calls);
 const altered = input('prepare','unprepared',0);
 altered.clock = JSON.stringify({ lower_ms: 90001, upper_ms: 90011 });
 assert.equal((await store.submit(altered)).state, 'unknown');
 assert.equal(f.calls.length, calls);
 assert.equal((await store.submit(first)).state, 'unknown');
 assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
 assert.equal(f.release(), true);
 assert.equal((await store.submit(first)).state, 'historical_unverified');
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'persisted_unverified');
});

test('a stalled active request refuses concurrent submits and remains unresolved after timeout', async () => {
 const f = fixture(); let release, started;
 const waiting = new Promise(resolve => { release = resolve; });
 const entered = new Promise(resolve => { started = resolve; });
 const store = adapter({ request: async req => {
   if (req.method === 'POST') { started(); await waiting; }
   return f.request(req);
 } });
 const first = input('prepare','unprepared',0);
 const pending = store.submit(first);
 await entered;
 assert.equal((await store.submit(first)).state, 'unknown');
 assert.equal((await store.submit(input('prepare','unprepared',0,'2'))).state, 'unknown');
 assert.equal((await pending).state, 'unknown');
 assert.equal((await store.submit(input('prepare','unprepared',0,'2'))).state, 'unknown');
 release();
 await new Promise(resolve => setImmediate(resolve));
 assert.equal((await store.submit(first)).state, 'historical_unverified');
});

test('a transport callback cannot reenter submit', async () => {
 const f = fixture(); let store, reentered;
 store = adapter({ request: async req => {
   if (req.method === 'POST') reentered = await store.submit(input('prepare','unprepared',0,'2'));
   return f.request(req);
 } });
 assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'persisted_unverified');
 assert.equal(reentered.state, 'unknown');
 assert.equal(f.calls.filter(c => c.method === 'POST').length, 1);
});

test('refuses v1, truncated history and altered exact updateTime', async () => {
 const f = fixture(), store = adapter(f); await store.submit(input('prepare','unprepared',0));
 const good = JSON.parse(f.doc); f.raw(JSON.stringify({ ...good, schema_version: 1 }));
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'unknown');
 f.raw(JSON.stringify({ ...good, revision: 1, receipts: [] }));
 assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'unknown');
 const bad = { request: async req => req.method === 'GET' ? { status: 200, body: JSON.stringify({ name: 'projects/demo-project/databases/(default)/documents/holder_evidence_operations/' + base.operation_id, fields: { payload: { stringValue: JSON.stringify(good) } }, updateTime: '2026-01-01T00:00:00.123456789Z' }) } : (() => { throw Error('must not write'); })() };
 assert.equal((await adapter(bad).submit(input('arm','unarmed',0,'2'))).state, 'unknown');
});

test('refuses duplicate provider document keys and escaped aliases', async () => {
 const f = fixture(); await adapter(f).submit(input('prepare','unprepared',0));
 const doc = JSON.stringify({ name: 'projects/demo-project/databases/(default)/documents/holder_evidence_operations/' + base.operation_id,
   fields: { payload: { stringValue: f.doc } }, updateTime: f.time });
 for (const body of [doc.replace('{"name":', '{"name":"wrong","name":'),
   doc.replace('"fields":{"payload":', '"fields":{"payload":{},"payload":'),
   doc.replace('"updateTime":', '"\\u0075pdateTime":"2026-01-01T00:00:00.000001Z","updateTime":')]) {
   let posts = 0;
   const store = adapter({ request: async req => { if (req.method === 'POST') posts++; return { status: 200, body }; } });
   assert.equal((await store.submit(input('arm','unarmed',0,'2'))).state, 'unknown');
   assert.equal(posts, 0);
 }
});

test('a stalled response getter cannot start a late POST', async () => {
 let posts = 0;
 const wait = () => { const end = performance.now() + 1050; while (performance.now() < end) {} };
 const request = async req => { if (req.method === 'POST') { posts++; return null; } return { get status() { wait(); return 404; }, body: '{}' }; };
 assert.equal((await adapter({ request }).submit(input('prepare','unprepared',0))).state, 'unknown');
 assert.equal(posts, 0);
});

test('a stalled document parse cannot start a late POST', async () => {
 const f = fixture(); await adapter(f).submit(input('prepare','unprepared',0));
 f.calls.length = 0;
 const original = JSON.parse; let blocked = false;
 JSON.parse = function (text, ...rest) {
   if (typeof text === 'string' && text.startsWith('{"name":"projects/demo-project/') && !blocked) { blocked = true; const end = performance.now() + 1050; while (performance.now() < end) {} }
   return original.call(this, text, ...rest);
 };
 try {
   assert.equal((await adapter(f).submit(input('arm','unarmed',0,'2'))).state, 'unknown');
   assert.equal(blocked, true); assert.equal(f.calls.filter(c => c.method === 'POST').length, 0);
 } finally { JSON.parse = original; }
});

test('a stalled candidate validation cannot start a late POST', async () => {
 const f = fixture(), store = adapter(f); let blocked = false;
 const original = JSON.stringify;
 JSON.stringify = function (value, ...rest) {
   if (value && value.schema_version === 2 && value.state === 'unarmed' && !blocked) { blocked = true; const end = performance.now() + 1050; while (performance.now() < end) {} }
   return original.call(this, value, ...rest);
 };
 try {
   assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'unknown');
   assert.equal(blocked, true); assert.equal(f.calls.filter(c => c.method === 'POST').length, 0);
 } finally { JSON.stringify = original; }
});

test('a stalled commit encoding cannot start a late POST', async () => {
 const f = fixture(), store = adapter(f); let blocked = false;
 const original = JSON.stringify;
 JSON.stringify = function (value, ...rest) {
   if (value && Array.isArray(value.writes) && !blocked) { blocked = true; const end = performance.now() + 1050; while (performance.now() < end) {} }
   return original.call(this, value, ...rest);
 };
 try {
   assert.equal((await store.submit(input('prepare','unprepared',0))).state, 'unknown');
   assert.equal(blocked, true); assert.equal(f.calls.filter(c => c.method === 'POST').length, 0);
 } finally { JSON.stringify = original; }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReservationAdapter } from './holder-reservation-firestore.mjs';

const base = {version:'holder-reservation-v1',purpose:'reserve',operation:'a'.repeat(32),generation:'b'.repeat(32),command:'c'.repeat(32),nonce:'d'.repeat(32),epoch:'1',entry:'receipt',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200',manifest_sha256:'e'.repeat(64),controller_sha256:'f'.repeat(64),caller_sha256:'1'.repeat(64),audience_sha256:'2'.repeat(64)};
const reserve = JSON.stringify(base);
const sha = value => createHash('sha256').update(value).digest('hex');
const bind = JSON.stringify({...base,purpose:'bind',reserve_sha256:sha(reserve),receipt_device:'3',receipt_inode:'4'});
const name = `projects/demo-project/databases/(default)/documents/holder_reservations/${base.operation}_${base.generation}`;
const time = version => `2026-01-01T00:00:00.${String(version).padStart(6,'0')}Z`;

function fixture() {
  let raw = null, version = 0, delayed = null, delayNext = false;
  const calls = [];
  return {
    calls,
    async request(req) {
      calls.push(req);
      if (req.method === 'GET') return raw === null ? {status:404,body:'{}'} : {status:200,body:JSON.stringify({name,fields:{payload:{stringValue:raw}},updateTime:time(version)})};
      const write = JSON.parse(req.body).writes[0];
      const apply = () => {
        if (write.currentDocument.exists === false ? raw !== null : raw === null || write.currentDocument.updateTime !== time(version)) return false;
        raw = write.update.fields.payload.stringValue; version++; return true;
      };
      if (delayNext) { delayNext = false; delayed = apply; return null; }
      return {status:apply() ? 200 : 409,body:'{}'};
    },
    delay() { delayNext = true; },
    release() { return delayed(); },
    inject(value) { raw = value; version++; },
    get raw() { return raw; },
    get revision() { return time(version); },
  };
}
const adapter = f => createReservationAdapter('demo-project','(default)',base.operation,base.generation,f.request);

test('reserve and bind use exact conditional writes and retain exact receipts', async () => {
  const f = fixture(), a = adapter(f);
  assert.equal((await a.reserve(reserve)).state,'persisted_unverified');
  const firstVersion = f.revision;
  assert.equal((await a.bind(reserve,bind)).state,'persisted_unverified');
  const writes = f.calls.filter(x => x.method === 'POST').map(x => JSON.parse(x.body).writes[0]);
  assert.equal(writes[0].update.name,name);
  assert.deepEqual(writes[0].currentDocument,{exists:false});
  assert.deepEqual(writes[1].currentDocument,{updateTime:firstVersion});
  assert.deepEqual(JSON.parse(f.raw),{reserve,reserve_sha256:sha(reserve),bind,bind_sha256:sha(bind)});
  assert.equal((await a.reserve(reserve)).state,'historical_unverified');
  assert.equal((await a.bind(reserve,bind)).state,'historical_unverified');
});

test('changed reserve or bind and mismatched identity are rejected', async () => {
  const f = fixture(), a = adapter(f);
  assert.equal((await a.reserve(JSON.stringify({...base,operation:'0'.repeat(32)}))).state,'unknown');
  await a.reserve(reserve); await a.bind(reserve,bind);
  assert.equal((await a.reserve(JSON.stringify({...base,nonce:'0'.repeat(32)}))).state,'unknown');
  assert.equal((await a.bind(reserve,JSON.stringify({...JSON.parse(bind),receipt_inode:'5'}))).state,'unknown');
  assert.equal((await a.bind(JSON.stringify({...base,nonce:'0'.repeat(32)}),bind)).state,'unknown');
});

test('an absent read after a delayed write never proves failure', async () => {
  const f = fixture(), a = adapter(f); f.delay();
  assert.equal((await a.reserve(reserve)).state,'unknown');
  assert.equal(f.release(),true);
  assert.equal((await a.reserve(reserve)).state,'historical_unverified');
});

test('competing create and bind allow only the exact winning record', async () => {
  const f = fixture(), a = adapter(f);
  const other = JSON.stringify({...base,nonce:'0'.repeat(32)});
  const created = await Promise.all([a.reserve(reserve),a.reserve(other)]);
  assert.deepEqual(created.map(x => x.state).sort(),['persisted_unverified','unknown']);
  const winning = JSON.parse(f.raw).reserve;
  const one = JSON.stringify({...JSON.parse(winning),purpose:'bind',reserve_sha256:sha(winning),receipt_device:'3',receipt_inode:'4'});
  const two = JSON.stringify({...JSON.parse(one),receipt_inode:'5'});
  const bound = await Promise.all([a.bind(winning,one),a.bind(winning,two)]);
  assert.deepEqual(bound.map(x => x.state).sort(),['persisted_unverified','unknown']);
});

test('rejects malformed persisted history and imprecise update times', async () => {
  const f = fixture(), a = adapter(f); await a.reserve(reserve);
  const record = JSON.parse(f.raw);
  for (const invalid of ['{}',JSON.stringify({...record,reserve_sha256:'0'.repeat(64)}),JSON.stringify({...record,extra:true})]) {
    f.inject(invalid);
    assert.equal((await a.bind(reserve,bind)).state,'unknown');
  }
  let posts = 0;
  const bad = {request:async req => req.method === 'GET' ? {status:200,body:JSON.stringify({name,fields:{payload:{stringValue:JSON.stringify(record)}},updateTime:'2026-01-01T00:00:00.123456789Z'})} : (posts++, {status:409,body:'{}'})};
  assert.equal((await adapter(bad).bind(reserve,bind)).state,'unknown');
  assert.equal(posts,0);
});

test('unresolved in-flight bind blocks a competing inode until exact readback', async () => {
  const f = fixture(), a = adapter(f); await a.reserve(reserve); f.delay();
  assert.equal((await a.bind(reserve,bind)).state,'unknown');
  const other = JSON.stringify({...JSON.parse(bind),receipt_inode:'5'});
  const before = f.calls.filter(x => x.method === 'POST').length;
  assert.equal((await a.bind(reserve,other)).state,'unknown');
  assert.equal(f.calls.filter(x => x.method === 'POST').length,before);
  assert.equal((await a.bind(reserve,bind)).state,'unknown');
  assert.equal(f.calls.filter(x => x.method === 'POST').length,before);
  assert.equal(f.release(),true);
  assert.equal((await a.bind(reserve,bind)).state,'historical_unverified');
});

test('unresolved create blocks changed requests and concurrent writes', async () => {
  const f = fixture(), a = adapter(f); f.delay();
  assert.equal((await a.reserve(reserve)).state,'unknown');
  const before = f.calls.filter(x => x.method === 'POST').length;
  assert.equal((await a.reserve(JSON.stringify({...base,nonce:'0'.repeat(32)}))).state,'unknown');
  assert.equal(f.calls.filter(x => x.method === 'POST').length,before);
});

test('rejects a creation timestamp later than the exact update timestamp', async () => {
  const f = fixture(); await adapter(f).reserve(reserve);
  let posts = 0;
  const bad = {request:async req => req.method === 'GET' ? {status:200,body:JSON.stringify({name,fields:{payload:{stringValue:f.raw}},createTime:'2026-01-01T00:00:00.000002Z',updateTime:'2026-01-01T00:00:00.000001Z'})} : (posts++, {status:409,body:'{}'})};
  assert.equal((await adapter(bad).bind(reserve,bind)).state,'unknown');
  assert.equal(posts,0);
});

test('throwing and stalled response accessors cannot start a late commit', async () => {
  let writes = 0;
  for (const response of [
    {get status() { throw Error('sensitive'); }},
    {get status() { const end = performance.now() + 1020; while (performance.now() < end) {} return 404; },body:'{}'},
  ]) {
    const a = adapter({request:async req => { if (req.method === 'POST') writes++; return response; }});
    assert.equal((await a.reserve(reserve)).state,'unknown');
  }
  assert.equal(writes,0);
});

test('duplicate provider document keys, including escaped aliases, refuse without a write', async () => {
  const f = fixture(); await adapter(f).reserve(reserve);
  const doc = JSON.stringify({name,fields:{payload:{stringValue:f.raw}},updateTime:'2026-01-01T00:00:00.000001Z'});
  const duplicate = [doc.replace('{"name":','{"name":"wrong","name":'),
    doc.replace('"fields":{"payload":','"fields":{"payload":{},"payload":'),
    doc.replace('"updateTime":','"\\u0075pdateTime":"2026-01-01T00:00:00.000001Z","updateTime":')];
  for (const body of duplicate) {
    let posts = 0;
    const a = adapter({request:async req => { if (req.method === 'POST') posts++; return {status:200,body}; }});
    assert.equal((await a.bind(reserve,bind)).state,'unknown');
    assert.equal(posts,0);
  }
});

test('a timed-out POST leaves a latch that blocks conflicting retries', async () => {
  const f = fixture(); let posts = 0;
  const a = adapter({request:async req => {
    if (req.method === 'POST') { posts++; return new Promise(() => {}); }
    return f.request(req);
  }});
  assert.equal((await a.reserve(reserve)).state,'unknown');
  assert.equal((await a.reserve(JSON.stringify({...base,nonce:'0'.repeat(32)}))).state,'unknown');
  assert.equal(posts,1);
});

test('provider field order and whitespace do not change document validation', async () => {
  const f = fixture(); await adapter(f).reserve(reserve);
  const a = adapter({request:async req => {
    if (req.method !== 'GET') return {status:409,body:'{}'};
    return {status:200,body:JSON.stringify({updateTime:'2026-01-01T00:00:00.000001Z',fields:{payload:{stringValue:f.raw}},name},null,2)};
  }});
  assert.equal((await a.reserve(reserve)).state,'historical_unverified');
});

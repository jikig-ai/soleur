import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createGuardCommitBuilder } from './holder-reservation-guard-commit.mjs';

const base = {version:'holder-reservation-v1',purpose:'reserve',operation:'a'.repeat(32),generation:'b'.repeat(32),command:'c'.repeat(32),nonce:'d'.repeat(32),epoch:'1',entry:'receipt',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200',manifest_sha256:'e'.repeat(64),controller_sha256:'f'.repeat(64),caller_sha256:'1'.repeat(64),audience_sha256:'2'.repeat(64)};
const reserve = JSON.stringify(base);
const sha = value => createHash('sha256').update(value).digest('hex');
const bind = JSON.stringify({...base,purpose:'bind',reserve_sha256:sha(reserve),receipt_device:'3',receipt_inode:'4'});
const prior = JSON.stringify({reserve,reserve_sha256:sha(reserve),bind:null,bind_sha256:null});
const time = '2026-01-01T00:00:00.123456Z';
const attempt = '3'.repeat(32), barrier = '4'.repeat(32);
const make = purpose => createGuardCommitBuilder('demo-project','(default)',base.operation,base.generation,purpose);
const write = body => JSON.parse(body).writes;

test('ready bootstrap, claim and terminal fence pin one guard and exact revision', () => {
  const b = make('reserve');
  const init = b.initialize();
  assert.equal(init.state,'prepared_unverified');
  assert.deepEqual(write(init.body)[0].currentDocument,{exists:false});
  const claim = b.claim(init.guard,time,attempt,reserve);
  assert.equal(claim.state,'prepared_unverified');
  assert.deepEqual(write(claim.body)[0].currentDocument,{updateTime:time});
  const fence = b.fence(init.guard,time,barrier);
  assert.equal(fence.state,'prepared_unverified');
  assert.deepEqual(write(fence.body)[0].currentDocument,{updateTime:time});
  assert.notEqual(fence.guard,init.guard);
  assert.equal(b.claim(fence.guard,time,attempt,reserve).state,'unknown');
});

test('reservation effect atomically updates exact pending guard and creates reserved record', () => {
  const b = make('reserve'), ready = b.initialize().guard;
  const pending = b.claim(ready,time,attempt,reserve).guard;
  const effect = b.effect(pending,time);
  assert.equal(effect.state,'prepared_unverified');
  const writes = write(effect.body);
  assert.equal(writes.length,2);
  assert.deepEqual(writes[0].currentDocument,{updateTime:time});
  assert.deepEqual(writes[1].currentDocument,{exists:false});
  assert.notEqual(writes[0].update.name,writes[1].update.name);
  assert.equal(JSON.parse(writes[1].update.fields.payload.stringValue).reserve,reserve);
  assert.equal(b.effect(effect.guard,time).state,'unknown');
});

test('bind effect encodes caller-asserted reserve and reservation update time', () => {
  const b = make('bind'), ready = b.initialize().guard;
  const pending = b.claim(ready,time,attempt,bind,prior,time).guard;
  const effect = b.effect(pending,time), writes = write(effect.body);
  assert.equal(effect.state,'prepared_unverified');
  assert.deepEqual(writes[1].currentDocument,{updateTime:time});
  assert.equal(JSON.parse(writes[1].update.fields.payload.stringValue).bind,bind);
  const other = JSON.stringify({...JSON.parse(prior),reserve_sha256:'0'.repeat(64)});
  assert.equal(b.claim(ready,time,attempt,bind,other,time).state,'unknown');
});

test('builder output does not prove caller payload belongs to supplied revision', () => {
  const b = make('reserve'), ready = b.initialize().guard;
  const fenced = b.fence(ready,time,barrier).guard;
  assert.notEqual(fenced,ready);
  // A revision alone does not bind these supplied bytes to an observed record.
  // An authority-owned authenticated read must reject this substitution.
  assert.equal(b.claim(ready,time,attempt,reserve).state,'prepared_unverified');
});

test('malformed identity, altered history, timestamp and state never prepare a commit', () => {
  const b = make('reserve'), ready = b.initialize().guard;
  for (const invalid of ['not-time','2026-01-01T00:00:00.123456789Z','2026-02-30T00:00:00Z']) {
    assert.equal(b.claim(ready,invalid,attempt,reserve).state,'unknown');
    assert.equal(b.fence(ready,invalid,barrier).state,'unknown');
  }
  assert.equal(b.claim(ready,time,attempt,JSON.stringify({...base,operation:'0'.repeat(32)})).state,'unknown');
  assert.equal(b.claim(ready,time,attempt,reserve,'extra',time).state,'unknown');
  assert.equal(b.fence(ready,time,'bad').state,'unknown');
  assert.equal(b.effect(ready,time).state,'unknown');
  assert.equal(b.fence(ready+' ',time,barrier).state,'unknown');
});

test('atomic CAS fixture gives exactly one winner in both claim/fence and effect/fence orders', () => {
  function database() {
    const records = new Map(); let tick = 0;
    return {
      read(name) { return records.get(name); },
      commit(body) {
        const writes = write(body);
        if (!writes.every(({update,currentDocument}) => currentDocument.exists === false ? !records.has(update.name) : records.get(update.name)?.time === currentDocument.updateTime)) return false;
        const version = `2026-01-01T00:00:00.${String(++tick).padStart(6,'0')}Z`;
        for (const {update} of writes) records.set(update.name,{time:version,payload:update.fields.payload.stringValue});
        return true;
      },
    };
  }
  const b = make('reserve');
  for (const claimFirst of [false,true]) {
    const db = database(), init = b.initialize(), guardName = write(init.body)[0].update.name;
    assert.equal(db.commit(init.body),true);
    const observed = db.read(guardName);
    const claim = b.claim(observed.payload,observed.time,attempt,reserve);
    const fence = b.fence(observed.payload,observed.time,barrier);
    assert.equal(db.commit((claimFirst ? claim : fence).body),true);
    assert.equal(db.commit((claimFirst ? fence : claim).body),false);
    if (!claimFirst) continue;
    const pending = db.read(guardName);
    const effect = b.effect(pending.payload,pending.time);
    const stop = b.fence(pending.payload,pending.time,barrier);
    for (const effectFirst of [false,true]) {
      const replay = database();
      replay.commit(init.body); replay.commit(claim.body);
      assert.equal(replay.commit((effectFirst ? effect : stop).body),true);
      assert.equal(replay.commit((effectFirst ? stop : effect).body),false);
    }
  }
});

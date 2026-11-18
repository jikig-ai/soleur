import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createGuardAuthority } from './holder-reservation-guard-authority.mjs';
import { createGuardCommitBuilder } from './holder-reservation-guard-commit.mjs';

const operation='a'.repeat(32), generation='b'.repeat(32), attempt='c'.repeat(32), barrier='d'.repeat(32);
const request=JSON.stringify({version:'holder-reservation-v1',purpose:'reserve',operation,generation,command:'1'.repeat(32),nonce:'2'.repeat(32),epoch:'1',entry:'receipt',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200',manifest_sha256:'e'.repeat(64),controller_sha256:'f'.repeat(64),caller_sha256:'1'.repeat(64),audience_sha256:'2'.repeat(64)});
const hash=x=>createHash('sha256').update(x).digest('hex');
const binding=JSON.stringify({...JSON.parse(request),purpose:'bind',reserve_sha256:hash(request),receipt_device:'5',receipt_inode:'6'});
const root='projects/demo-project/databases/(default)/documents';
const guardName=`${root}/holder_reservation_guards/${operation}_${generation}_reserve`;
const builder=createGuardCommitBuilder('demo-project','(default)',operation,generation,'reserve');

function database() {
  const docs=new Map(), calls=[]; let tick=0, delayed=null, delayNext=false, hangNext=false, loseNext=false, applyHangNext=false, releaseResponse=null;
  return {
    calls,
    async request(req) {
      calls.push(req);
      if (req.method === 'GET') {
        const name=req.url.slice('https://firestore.googleapis.com/v1/'.length), doc=docs.get(name);
        return doc ? {status:200,body:JSON.stringify({name,fields:{payload:{stringValue:doc.payload}},updateTime:doc.time})} : {status:404,body:'{}'};
      }
      const writes=JSON.parse(req.body).writes;
      const apply=() => {
        if (!writes.every(w => w.currentDocument.exists === false ? !docs.has(w.update.name) : docs.get(w.update.name)?.time === w.currentDocument.updateTime)) return false;
        const time=`2026-01-01T00:00:00.${String(++tick).padStart(6,'0')}Z`;
        for (const w of writes) docs.set(w.update.name,{payload:w.update.fields.payload.stringValue,time});
        return true;
      };
      if (delayNext) { delayNext=false; delayed=apply; return null; }
      if (hangNext) { hangNext=false; delayed=apply; return new Promise(resolve=>{releaseResponse=resolve;}); }
      if (applyHangNext) { applyHangNext=false; apply(); return new Promise(()=>{}); }
      if (loseNext) { loseNext=false; apply(); return null; }
      return {status:apply()?200:409,body:'{}'};
    },
    delay() { delayNext=true; }, hang() { hangNext=true; }, lose() { loseNext=true; }, applyHang() { applyHangNext=true; },
    release() { const applied=delayed(); if (releaseResponse) {releaseResponse({status:applied?200:409,body:'{}'}); releaseResponse=null;} return applied; },
    overwrite(name,payload) { docs.set(name,{payload,time:`2026-01-01T00:00:00.${String(++tick).padStart(6,'0')}Z`}); },
    read(name) { return docs.get(name); },
  };
}
const authority=(db,purpose='reserve') => createGuardAuthority('demo-project','(default)',operation,generation,purpose,db.request);

test('bootstrap, internally observed claim and atomic effect preserve the guard', async () => {
  const db=database(), a=authority(db);
  assert.equal((await a.bootstrap()).state,'ready_unverified');
  assert.equal((await a.claim(request,attempt)).state,'pending_unverified');
  assert.equal((await a.commit()).state,'committed_unverified');
  assert.equal(JSON.parse(db.read(guardName).payload).state,'committed');
});

test('a restarted authority cannot fabricate ready bytes for a fenced revision', async () => {
  const db=database(), first=authority(db); await first.bootstrap();
  const recover=authority(db);
  assert.equal((await recover.recover(barrier)).state,'fenced_unverified');
  const posts=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await recover.claim(request,attempt,builder.initialize().guard,db.read(guardName).time)).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,posts);
  assert.equal((await first.claim(request,attempt)).state,'unknown');
  assert.equal(JSON.parse(db.read(guardName).payload).state,'fenced');
});

test('a delayed claim cannot commit after a recovery fence wins', async () => {
  const db=database(), first=authority(db); await first.bootstrap(); db.delay();
  assert.equal((await first.claim(request,attempt)).state,'unknown');
  assert.equal((await authority(db).recover(barrier)).state,'fenced_unverified');
  assert.equal(db.release(),false);
  assert.equal(JSON.parse(db.read(guardName).payload).state,'fenced');
});

test('a delayed effect cannot commit after recovery fences its pending revision', async () => {
  const db=database(), first=authority(db); await first.bootstrap(); await first.claim(request,attempt); db.delay();
  assert.equal((await first.commit()).state,'unknown');
  assert.equal((await authority(db).recover(barrier)).state,'fenced_unverified');
  assert.equal(db.release(),false);
  assert.equal(db.read(`${root}/holder_reservations/${operation}_${generation}`),undefined);
});

test('lost bootstrap reply never grants claim, even when ready is later visible', async () => {
  const db=database(), first=authority(db); db.delay();
  assert.equal((await first.bootstrap()).state,'unknown');
  assert.equal(db.release(),true);
  assert.equal((await first.claim(request,attempt)).state,'unknown');
  assert.equal((await authority(db).recover(barrier)).state,'fenced_unverified');
});

test('bind fetches the real predecessor internally and pins its revision', async () => {
  const db=database(), reserveAuthority=authority(db);
  await reserveAuthority.bootstrap(); await reserveAuthority.claim(request,attempt); await reserveAuthority.commit();
  const bindingAuthority=authority(db,'bind');
  assert.equal((await bindingAuthority.bootstrap()).state,'ready_unverified');
  const before=db.calls.filter(x=>x.method==='POST').length;
  const guardBefore=db.read(`${root}/holder_reservation_guards/${operation}_${generation}_bind`).payload;
  assert.equal((await bindingAuthority.claim(binding,attempt,'fabricated prior','2026-01-01T00:00:00Z')).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  assert.equal(db.read(`${root}/holder_reservation_guards/${operation}_${generation}_bind`).payload,guardBefore);
  assert.equal((await bindingAuthority.claim(binding,attempt)).state,'pending_unverified');
  assert.equal((await bindingAuthority.commit()).state,'committed_unverified');
  assert.equal(JSON.parse(db.read(`${root}/holder_reservations/${operation}_${generation}`).payload).bind,binding);
});

test('successful response without an actual READY document grants no claim', async () => {
  const calls=[];
  const db={request:async req => {calls.push(req); return req.method==='POST' ? {status:200,body:'{}'} : {status:404,body:'{}'};}};
  const a=authority(db);
  assert.equal((await a.bootstrap()).state,'unknown');
  const posts=calls.filter(x=>x.method==='POST').length;
  assert.equal((await a.claim(request,attempt)).state,'unknown');
  assert.equal(calls.filter(x=>x.method==='POST').length,posts);
});

test('a competing bootstrap cannot claim an already existing guard', async () => {
  const db=database(), a=authority(db), b=authority(db);
  const responses=await Promise.all([a.bootstrap(),b.bootstrap()]);
  assert.deepEqual(responses.map(x=>x.state).sort(),['ready_unverified','unknown']);
  const loser=responses[0].state==='unknown'?a:b;
  const before=db.calls.filter(x=>x.method==='POST').length;
  const guardBefore=db.read(guardName).payload;
  assert.equal((await loser.claim(request,attempt)).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  assert.equal(db.read(guardName).payload,guardBefore);
});

test('an actually timed-out effect remains fenced against a later completion', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt); db.hang();
  assert.equal((await a.commit()).state,'unknown');
  assert.equal((await authority(db).recover(barrier)).state,'fenced_unverified');
  const before=db.calls.length;
  assert.equal(db.release(),false);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(db.calls.length,before);
  assert.equal(db.read(`${root}/holder_reservations/${operation}_${generation}`),undefined);
});

test('changed bind predecessor aborts both writes in the atomic effect', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt); await a.commit();
  const b=authority(db,'bind'); await b.bootstrap(); await b.claim(binding,attempt);
  const name=`${root}/holder_reservations/${operation}_${generation}`;
  const changed=JSON.stringify({...JSON.parse(db.read(name).payload),bind:'changed'});
  db.overwrite(name,changed);
  assert.equal((await b.commit()).state,'unknown');
  assert.equal(db.read(name).payload,changed);
  assert.equal(JSON.parse(db.read(`${root}/holder_reservation_guards/${operation}_${generation}_bind`).payload).state,'pending');
});

test('recovery cannot fence a committed effect and two recoverers cannot both win', async () => {
  const firstDb=database(), a=authority(firstDb); await a.bootstrap(); await a.claim(request,attempt); await a.commit();
  assert.equal((await authority(firstDb).recover(barrier)).state,'unknown');
  assert.equal(JSON.parse(firstDb.read(guardName).payload).state,'committed');
  const secondDb=database(); await authority(secondDb).bootstrap();
  const results=await Promise.all([authority(secondDb).recover(barrier),authority(secondDb).recover('9'.repeat(32))]);
  assert.deepEqual(results.map(x=>x.state).sort(),['fenced_unverified','unknown']);
});

test('a GET timeout cannot start a late claim POST', async () => {
  let release, posts=0;
  const ownDb=database();
  let delayedRead=false;
  const own={request:async req => {
    if (delayedRead && req.method==='GET') return new Promise(resolve=>{release=()=>resolve(ownDb.request(req));});
    if (delayedRead && req.method==='POST') posts++;
    return ownDb.request(req);
  }};
  const ownAuthority=authority(own); await ownAuthority.bootstrap(); delayedRead=true;
  assert.equal((await ownAuthority.claim(request,attempt)).state,'unknown');
  release(); await new Promise(resolve=>setImmediate(resolve));
  assert.equal(posts,0);
});

test('a substituted valid pending guard never reaches the effect POST', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt);
  const other=JSON.stringify({...JSON.parse(request),nonce:'7'.repeat(32)});
  const replacement=builder.claim(builder.initialize().guard,'2026-01-01T00:00:00.000001Z',attempt,other).guard;
  db.overwrite(guardName,replacement);
  const before=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await a.commit()).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  assert.equal(db.read(guardName).payload,replacement);
});

test('a fence readback with an unchanged revision stays unknown', async () => {
  const db=database(); await authority(db).bootstrap();
  const original=db.read(guardName).time; let afterWrite=false;
  const transport={request:async req => {
    const value=await db.request(req);
    if (req.method==='POST') afterWrite=true;
    if (afterWrite && req.method==='GET' && value.status===200) {
      const body=JSON.parse(value.body); body.updateTime=original;
      return {status:200,body:JSON.stringify(body)};
    }
    return value;
  }};
  assert.equal((await authority(transport).recover(barrier)).state,'unknown');
});

test('a delayed fence loses to an effect that commits first', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt); db.delay();
  assert.equal((await authority(db).recover(barrier)).state,'unknown');
  assert.equal((await a.commit()).state,'committed_unverified');
  assert.equal(db.release(),false);
  assert.equal(JSON.parse(db.read(guardName).payload).state,'committed');
});

test('a lost fence response is resolved only by exact terminal readback', async () => {
  const db=database(); await authority(db).bootstrap(); db.lose();
  assert.equal((await authority(db).recover(barrier)).state,'fenced_unverified');
  assert.equal(JSON.parse(db.read(guardName).payload).barrier,barrier);
});

test('a delayed bootstrap cannot replace the winning instance guard', async () => {
  const db=database(), first=authority(db), second=authority(db); db.delay();
  assert.equal((await first.bootstrap()).state,'unknown');
  assert.equal((await second.bootstrap()).state,'ready_unverified');
  assert.equal(db.release(),false);
  const before=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await first.claim(request,attempt)).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  assert.equal((await second.claim(request,attempt)).state,'pending_unverified');
});

test('a restarted authority reconciles only exact committed guard and reservation', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt);
  db.lose();
  assert.equal((await a.commit()).state,'committed_unverified');
  const restarted=authority(db), before=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await restarted.reconcile(request,attempt)).state,'reconciled_unverified');
  assert.equal((await restarted.reconcile(request,'0'.repeat(32))).state,'unknown');
  assert.equal((await restarted.reconcile(JSON.stringify({...JSON.parse(request),nonce:'9'.repeat(32)}),attempt)).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  const reservation=`${root}/holder_reservations/${operation}_${generation}`;
  db.overwrite(reservation,'{}');
  assert.equal((await restarted.reconcile(request,attempt)).state,'unknown');
});

test('reconciliation refuses pending or fenced guards without issuing writes', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt);
  const restarted=authority(db), before=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await restarted.reconcile(request,attempt)).state,'unknown');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
  await restarted.recover(barrier);
  assert.equal((await restarted.reconcile(request,attempt)).state,'unknown');
});

test('restart reconciles an effect that committed before its response timed out', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt);
  db.applyHang();
  assert.equal((await a.commit()).state,'unknown');
  const before=db.calls.filter(x=>x.method==='POST').length;
  assert.equal((await authority(db).reconcile(request,attempt)).state,'reconciled_unverified');
  assert.equal(db.calls.filter(x=>x.method==='POST').length,before);
});

test('reconciliation rejects guard/reservation revision mismatch', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt); await a.commit();
  const reservation=`${root}/holder_reservations/${operation}_${generation}`;
  const actual=db.read(reservation).payload;
  for (const spoofedTime of ['2026-01-01T00:00:00.000001Z','2026-01-01T00:00:00.999999Z']) {
    const wrapper={request:async req => {
      const result=await db.request(req);
      if (req.method==='GET' && req.url.endsWith(`/${operation}_${generation}`) && result.status===200) {
        const doc=JSON.parse(result.body); doc.updateTime=spoofedTime;
        return {status:200,body:JSON.stringify(doc)};
      }
      return result;
    }};
    assert.equal((await authority(wrapper).reconcile(request,attempt)).state,'unknown');
    assert.equal(db.read(reservation).payload,actual);
  }
});

test('reserve reconciliation after a later bind remains unknown', async () => {
  const db=database(), a=authority(db); await a.bootstrap(); await a.claim(request,attempt); await a.commit();
  const b=authority(db,'bind'); await b.bootstrap(); await b.claim(binding,attempt); await b.commit();
  assert.equal((await authority(db).reconcile(request,attempt)).state,'unknown');
  assert.equal((await authority(db,'bind').reconcile(binding,attempt)).state,'reconciled_unverified');
});

test('matching injected documents and times remain unverified rather than authorization', async () => {
  const ready=builder.initialize().guard;
  const pending=builder.claim(ready,'2026-01-01T00:00:00.000001Z',attempt,request).guard;
  const effect=builder.effect(pending,'2026-01-01T00:00:00.000002Z');
  const writes=JSON.parse(effect.body).writes;
  const fake={request:async req => {
    const name=req.url.slice('https://firestore.googleapis.com/v1/'.length);
    const entry=writes.find(w=>w.update.name===name);
    return {status:200,body:JSON.stringify({name,fields:entry.update.fields,updateTime:'2026-01-01T00:00:00.000003Z'})};
  }};
  assert.deepEqual(await authority(fake).reconcile(request,attempt),{state:'reconciled_unverified',capture_authorized:false,cleanup_authorized:false,deletion_verified:false});
});

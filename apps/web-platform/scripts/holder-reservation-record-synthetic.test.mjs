import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReservationFixture } from './holder-reservation-record-synthetic.mjs';

const base = {version:'holder-reservation-v1',purpose:'reserve',operation:'a'.repeat(32),generation:'b'.repeat(32),command:'c'.repeat(32),nonce:'d'.repeat(32),epoch:'1',entry:'receipt',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200',manifest_sha256:'e'.repeat(64),controller_sha256:'f'.repeat(64),caller_sha256:'1'.repeat(64),audience_sha256:'2'.repeat(64)};
const reserve = JSON.stringify(base);
const sha = value => createHash('sha256').update(value).digest('hex');
const bind = JSON.stringify({...base,purpose:'bind',reserve_sha256:sha(reserve),receipt_device:'3',receipt_inode:'4'});
const fixture = () => createReservationFixture(base.operation, base.generation);

test('conditional reserve and bind preserve exact receipts and reject replay changes', async () => {
  const store = fixture();
  assert.equal((await store.bind('v0', bind)).state, 'unknown');
  assert.equal((await store.reserve(reserve)).state, 'committed_unverified');
  assert.equal((await store.reserve(reserve)).state, 'historical_unverified');
  assert.equal((await store.reserve(JSON.stringify({...base,nonce:'0'.repeat(32)}))).state, 'unknown');
  assert.equal((await store.bind('v0', bind)).state, 'unknown');
  assert.equal((await store.bind('v1', bind)).state, 'committed_unverified');
  assert.equal((await store.bind('v2', bind)).state, 'historical_unverified');
  assert.equal((await store.bind('v2', JSON.stringify({...JSON.parse(bind),receipt_inode:'5'}))).state, 'unknown');
  assert.equal((await store.bind('v2', JSON.stringify({...JSON.parse(bind),receipt_device:'5'}))).state, 'unknown');
  assert.deepEqual(await store.read(), {state:'found_unverified',version:'v2',reserve,reserve_sha256:sha(reserve),bind,bind_sha256:sha(bind)});
});

test('competing creates and binds have only one winner', async () => {
  const store = fixture();
  const other = JSON.stringify({...base,nonce:'0'.repeat(32)});
  const creates = await Promise.all([store.reserve(reserve),store.reserve(other)]);
  assert.deepEqual(creates.map(x => x.state), ['committed_unverified','unknown']);
  const otherBind = JSON.stringify({...JSON.parse(bind),receipt_inode:'5'});
  const binds = await Promise.all([store.bind('v1',bind),store.bind('v1',otherBind)]);
  assert.deepEqual(binds.map(x => x.state), ['committed_unverified','unknown']);
});

test('ambiguous delayed write remains unknown after an absent read', async () => {
  const store = fixture();
  store.delayNext();
  assert.equal((await store.reserve(reserve)).state, 'unknown');
  assert.equal((await store.read()).state, 'unknown');
  assert.equal((await store.observeRemote()).state, 'absent_unverified');
  assert.equal((await store.reserve(reserve)).state, 'unknown');
  store.releaseDelayed();
  assert.equal((await store.read()).state, 'found_unverified');
});

test('untrusted inputs and corrupted stored digests fail closed', async () => {
  const store = fixture();
  const hostile = {toJSON() { throw Error('must not run'); }};
  for (const value of [1n, hostile, 'x'.repeat(5000)]) assert.equal((await store.reserve(value)).state, 'unknown');
  await store.reserve(reserve);
  for (const value of [1n, hostile, 'x'.repeat(5000)]) assert.equal((await store.bind('v1', value)).state, 'unknown');
  store.loadRawFixture(JSON.stringify({reserve,reserve_sha256:'0'.repeat(64),bind:null,bind_sha256:null}));
  assert.equal((await store.read()).state, 'unknown');
});

test('delayed create keeps its absent precondition against a competing actor', async () => {
  const store = fixture();
  store.delayNext();
  assert.equal((await store.reserve(reserve)).state, 'unknown');
  const other = JSON.stringify({...base,nonce:'0'.repeat(32)});
  assert.equal(store.externalCreate(other).state, 'committed_unverified');
  assert.equal(store.releaseDelayed().state, 'conflict_unverified');
  assert.equal((await store.read()).reserve, other);
});

test('delayed bind retains its version precondition against a competing bind', async () => {
  const store = fixture();
  await store.reserve(reserve);
  store.delayNext();
  assert.equal((await store.bind('v1',bind)).state, 'unknown');
  assert.equal((await store.read()).state, 'unknown');
  const other = JSON.stringify({...JSON.parse(bind),receipt_inode:'5'});
  assert.equal(store.externalBind('v1',other).state, 'committed_unverified');
  assert.equal(store.releaseDelayed().state, 'conflict_unverified');
  assert.equal((await store.read()).bind, other);
  const second = fixture();
  await second.reserve(reserve);
  second.delayNext();
  assert.equal((await second.bind('v1',bind)).state, 'unknown');
  assert.equal(second.releaseDelayed().state, 'committed_unverified');
  assert.equal((await second.read()).bind, bind);
});

test('malformed records and wrong pinned identities are unknown', async () => {
  const store = fixture();
  assert.equal((await store.reserve(JSON.stringify({...base,operation:'0'.repeat(32)}))).state, 'unknown');
  for (const value of ['{}', '{', JSON.stringify({reserve,bind,extra:true})]) {
    store.loadRawFixture(value);
    assert.equal((await store.read()).state, 'unknown');
  }
});

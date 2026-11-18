import test from 'node:test';
import assert from 'node:assert/strict';
import { createDrainFixture } from './holder-drain-synthetic.mjs';

const operation = 'a'.repeat(32), generation = 'b'.repeat(32), barrier = 'c'.repeat(32);
const fresh = () => createDrainFixture({operation, generation, epoch:'1'});

test('barrier closes admission and waits for mutation, sync and handles', () => {
  const f = fresh();
  assert.equal(f.admit('one').state, 'admitted_unverified');
  assert.equal(f.beginBarrier(barrier).state, 'pending_unverified');
  assert.equal(f.admit('two').state, 'unknown');
  assert.equal(f.confirmSeal(barrier).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  assert.equal(f.complete('one', {synced:true, handlesClosed:false}).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  assert.equal(f.closeHandles('one').state, 'completed_unverified');
  assert.equal(f.confirmSeal(barrier).state, 'pending_unverified');
  assert.deepEqual(f.acknowledge(barrier), {state:'drained_unverified', operation, generation, epoch:'1', barrier});
  assert.deepEqual(f.acknowledge(barrier), {state:'drained_unverified', operation, generation, epoch:'1', barrier});
  assert.equal(f.admit('three').state, 'unknown');
});

test('no acknowledgment without exact confirmed seal or for conflicting barrier', () => {
  const f = fresh();
  f.beginBarrier(barrier);
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  assert.equal(f.confirmSeal('d'.repeat(32)).state, 'unknown');
  assert.equal(f.beginBarrier('d'.repeat(32)).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  f.confirmSeal(barrier);
  assert.equal(f.acknowledge('d'.repeat(32)).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'drained_unverified');
});

test('failed or ambiguous mutation permanently prevents drained', () => {
  for (const result of [{synced:false,handlesClosed:true}, {synced:true,handlesClosed:'yes'}, null]) {
    const f = fresh();
    f.admit('one'); f.beginBarrier(barrier); f.confirmSeal(barrier);
    assert.equal(f.complete('one', result).state, 'unknown');
    assert.equal(f.confirmSeal(barrier).state, 'unknown');
    assert.equal(f.acknowledge(barrier).state, 'unknown');
    assert.equal(f.complete('one', {synced:true,handlesClosed:true}).state, 'unknown');
    assert.equal(f.acknowledge(barrier).state, 'unknown');
  }
});

test('restart begins closed and does not infer a drain from persisted state', () => {
  const f = fresh();
  f.admit('one'); f.beginBarrier(barrier); f.confirmSeal(barrier);
  f.restart();
  assert.equal(f.admit('two').state, 'unknown');
  assert.equal(f.complete('one', {synced:true,handlesClosed:true}).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
});

test('duplicate mutation IDs and unrelated completion cannot discharge active work', () => {
  const f = fresh();
  f.admit('one');
  assert.equal(f.admit('one').state, 'unknown');
  f.beginBarrier(barrier); f.confirmSeal(barrier);
  assert.equal(f.complete('other', {synced:true,handlesClosed:true}).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
});

test('one mutation holds the modeled exclusive gate until it finishes', () => {
  const f = fresh();
  f.admit('one');
  assert.equal(f.admit('two').state, 'unknown');
  f.beginBarrier(barrier);
  assert.equal(f.confirmSeal(barrier).state, 'unknown');
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  f.complete('one', {synced:true,handlesClosed:true});
  assert.equal(f.confirmSeal(barrier).state, 'pending_unverified');
  assert.equal(f.acknowledge(barrier).state, 'drained_unverified');
});

test('restart refuses even after a prior acknowledgment', () => {
  const f = fresh();
  f.beginBarrier(barrier); f.confirmSeal(barrier);
  assert.equal(f.acknowledge(barrier).state, 'drained_unverified');
  f.restart();
  assert.equal(f.acknowledge(barrier).state, 'unknown');
  assert.equal(f.beginBarrier(barrier).state, 'unknown');
});

test('accessors, hidden fields and throwing proxies make outcome uncertain', () => {
  let reads = 0;
  const values = [
    {synced:true, get handlesClosed() { return ++reads > 1; }},
    {synced:true, get handlesClosed() { throw Error('unexpected'); }},
    new Proxy({}, {ownKeys() { throw Error('unexpected'); }}),
    Object.defineProperty({synced:true,handlesClosed:true}, 'extra', {value:1}),
    {synced:true,handlesClosed:true,[Symbol('extra')]:1},
  ];
  for (const value of values) {
    const f = fresh(); f.admit('one'); f.beginBarrier(barrier); f.confirmSeal(barrier);
    assert.equal(f.complete('one', value).state, 'unknown');
    assert.equal(f.acknowledge(barrier).state, 'unknown');
  }
  assert.equal(reads, 0);
});

test('reentrant proxy cannot drain while completion is being inspected', () => {
  const f = fresh();
  f.admit('one');
  const observed = [];
  const result = new Proxy({synced:true,handlesClosed:true}, {
    ownKeys(target) {
      observed.push(f.complete('one', {synced:true,handlesClosed:true}).state);
      observed.push(f.beginBarrier(barrier).state);
      observed.push(f.confirmSeal(barrier).state);
      observed.push(f.acknowledge(barrier).state);
      observed.push(f.restart().state);
      return Reflect.ownKeys(target);
    },
  });
  f.complete('one', result);
  assert.deepEqual(observed, Array(5).fill('unknown'));
});

test('a later mutation may enter before the barrier and also blocks sealing', () => {
  const f = fresh();
  f.admit('one'); f.complete('one', {synced:true,handlesClosed:true});
  assert.equal(f.admit('two').state, 'admitted_unverified');
  f.beginBarrier(barrier);
  assert.equal(f.confirmSeal(barrier).state, 'unknown');
  f.complete('two', {synced:true,handlesClosed:true});
  f.confirmSeal(barrier);
  assert.equal(f.acknowledge(barrier).state, 'drained_unverified');
});

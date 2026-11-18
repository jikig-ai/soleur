import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { validateReservation } from './holder-reservation-contract.mjs';

const base = {version:'holder-reservation-v1', purpose:'reserve', operation:'a'.repeat(32), generation:'b'.repeat(32), command:'c'.repeat(32), nonce:'d'.repeat(32), epoch:'18446744073709551615', entry:'receipt', vault_device:'9007199254740993', vault_inode:'18446744073709551615', start_ms:'100', deadline_ms:'200', manifest_sha256:'e'.repeat(64), controller_sha256:'f'.repeat(64), caller_sha256:'1'.repeat(64), audience_sha256:'2'.repeat(64)};
const encode = value => JSON.stringify(value);
const hash = value => createHash('sha256').update(value).digest('hex');
const py = value => execFileSync('python3', ['apps/web-platform/scripts/holder-reservation-contract.py'], {input: value, encoding:'utf8'}).trim();
// Frozen wire vectors: changes require a new encoding version and review.
const reserveVector = '{"version":"holder-reservation-v1","purpose":"reserve","operation":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","command":"cccccccccccccccccccccccccccccccc","nonce":"dddddddddddddddddddddddddddddddd","epoch":"18446744073709551615","entry":"receipt","vault_device":"9007199254740993","vault_inode":"18446744073709551615","start_ms":"100","deadline_ms":"200","manifest_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","controller_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","caller_sha256":"1111111111111111111111111111111111111111111111111111111111111111","audience_sha256":"2222222222222222222222222222222222222222222222222222222222222222"}';
const bindVector = '{"version":"holder-reservation-v1","purpose":"bind","operation":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","command":"cccccccccccccccccccccccccccccccc","nonce":"dddddddddddddddddddddddddddddddd","epoch":"18446744073709551615","entry":"receipt","vault_device":"9007199254740993","vault_inode":"18446744073709551615","start_ms":"100","deadline_ms":"200","manifest_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","controller_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","caller_sha256":"1111111111111111111111111111111111111111111111111111111111111111","audience_sha256":"2222222222222222222222222222222222222222222222222222222222222222","reserve_sha256":"9345cbeb4843da0bf7cb8933e334fe51ad1c7e232842eb4924c5438acca188dd","receipt_device":"9007199254740993","receipt_inode":"18446744073709551615"}';
test('reserve and bind vectors match Python bytes and digests', () => {
  const reserve = encode(base);
  assert.equal(reserve, reserveVector);
  assert.equal(hash(reserve), '9345cbeb4843da0bf7cb8933e334fe51ad1c7e232842eb4924c5438acca188dd');
  assert.deepEqual(validateReservation(reserve), {state:'prepared_unverified', sha256:hash(reserve)});
  assert.equal(py(reserve), hash(reserve));
  const bind = encode({...base, purpose:'bind', reserve_sha256:hash(reserve), receipt_device:'9007199254740993', receipt_inode:'18446744073709551615'});
  assert.equal(bind, bindVector);
  assert.equal(hash(bind), 'e81b5af819189fcf80414fb934be1ac871cd3e299d8ba1a038923872f3b5ac4a');
  assert.deepEqual(validateReservation(bind, reserve), {state:'prepared_unverified', sha256:hash(bind)});
  assert.equal(py(JSON.stringify([bind,reserve])), hash(bind));
});
test('reject noncanonical, overflow, changed reservation, and malformed fields', () => {
  const reserve = encode(base);
  assert.equal(validateReservation(reserve, null).state, 'unknown');
  assert.equal(py(JSON.stringify([reserve, null])), 'unknown');
  const bind = {...base, purpose:'bind', reserve_sha256:hash(reserve), receipt_device:'1', receipt_inode:'2'};
  const invalid = [reserve+' ', encode({...base,epoch:'01'}), encode({...base,epoch:'18446744073709551616'}), encode({...base,vault_inode:9007199254740992}), encode({...base,deadline_ms:'86500101'}), encode({...base,unexpected:'x'}), encode({...base,entry:'../receipt'}), encode({...base,purpose:'bind'})];
  for (const input of invalid) { assert.equal(validateReservation(input).state,'unknown'); assert.equal(py(input),'unknown'); }
  for (const [field, value] of Object.entries({operation:'0'.repeat(32), generation:'0'.repeat(32), command:'0'.repeat(32), nonce:'0'.repeat(32), epoch:'2', vault_device:'1', vault_inode:'2', start_ms:'101', deadline_ms:'199', manifest_sha256:'0'.repeat(64), controller_sha256:'0'.repeat(64), caller_sha256:'0'.repeat(64), audience_sha256:'0'.repeat(64), reserve_sha256:'0'.repeat(64)})) {
    const changed = encode({...bind, [field]:value});
    assert.equal(validateReservation(changed,reserve).state,'unknown', field);
    assert.equal(py(JSON.stringify([changed,reserve])),'unknown', field);
  }
});

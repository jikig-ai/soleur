import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createPublicKey, generateKeyPairSync, sign } from 'node:crypto';
import { proofMessage, verifyReservationProof } from './holder-reservation-proof.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const request = JSON.stringify({version:'holder-reservation-v1', purpose:'reserve', operation:'a'.repeat(32), generation:'b'.repeat(32), command:'c'.repeat(32), nonce:'d'.repeat(32), epoch:'1', entry:'receipt', vault_device:'2', vault_inode:'3', start_ms:'100', deadline_ms:'200', manifest_sha256:'e'.repeat(64), controller_sha256:'f'.repeat(64), caller_sha256:'1'.repeat(64), audience_sha256:'2'.repeat(64)});
const attempt = '3'.repeat(32), challenge = '4'.repeat(64), tokenHash = '5'.repeat(64);
const keypair = generateKeyPairSync('ed25519');
const publicPem = keypair.publicKey.export({type:'spki', format:'pem'}).toString();
const signature = sign(null, proofMessage(request, undefined, attempt, challenge, tokenHash, publicPem), keypair.privateKey).toString('base64');
const check = (r=request, a=attempt, c=challenge, t=tokenHash, key=publicPem, sig=signature) =>
  verifyReservationProof(r, undefined, a, c, t, key, sig);

test('only validates a signature over the exact request and context, never authority or replay', () => {
  for (let i=0;i<2;i++) assert.deepEqual(check(), {state:'signature_valid_only',capture_authorized:false,cleanup_authorized:false,deletion_verified:false});
  const changed = JSON.parse(request); changed.operation = '0'.repeat(32);
  for (const result of [check(JSON.stringify(changed)), check(request,'6'.repeat(32)), check(request,attempt,'6'.repeat(64)),
    check(request,attempt,challenge,'6'.repeat(64)), check(request,attempt,challenge,tokenHash,generateKeyPairSync('ed25519').publicKey.export({type:'spki',format:'pem'}).toString()),
    check(request,attempt,challenge,tokenHash,publicPem,signature.slice(0,-2)+'AA'), check(request+' ')]) {
    assert.equal(result.state,'unknown');
    assert.equal(result.capture_authorized,false);
  }
});

test('bind proof requires exact preceding reserve and rejects noncanonical keys and signatures', () => {
  const bind = JSON.stringify({...JSON.parse(request),purpose:'bind',reserve_sha256:hash(request),receipt_device:'4',receipt_inode:'5'});
  const signed = sign(null,proofMessage(bind,request,attempt,challenge,tokenHash,publicPem),keypair.privateKey).toString('base64');
  assert.equal(verifyReservationProof(bind,request,attempt,challenge,tokenHash,publicPem,signed).state,'signature_valid_only');
  assert.equal(verifyReservationProof(bind,request+' ',attempt,challenge,tokenHash,publicPem,signed).state,'unknown');
  assert.equal(verifyReservationProof(request,request,attempt,challenge,tokenHash,publicPem,signature).state,'unknown');
  assert.equal(verifyReservationProof(bind,request,attempt,challenge,tokenHash,publicPem,signature).state,'unknown');
  const altered = JSON.parse(bind); altered.receipt_inode = '6';
  assert.equal(verifyReservationProof(JSON.stringify(altered),request,attempt,challenge,tokenHash,publicPem,signed).state,'unknown');
  for (const key of [keypair.privateKey.export({type:'pkcs8',format:'pem'}).toString(), '', publicPem+'x']) assert.equal(check(request,attempt,challenge,tokenHash,key).state,'unknown');
  for (const sig of [signature+'\n', '', 'a'.repeat(88)]) assert.equal(check(request,attempt,challenge,tokenHash,publicPem,sig).state,'unknown');
});

test('message matches the independently computed fixed version-one vector', () => {
  const der = Buffer.from('302a300506032b6570032100d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a','hex');
  const key = createPublicKey({key:der,type:'spki',format:'der'}).export({type:'spki',format:'pem'}).toString();
  const expected = '["holder-reservation-request-proof-v1","reserve","a78b0753d4ed0f714944b8852eccf2e6360d6d86336d00494009d60e88b9b061","33333333333333333333333333333333","4444444444444444444444444444444444444444444444444444444444444444","5555555555555555555555555555555555555555555555555555555555555555","06e3fd8fda29bb60ab59557de61edb0aecdb231134be30e75b455f8e1b792fa9"]';
  assert.equal(proofMessage(request,undefined,attempt,challenge,tokenHash,key).toString(), expected);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { generateKeyPair,exportJWK,SignJWT } from 'jose';
import { createReservationIdentityBoundary } from './holder-reservation-identity-boundary.mjs';

const subject='123456789012345678901', audience='https://synthetic.invalid/authority';
const scope={audience,vault_subject:subject,operation:'a'.repeat(32),generation:'b'.repeat(32),manifest_sha256:'e'.repeat(64),controller_sha256:'f'.repeat(64),epoch:'1',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200'};
const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const base={version:'holder-reservation-v1',purpose:'reserve',operation:scope.operation,generation:scope.generation,command:'c'.repeat(32),nonce:'d'.repeat(32),epoch:'1',entry:'receipt',vault_device:'1',vault_inode:'2',start_ms:'100',deadline_ms:'200',manifest_sha256:scope.manifest_sha256,controller_sha256:scope.controller_sha256,caller_sha256:digest(['holder-reservation-caller-v1','https://accounts.google.com',subject]),audience_sha256:digest(['holder-reservation-audience-v1',audience])};
const key=await generateKeyPair('RS256',{extractable:true,modulusLength:2048});
const jwks=JSON.stringify({keys:[{...(await exportJWK(key.publicKey)),kid:'synthetic',alg:'RS256',use:'sig'}]});
const now=Math.floor(Date.now()/1000);
const token=async ({sub=subject,aud=audience,exp=now+60}={})=>new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'synthetic'}).setIssuer('https://accounts.google.com').setAudience(aud).setSubject(sub).setIssuedAt(now).setExpirationTime(exp).sign(key.privateKey);
test('caller and audience digests match the frozen cross-runtime vectors', () => {
  assert.equal(digest(['holder-reservation-caller-v1','https://accounts.google.com',subject]),'ba1e0c0da0c66440c777a211da590ae00cc60b4a8ec271dfec1d55ac207e4b67');
  assert.equal(digest(['holder-reservation-audience-v1',audience]),'81f0d9c57f9980a78a86813208641ed6868515052f9e43a13542eb51e8810dd8');
});
test('synthetic signature and exact scope produce only non-authorizing preparation', async () => {
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks);
  const result=await boundary.submit(await token(),JSON.stringify(base),'3'.repeat(32));
  assert.deepEqual(result,{state:'identity_bound_unverified',capture_authorized:false,cleanup_authorized:false,deletion_verified:false,identity:'signature_verified_untrusted_keys',request_sha256:createHash('sha256').update(JSON.stringify(base)).digest('hex'),attempt:'3'.repeat(32)});
});

test('wrong caller, audience, expiry or scoped request refuses before guard calls', async () => {
  for (const [t,raw] of [[await token({sub:'999'}),JSON.stringify(base)],[await token({aud:'https://other.invalid/'}),JSON.stringify(base)],[await token({exp:now-1}),JSON.stringify(base)],
    [await token(),JSON.stringify({...base,caller_sha256:'0'.repeat(64)})],[await token(),JSON.stringify({...base,audience_sha256:'0'.repeat(64)})],
    [await token(),JSON.stringify({...base,operation:'0'.repeat(32)})],[await token(),JSON.stringify({...base,manifest_sha256:'0'.repeat(64)})]]) {
    const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks);
    assert.equal((await boundary.submit(t,raw,'3'.repeat(32))).state,'unknown');
  }
});

test('untrusted injected callback is never invoked', async () => {
  let called=0;
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks,{bootstrap(){called++;}});
  assert.equal((await boundary.submit(await token(),JSON.stringify(base),'3'.repeat(32))).state,'unknown');
  assert.equal(called,0);
});

test('an attacker-controlled JWKS can sign the pinned subject and still yields only untrusted evidence', async () => {
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks);
  const result=await boundary.submit(await token(),JSON.stringify(base),'3'.repeat(32));
  assert.equal(result.identity,'signature_verified_untrusted_keys');
  assert.equal(result.capture_authorized,false);
});

test('bind requires the exact reservation and all approved scope values', async () => {
  const raw=JSON.stringify(base);
  const bound=JSON.stringify({...base,purpose:'bind',reserve_sha256:createHash('sha256').update(raw).digest('hex'),receipt_device:'5',receipt_inode:'6'});
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks);
  const result=await boundary.submit(await token(),bound,'3'.repeat(32),raw);
  assert.equal(result.state,'identity_bound_unverified');
  assert.equal(result.request_sha256,createHash('sha256').update(bound).digest('hex'));
  assert.equal((await boundary.submit(await token(),bound,'3'.repeat(32))).state,'unknown');
  for (const key of ['generation','controller_sha256','epoch','vault_device','vault_inode','start_ms','deadline_ms']) {
    const changed=JSON.stringify({...base,[key]:key.endsWith('sha256')?'0'.repeat(64):key==='generation'?'0'.repeat(32):'9'});
    assert.equal((await boundary.submit(await token(),changed,'3'.repeat(32))).state,'unknown',key);
  }
});

test('the unverified result retains exact request digest and attempt identity', async () => {
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks), t=await token();
  const first=await boundary.submit(t,JSON.stringify(base),'3'.repeat(32));
  const nonceChanged=await boundary.submit(t,JSON.stringify({...base,nonce:'8'.repeat(32)}),'3'.repeat(32));
  const attemptChanged=await boundary.submit(t,JSON.stringify(base),'4'.repeat(32));
  assert.notEqual(first.request_sha256,nonceChanged.request_sha256);
  assert.equal(first.attempt,nonceChanged.attempt);
  assert.equal(first.request_sha256,attemptChanged.request_sha256);
  assert.notEqual(first.attempt,attemptChanged.attempt);
  assert.equal(attemptChanged.identity,'signature_verified_untrusted_keys');
});

test('wrong key, malformed tokens and noncanonical configuration are refused', async () => {
  const attacker=await generateKeyPair('RS256',{modulusLength:2048});
  const forged=await new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'synthetic'}).setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).setIssuedAt(now).setExpirationTime(now+60).sign(attacker.privateKey);
  const boundary=createReservationIdentityBoundary(JSON.stringify(scope),jwks);
  for (const value of [forged,'x'.repeat(20000),null]) assert.equal((await boundary.submit(value,JSON.stringify(base),'3'.repeat(32))).state,'unknown');
  const duplicate=JSON.stringify(scope).replace('{"audience":','{"audience":"https://wrong.invalid/","audience":');
  assert.equal((await createReservationIdentityBoundary(duplicate,jwks).submit(await token(),JSON.stringify(base),'3'.repeat(32))).state,'unknown');
  assert.equal((await boundary.submit(await token(),'x'.repeat(100000),'3'.repeat(32))).state,'unknown');
});

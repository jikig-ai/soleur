import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { createGoogleIdVerifier } from './holder-google-id-verifier.mjs';

const subject = '123456789012345678901';
const audience = 'https://synthetic.invalid/authority';
const config = JSON.stringify({ audience, subjects: [{ subject, role: 'collector' }] });
const now = Math.floor(Date.now() / 1000);
const { privateKey, publicKey } = await generateKeyPair('RS256', { extractable: true, modulusLength: 2048 });
const jwk = { ...(await exportJWK(publicKey)), kid: 'synthetic-key', alg: 'RS256', use: 'sig' };
const jwks = JSON.stringify({ keys: [jwk] });
async function token(payload = {}, header = {}) {
  return new SignJWT({ ...payload }).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key', ...header })
    .setIssuer(payload.iss ?? 'https://accounts.google.com').setAudience(payload.aud ?? audience)
    .setSubject(payload.sub ?? subject).setIssuedAt(payload.iat ?? now).setExpirationTime(payload.exp ?? now + 60).sign(privateKey);
}
const unknown = { state: 'unknown', capture_authorized: false, cleanup_authorized: false };

test('verifies a signed token while mapping role solely from pinned subject', async () => {
  const verifier = createGoogleIdVerifier(config, jwks);
  const output = await verifier.verify(await token({ role: 'cleaner', command: 'delete' }));
  assert.deepEqual(output, { state: 'signature_verified_untrusted_keys', subject, role: 'collector', capture_authorized: false, cleanup_authorized: false });
});

test('refuses invalid issuer, audience, subject, expiration, signature and absent trusted inputs', async () => {
  const verify = createGoogleIdVerifier(config, jwks).verify;
  for (const payload of [{ iss: 'https://evil.invalid' }, { aud: 'https://evil.invalid' }, { aud: [audience, 'other'] }, { sub: '999' }, { exp: now - 1 }])
    assert.deepEqual(await verify(await token(payload)), unknown);
  const other = await generateKeyPair('RS256');
  const forged = await new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' }).setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).setExpirationTime(now + 60).sign(other.privateKey);
  assert.deepEqual(await verify(forged), unknown);
  assert.deepEqual(await createGoogleIdVerifier().verify(await token()), unknown);
  assert.deepEqual(await verify('x'.repeat(20000)), unknown);
});

test('refuses non-RS256, missing expiry, invalid pins and nonpublic key material', async () => {
  const verify = createGoogleIdVerifier(config, jwks).verify;
  const noExpiry = await new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' }).setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).sign(privateKey);
  assert.deepEqual(await verify(noExpiry), unknown);
  const hs = await new SignJWT({ iss: 'https://accounts.google.com', aud: audience, sub: subject, exp: now + 60 }).setProtectedHeader({ alg: 'HS256', kid: 'synthetic-key' }).sign(new TextEncoder().encode('secret'));
  assert.deepEqual(await verify(hs), unknown);
  assert.deepEqual(await createGoogleIdVerifier(config, JSON.stringify({ keys: [{ ...jwk, d: 'private' }] })).verify(await token()), unknown);
  assert.deepEqual(await createGoogleIdVerifier(JSON.stringify({ audience, subjects: [{ subject, role: 'collector' }, { subject, role: 'cleaner' }] }), jwks).verify(await token()), unknown);
});

test('signed token time policy rejects missing, future, stale and long-lived claims at boundaries', async () => {
  const verify = createGoogleIdVerifier(config, jwks).verify;
  const RealDate = Date;
  const seconds = Math.floor(RealDate.now() / 1000);
  globalThis.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [seconds * 1000])); }
    static now() { return seconds * 1000; }
  };
  try {
    const sign = async claims => new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'synthetic-key' })
      .setIssuer('https://accounts.google.com').setAudience(audience).setSubject(subject).sign(privateKey);
    const check = async (claims, expected) => assert.equal((await verify(await sign(claims))).state, expected, JSON.stringify(claims));
    const pass = 'signature_verified_untrusted_keys';
    await check({ exp: seconds + 10 }, 'unknown');
    await check({ iat: seconds + 1, exp: seconds + 60 }, 'unknown');
    await check({ iat: seconds - 0.5, exp: seconds + 60 }, 'unknown');
    await check({ iat: seconds, exp: seconds + 3601 }, 'unknown');
    await check({ iat: seconds, exp: seconds + 3600 }, pass);
    await check({ iat: seconds - 3599, exp: seconds + 1 }, pass);
    await check({ iat: seconds - 3600, exp: seconds + 1 }, 'unknown');
    await check({ iat: seconds, exp: seconds }, 'unknown');
    await check({ iat: seconds + 10, exp: seconds + 10 }, 'unknown');
  } finally { globalThis.Date = RealDate; }
});

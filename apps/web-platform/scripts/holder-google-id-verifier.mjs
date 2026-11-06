import { createLocalJWKSet, jwtVerify } from 'jose';

// Verification evidence only. The caller-supplied JWKS is NOT authenticated as
// Google's and the pinned subjects/roles are NOT independently approved. No
// result authorizes collection, deletion, or a request. There is no network,
// remote key retrieval, logging, live handler, replay or revocation protection.
// The candidate one-hour time policy relies on the untrusted host wall clock;
// it neither proves a bounded independent time nor revokes issued tokens.
const ISSUER = 'https://accounts.google.com';
const unknown = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false });
const keys = (obj, names) => obj && typeof obj === 'object' && !Array.isArray(obj) &&
  Object.keys(obj).length === names.length && names.every(name => Object.hasOwn(obj, name));
const parse = (raw, max) => {
  if (typeof raw !== 'string' || Buffer.byteLength(raw, 'utf8') > max) throw Error('invalid');
  const parsed = JSON.parse(raw);
  if (JSON.stringify(parsed) !== raw) throw Error('invalid');
  return parsed;
};
const b64 = (s, min, max) => typeof s === 'string' && s.length >= min && s.length <= max &&
  /^[A-Za-z0-9_-]+$/.test(s) && Buffer.from(s, 'base64url').toString('base64url') === s;
const failVerifier = () => Object.freeze({ verify: async () => unknown() });

export function createGoogleIdVerifier(configJson, jwksJson) {
  try {
    const config = parse(configJson, 8192), jwks = parse(jwksJson, 32768);
    if (!keys(config, ['audience', 'subjects']) || typeof config.audience !== 'string' || config.audience.length > 2048 ||
        !Array.isArray(config.subjects) || !config.subjects.length || config.subjects.length > 16 ||
        !keys(jwks, ['keys']) || !Array.isArray(jwks.keys) || !jwks.keys.length || jwks.keys.length > 8) return failVerifier();
    const url = new URL(config.audience);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.href !== config.audience) return failVerifier();
    const roles = new Map();
    for (const entry of config.subjects) {
      if (!keys(entry, ['subject', 'role']) || typeof entry.subject !== 'string' || !/^[0-9]{1,32}$/.test(entry.subject) ||
          typeof entry.role !== 'string' || !/^[a-z][a-z0-9_-]{0,31}$/.test(entry.role) || roles.has(entry.subject)) return failVerifier();
      roles.set(entry.subject, entry.role);
    }
    const kids = new Set();
    for (const key of jwks.keys) {
      if (!keys(key, ['kty', 'n', 'e', 'kid', 'alg', 'use']) || key.kty !== 'RSA' || key.alg !== 'RS256' || key.use !== 'sig' ||
          !b64(key.n, 342, 1366) || !b64(key.e, 2, 8) || typeof key.kid !== 'string' ||
          !/^[A-Za-z0-9_-]{1,128}$/.test(key.kid) || kids.has(key.kid)) return failVerifier();
      kids.add(key.kid);
    }
    const resolveKey = createLocalJWKSet(jwks);
    const audience = config.audience;
    return Object.freeze({ verify: async token => {
      if (typeof token !== 'string' || token.length < 1 || token.length > 16384 || !/^[A-Za-z0-9_.-]+$/.test(token)) return unknown();
      const end = performance.now() + 1000;
      let timer;
      try {
        const timeout = new Promise(resolve => { timer = setTimeout(() => resolve(null), 1000); });
        const verification = jwtVerify(token, resolveKey, { issuer: ISSUER, audience, algorithms: ['RS256'], requiredClaims: ['iss', 'aud', 'sub', 'exp', 'iat'] }).catch(() => null);
        const verified = await Promise.race([verification, timeout]);
        if (performance.now() >= end || !verified) return unknown();
        const payload = verified.payload;
        const now = Math.floor(Date.now() / 1000);
        if (payload.iss !== ISSUER || payload.aud !== audience || typeof payload.sub !== 'string' ||
            !Number.isSafeInteger(payload.exp) || !Number.isSafeInteger(payload.iat) || !Number.isSafeInteger(now) ||
            payload.exp <= now || payload.iat > now || payload.exp <= payload.iat ||
            payload.exp - payload.iat > 3600 || now - payload.iat > 3600 || !roles.has(payload.sub)) return unknown();
        return { state: 'signature_verified_untrusted_keys', subject: payload.sub, role: roles.get(payload.sub), capture_authorized: false, cleanup_authorized: false };
      } catch { return unknown(); }
      finally { clearTimeout(timer); }
    } });
  } catch { return failVerifier(); }
}

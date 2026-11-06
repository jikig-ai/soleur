import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';
import { createGoogleIdVerifier } from './holder-google-id-verifier.mjs';

// Unwired reader: the injected transport and host clock are untrusted. Request
// target and response URL checks cannot prove TLS, DNS, identity or key origin.
// No caching across calls, remote fetch, credentials, logging, or authorization.
// Cache freshness does not revoke tokens or prove keys remain trusted.
// Google lists this JWKS URI and directs clients to respect HTTP cache headers:
// https://developers.google.com/identity/openid-connect/openid-connect
const ENDPOINT = 'https://www.googleapis.com/oauth2/v3/certs';
const MAX_BYTES = 32768, MAX_CHUNKS = 1024;
const unknown = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false });

export async function prepareGoogleJwksVerifier(configJson, fetcher, timeoutMs = 1000) {
  if (typeof configJson !== 'string' || Buffer.byteLength(configJson) > 8192 || typeof fetcher !== 'function' ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 1000) return unknown();
  const controller = new AbortController();
  const deadline = performance.now() + timeoutMs;
  let timer;
  const expired = () => controller.signal.aborted || performance.now() >= deadline;
  const work = async () => {
    let reader;
    try {
      const requestStart = performance.now();
      const response = await fetcher(ENDPOINT, Object.freeze({ method: 'GET', redirect: 'error', credentials: 'omit', signal: controller.signal }));
      if (expired() || !response || response.status !== 200 || response.url !== ENDPOINT || response.redirected !== false) return unknown();
      const headers = response.headers;
      const type = headers.get('content-type'), cc = headers.get('cache-control'), date = headers.get('date'), age = headers.get('age');
      if (typeof type !== 'string' || !/^application\/json(?:\s*;[^\r\n]*)?$/i.test(type) || typeof cc !== 'string' || cc.length > 1024 ||
          /(?:^|,)\s*(?:no-store|no-cache|private)\s*(?:=|,|$)/i.test(cc) || typeof date !== 'string' || date.length > 64 ||
          (age !== null && (typeof age !== 'string' || !/^(?:0|[1-9][0-9]{0,8})$/.test(age)))) return unknown();
      const ages = [...cc.matchAll(/(?:^|,)\s*max-age\s*=\s*([0-9]{1,8})\s*(?=,|$)/gi)];
      if (ages.length !== 1 || [...cc.matchAll(/(?:^|,)\s*max-age\b/gi)].length !== 1) return unknown();
      const maxAge = Math.min(Number(ages[0][1]), 3600), dateMs = Date.parse(date), now = Date.now();
      if (!Number.isFinite(dateMs) || !Number.isFinite(now) || dateMs > now + 60000) return unknown();
      const responseDelay = performance.now() - requestStart;
      if (!Number.isFinite(responseDelay) || responseDelay < 0) return unknown();
      const apparentAge = Math.max(Number(age || 0) * 1000 + responseDelay, Math.max(0, now - dateMs));
      const remaining = maxAge * 1000 - apparentAge;
      if (remaining <= 0 || !response.body) return unknown();
      const validWallUntil = now + remaining, validMonoUntil = performance.now() + remaining;
      reader = response.body.getReader();
      const chunks = []; let size = 0, count = 0;
      for (;;) {
        const item = await reader.read();
        if (expired()) return unknown();
        if (item.done) break;
        if (++count > MAX_CHUNKS) return unknown();
        const copy = snapshotBytes(item.value, MAX_BYTES - size);
        size += copy.length;
        if (copy.length) chunks.push(copy);
      }
      const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size));
      const data = JSON.parse(text);
      if (!data || Array.isArray(data) || Object.keys(data).length !== 1 || !Array.isArray(data.keys) || data.keys.length < 1 || data.keys.length > 8) return unknown();
      const jwks = JSON.stringify(data);
      if (Buffer.byteLength(jwks) > MAX_BYTES || expired() || Date.now() >= validWallUntil || performance.now() >= validMonoUntil) return unknown();
      const inner = createGoogleIdVerifier(configJson, jwks);
      const verifier = Object.freeze({ verify: async token => {
        if (Date.now() >= validWallUntil || performance.now() >= validMonoUntil) return unknown();
        const result = await inner.verify(token);
        return Date.now() >= validWallUntil || performance.now() >= validMonoUntil ? unknown() : result;
      } });
      if (reader) { reader.releaseLock(); reader = undefined; }
      return { state: 'prepared_untrusted_transport', verifier, capture_authorized: false, cleanup_authorized: false };
    } catch { return unknown(); }
    finally {
      if (reader) {
        try { Promise.resolve(reader.cancel()).catch(() => {}); } catch {}
        try { reader.releaseLock(); } catch {}
      }
    }
  };
  try {
    const timeout = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(unknown()); }, timeoutMs); });
    const value = await Promise.race([work().catch(unknown), timeout]);
    return expired() ? unknown() : value;
  } catch { return unknown(); }
  finally { clearTimeout(timer); controller.abort(); }
}

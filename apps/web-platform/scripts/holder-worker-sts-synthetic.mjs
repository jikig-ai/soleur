import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Synthetic-only exchange experiment. The fixed subject token is NOT a DER
// certificate, the audience is a fixture, and the sole accepted token is a
// fixed synthetic string. Injected fetch is not verified as an mTLS binding.
// No result authenticates a worker or authorizes any live operation. This file
// has no network client or deployable handler; no live credential is accepted.
const ENDPOINT = 'https://sts.mtls.googleapis.com/v1/token';
const AUDIENCE = '//iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/synthetic-pool/providers/synthetic-provider';
const SUBJECT = JSON.stringify(['c3ludGhldGljLW5vdC1jZXJ0aWZpY2F0ZQ==']);
const ACCESS = 'urn:ietf:params:oauth:token-type:access_token';
const MAX_BYTES = 65536;
const MAX_CHUNKS = 1024;
const result = (state = 'unknown') => ({ state, capture_authorized: false, cleanup_authorized: false, identity_verified: false });

export async function simulateWorkerSts(binding, timeoutMs = 1000) {
  try {
    if (!binding || typeof binding.fetch !== 'function' || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 1000) return result();
    const fetch = binding.fetch.bind(binding);
    const controller = new AbortController();
    const deadlineAt = performance.now() + timeoutMs;
    let timer;
    const deadline = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(result()); }, timeoutMs); });
    const work = async () => {
      let reader, response;
      const outcome = await (async () => {
        try {
          const body = JSON.stringify({ subject_token_type: 'urn:ietf:params:oauth:token-type:mtls',
            grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange', audience: AUDIENCE,
            requested_token_type: ACCESS, scope: 'https://www.googleapis.com/auth/cloud-platform', subject_token: SUBJECT });
          response = await fetch(ENDPOINT, { method: 'POST', redirect: 'error', headers: { 'content-type': 'application/json' }, body, signal: controller.signal });
          if (controller.signal.aborted || performance.now() >= deadlineAt || !response || response.status !== 200 || response.redirected || !response.body) return result();
          reader = response.body.getReader();
          const chunks = [];
          let size = 0, count = 0;
          for (;;) {
            const { done, value } = await reader.read();
            if (controller.signal.aborted || performance.now() >= deadlineAt) return result();
            if (done) break;
            if (++count > MAX_CHUNKS) return result();
            const bytes = snapshotBytes(value, MAX_BYTES - size);
            size += bytes.length;
            if (bytes.length) chunks.push(bytes);
          }
          const decoded = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size));
          const parsed = JSON.parse(decoded);
          if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || JSON.stringify(parsed) !== decoded ||
              Object.keys(parsed).length !== 4 || !['access_token', 'issued_token_type', 'token_type', 'expires_in'].every(key => Object.hasOwn(parsed, key)) ||
              parsed.access_token !== 'synthetic-token' || parsed.issued_token_type !== ACCESS || parsed.token_type !== 'Bearer' ||
              !Number.isSafeInteger(parsed.expires_in) || parsed.expires_in < 1 || parsed.expires_in > 3600) return result();
          return result('synthetic_match');
        } catch { return result(); }
      })();
      let cleanupFailed = false;
      if (reader) {
        try { Promise.resolve(reader.cancel()).catch(() => {}); } catch { cleanupFailed = true; }
        try { reader.releaseLock(); } catch { cleanupFailed = true; }
      } else if (response?.body) {
        try { Promise.resolve(response.body.cancel()).catch(() => {}); } catch { cleanupFailed = true; }
      }
      return cleanupFailed ? result() : outcome;
    };
    try { return await Promise.race([work(), deadline]); }
    finally { clearTimeout(timer); controller.abort(); }
  } catch { return result(); }
}

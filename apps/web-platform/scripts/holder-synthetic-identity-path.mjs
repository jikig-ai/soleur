// Disposable synthetic protocol fixture, not an authentication implementation.
// All identifiers, tokens and commands are fixed non-credential literals. The
// injected verifier is only a test double; its claims do not prove identity.
// This module has no listener, fetch, credentials, provider client or writes.
const AUDIENCE = 'https://synthetic.invalid/receiver';
const TOKEN = 'synthetic-id-token';
const COMMAND = 'synthetic-probe';
const NONCE = '0123456789abcdef0123456789abcdef';
const BODY = JSON.stringify({ token: TOKEN, command: COMMAND, nonce: NONCE });
const CLAIMS = JSON.stringify({ issuer: 'synthetic-issuer', audience: AUDIENCE,
  subject: 'synthetic-worker' });
const result = state => ({ state, capture_authorized: false, cleanup_authorized: false });
const unknown = () => result('unknown');
const MATCH = JSON.stringify(result('synthetic_match'));

async function bounded(timeoutMs, work) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 1000) return unknown();
  const controller = new AbortController();
  const end = performance.now() + timeoutMs;
  let timer;
  try {
    const timeout = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(unknown()); }, timeoutMs); });
    const expired = () => controller.signal.aborted || performance.now() >= end;
    const execution = Promise.resolve().then(() => work(controller.signal, expired)).catch(unknown);
    const value = await Promise.race([execution, timeout]);
    if (controller.signal.aborted || performance.now() >= end) return unknown();
    return value;
  } catch { return unknown(); }
  finally { clearTimeout(timer); controller.abort(); }
}

// Independent request-binding/replay seam is also an injected test double. It
// cannot establish actual proof, durable replay protection, or authorization.
export async function receiveSyntheticRequest(body, verifyIdentity, checkBinding, timeoutMs = 1000) {
  if (typeof body !== 'string' || body !== BODY || typeof verifyIdentity !== 'function' || typeof checkBinding !== 'function') return unknown();
  return bounded(timeoutMs, async (signal, expired) => {
    const claims = await verifyIdentity(TOKEN, Object.freeze({ audience: AUDIENCE, signal }));
    if (expired() || JSON.stringify(claims) !== CLAIMS || expired()) return unknown();
    const accepted = await checkBinding(Object.freeze({ subject: 'synthetic-worker', audience: AUDIENCE,
      command: COMMAND, nonce: NONCE, signal }));
    if (expired() || accepted !== true) return unknown();
    return result('synthetic_match');
  });
}

export async function runSyntheticWorker(exchange, send, timeoutMs = 1000) {
  if (typeof exchange !== 'function' || typeof send !== 'function') return unknown();
  return bounded(timeoutMs, async (signal, expired) => {
    const token = await exchange(Object.freeze({ audience: AUDIENCE, command: COMMAND, nonce: NONCE, signal }));
    if (expired() || token !== TOKEN) return unknown();
    const response = await send(Object.freeze({ url: AUDIENCE, method: 'POST', body: BODY, signal }));
    if (expired() || JSON.stringify(response) !== MATCH || expired()) return unknown();
    return result('synthetic_match');
  });
}

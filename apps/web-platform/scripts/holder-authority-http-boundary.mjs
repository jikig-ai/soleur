import { createGoogleIdVerifier } from './holder-google-id-verifier.mjs';
import { prepareIntent } from './holder-authority-intent.mjs';
import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Unwired HTTP preparation boundary. Injected keys, role pins, replay check and
// request clock are assertions, not independently authenticated evidence. No
// result authorizes capture, cleanup, a write, or a live authority transition.
// This handler does not listen, fetch keys, log requests or write to a provider.
// It receives an already parsed Node request; these header checks do not prove
// that upstream proxies and the Node HTTP parser agree on wire-level framing.
// Destroying a refused request can close its socket before a 403 is delivered.
// It cannot force a hostile iterator or injected dependency to stop executing.
const ALLOWED = Object.freeze({ administrator: Object.freeze(['prepare', 'arm', 'revoke']),
  collector: Object.freeze(['begin_capture', 'seal']), worker: Object.freeze(['report_attempt']),
  verifier: Object.freeze(['report_verified']) });
const denied = () => ({ state: 'unknown', capture_authorized: false, cleanup_authorized: false, deletion_verified: false });
const object = (v, names) => v && typeof v === 'object' && !Array.isArray(v) &&
  Object.keys(v).length === names.length && names.every(n => Object.hasOwn(v, n));

function bearer(raw) {
  if (!Array.isArray(raw) || raw.length % 2 || raw.length > 128) throw Error('invalid');
  let authorization, type, length, transfer;
  for (let i = 0; i < raw.length; i += 2) {
    const name = raw[i], value = raw[i + 1];
    if (typeof name !== 'string' || typeof value !== 'string' || name.length > 128 || value.length > 17000) throw Error('invalid');
    const lower = name.toLowerCase();
    if (lower === 'authorization') { if (authorization !== undefined) throw Error('invalid'); authorization = value; }
    if (lower === 'content-type') { if (type !== undefined) throw Error('invalid'); type = value; }
    if (lower === 'content-length') { if (length !== undefined) throw Error('invalid'); length = value; }
    if (lower === 'transfer-encoding') { if (transfer !== undefined) throw Error('invalid'); transfer = value; }
  }
  if (type !== 'application/json' || typeof authorization !== 'string' || !/^Bearer [A-Za-z0-9_.-]{1,16384}$/.test(authorization) ||
      (length !== undefined && (!/^(?:0|[1-9][0-9]{0,4})$/.test(length) || Number(length) > 16384)) ||
      (transfer !== undefined && (transfer.toLowerCase() !== 'chunked' || length !== undefined))) throw Error('invalid');
  return { token: authorization.slice(7), length: length === undefined ? undefined : Number(length) };
}

export function createAuthorityHttpHandler(configJson, keySource, checkReplay) {
  // Primitive strings are snapshots. Invalid or absent injected seams refuse.
  const enabled = typeof configJson === 'string' && Buffer.byteLength(configJson) <= 8192 &&
    typeof keySource === 'function' && typeof checkReplay === 'function';
  return async (req, res) => {
    const controller = new AbortController();
    const deadline = performance.now() + 1000;
    let timer;
    const expired = () => controller.signal.aborted || performance.now() >= deadline;
    const work = async () => {
      if (!enabled || req.method !== 'POST' || req.url !== '/v1/intent') return denied();
      const { token, length } = bearer(req.rawHeaders);
      const chunks = []; let size = 0, count = 0;
      for await (const chunk of req) {
        if (expired() || ++count > 1024) return denied();
        const copy = snapshotBytes(chunk, 16384 - size);
        size += copy.length; if (copy.length) chunks.push(copy);
      }
      if (expired() || (length !== undefined && length !== size)) return denied();
      const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size));
      const payload = JSON.parse(text);
      if (JSON.stringify(payload) !== text || !object(payload, ['base', 'command', 'clock']) ||
          !payload.command || typeof payload.command !== 'object' || typeof payload.command.action !== 'string' || expired()) return denied();
      const jwksJson = await keySource(controller.signal);
      if (expired() || typeof jwksJson !== 'string' || Buffer.byteLength(jwksJson) > 32768) return denied();
      const identity = await createGoogleIdVerifier(configJson, jwksJson).verify(token);
      if (expired() || identity.state !== 'signature_verified_untrusted_keys' || !Object.hasOwn(ALLOWED, identity.role) ||
          !ALLOWED[identity.role].includes(payload.command.action)) return denied();
      const intent = prepareIntent({ base: JSON.stringify(payload.base), command: JSON.stringify(payload.command),
        clock: JSON.stringify(payload.clock), principal: JSON.stringify({ issuer: 'https://accounts.google.com', subject: identity.subject }) });
      if (expired() || intent.state !== 'prepared_unverified') return denied();
      const replayOk = await checkReplay(Object.freeze({ subject: identity.subject, command_id: payload.command.command_id,
        intent_sha256: intent.intent_sha256, signal: controller.signal }));
      if (expired() || replayOk !== true) return denied();
      return { state: 'prepared_unverified', intent_sha256: intent.intent_sha256, capture_authorized: false, cleanup_authorized: false, deletion_verified: false };
    };
    let value = denied();
    try {
      const timeout = new Promise(resolve => { timer = setTimeout(() => { controller.abort(); resolve(denied()); }, 1000); });
      value = await Promise.race([Promise.resolve().then(work).catch(denied), timeout]);
      if (expired()) value = denied();
    } catch { value = denied(); }
    finally { clearTimeout(timer); controller.abort(); }
    if (value.state !== 'prepared_unverified') {
      try { req.destroy(); } catch { /* cleanup failure is not exposed */ }
    }
    try {
      res.writeHead(value.state === 'prepared_unverified' ? 200 : 403, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(value));
    } catch { /* no raw errors or request details leave this boundary */ }
  };
}

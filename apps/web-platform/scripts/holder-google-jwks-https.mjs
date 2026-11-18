import { request as nodeRequest } from 'node:https';
import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Explicitly constructed, unwired transport. Default implementation will make
// a real HTTPS request if invoked. Caller must bind runtime and review source;
// injected implementations cannot establish Google key provenance or identity.
const URL = 'https://www.googleapis.com/oauth2/v3/certs';
const failError = () => new Error('jwks_transport_failed');
const abortState = Object.getOwnPropertyDescriptor(AbortSignal.prototype, 'aborted').get;
const add = EventTarget.prototype.addEventListener;
const remove = EventTarget.prototype.removeEventListener;
const fields = ['method', 'redirect', 'credentials', 'signal'];
const getSignal = opts => {
  const descriptors = Object.getOwnPropertyDescriptors(opts);
  if (Object.keys(descriptors).length !== fields.length || fields.some(k => !descriptors[k] || !Object.hasOwn(descriptors[k], 'value')) ||
      descriptors.method.value !== 'GET' || descriptors.redirect.value !== 'error' || descriptors.credentials.value !== 'omit') throw failError();
  const signal = descriptors.signal.value;
  if (abortState.call(signal)) throw failError();
  return signal;
};

export function createGoogleJwksHttpsTransport(requestImpl = nodeRequest) {
  if (typeof requestImpl !== 'function') throw failError();
  return async (url, options) => {
    let signal;
    try {
      if (url !== URL || !options || typeof options !== 'object') throw failError();
      signal = getSignal(options);
    } catch { throw failError(); }
    return new Promise((resolve, reject) => {
      let req, res, settled = false;
      const end = performance.now() + 1000;
      const cleanup = () => { clearTimeout(timer); try { remove.call(signal, 'abort', fail); return true; } catch { return false; } };
      const destroy = () => { try { req?.destroy(); } catch {} try { res?.destroy(); } catch {} };
      const fail = () => { if (settled) return; settled = true; cleanup(); destroy(); reject(failError()); };
      const expired = () => settled || abortState.call(signal) || performance.now() >= end;
      const timer = setTimeout(fail, 1000);
      try {
        add.call(signal, 'abort', fail, { once: true });
        if (expired()) return fail();
        req = requestImpl({ protocol: 'https:', hostname: 'www.googleapis.com', port: 443,
          servername: 'www.googleapis.com', path: '/oauth2/v3/certs', method: 'GET', agent: false,
          rejectUnauthorized: true, headers: { accept: 'application/json' } }, response => {
          try {
            res = response;
            res.on('error', fail);
            if (expired() || res.statusCode !== 200) return fail();
            const headerMap = new Map();
            for (const name of ['content-type', 'cache-control', 'date', 'age']) {
              const value = res.headers[name];
              if (value !== undefined && (typeof value !== 'string' || value.length > 1024 || /[\r\n]/.test(value))) return fail();
              if (value !== undefined) headerMap.set(name, value);
            }
            let count = 0, size = 0; const chunks = [];
            res.once('aborted', fail);
            res.once('close', () => { if (!settled) fail(); });
            res.on('data', chunk => {
              try {
                if (expired() || ++count > 1024) return fail();
                const copy = snapshotBytes(chunk, 32768 - size);
                size += copy.length; if (copy.length) chunks.push(copy);
              } catch { fail(); }
            });
            res.once('end', () => {
              try {
                if (expired()) return fail();
                const bodyBytes = Buffer.concat(chunks, size);
                const body = new ReadableStream({ start(c) { c.enqueue(bodyBytes); c.close(); } });
                const headers = Object.freeze({ get: name => headerMap.get(name) ?? null });
                const value = { status: 200, url: URL, redirected: false, headers, body };
                if (expired()) return fail();
                if (!cleanup()) return fail();
                if (expired()) return fail();
                settled = true; resolve(value);
              } catch { fail(); }
            });
          } catch { fail(); }
        });
        req.on('error', fail);
        if (settled) { try { req.destroy(); } catch {} return; }
        if (expired()) return fail();
        req.end();
      } catch { fail(); }
    });
  };
}

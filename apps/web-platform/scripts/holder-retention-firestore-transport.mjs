import { request as httpsRequest } from 'node:https';
import { snapshotExpectedBase, validateRestrictedCommit } from './holder-retention-firestore-ledger.mjs';
import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Unwired transport boundary. The caller must separately bind the executable,
// credential source, operation, runtime, and legal/infrastructure approvals.
// A timeout does not prove that a submitted write did not commit.
const error = () => new Error('transport_failed');
const MAX_RESPONSE_CHUNKS = 1024;
const aborted = Object.getOwnPropertyDescriptor(AbortSignal.prototype, 'aborted').get;
const addListener = EventTarget.prototype.addEventListener;
const removeListener = EventTarget.prototype.removeEventListener;

export function makeFirestoreTransport({ projectId, databaseId, expectedBase, getAccessToken, requestImpl = httpsRequest }) {
  if (typeof projectId !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId) ||
      typeof databaseId !== 'string' || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(databaseId) ||
      typeof getAccessToken !== 'function' || typeof requestImpl !== 'function') throw error();
  let base;
  try { base = snapshotExpectedBase(expectedBase); } catch { throw error(); }
  const apiRoot = ['v1', 'projects'].join('/');
  const root = `/${apiRoot}/${projectId}/databases/${databaseId}/documents`;
  const getPath = `${root}/holder_evidence_operations/${base.operation_id}`;
  return async (input) => {
    let target, method, body, maxResponseBytes, signal;
    try {
      ({ method, body, maxResponseBytes, signal } = input);
      target = new URL(input.url);
    } catch { throw error(); }
    let isAborted;
    try { isAborted = aborted.call(signal); } catch { throw error(); }
    if (!['GET', 'POST'].includes(method) || target.protocol !== 'https:' ||
        target.hostname !== 'firestore.googleapis.com' || target.port || target.username || target.password || target.search || target.hash ||
        (method === 'GET' ? target.pathname !== getPath || body !== undefined : target.pathname !== `${root}:commit` ||
          typeof body !== 'string' || Buffer.byteLength(body) > 32768 || !validateRestrictedCommit(body, projectId, databaseId, base)) ||
        !Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1 || maxResponseBytes > 65536 ||
        !(signal instanceof AbortSignal) || isAborted) throw error();
    // A shape check cannot prove that an authorized authority service ran the
    // state, evidence and clock checks. Keep writes disabled until it exists.
    if (method === 'POST') throw error();

    return await new Promise((resolve, reject) => {
      let settled = false, req, response;
      const cleanup = () => {
        clearTimeout(timer);
        try { removeListener.call(signal, 'abort', fail); return true; } catch { return false; }
      };
      const fail = () => {
        if (settled) return;
        settled = true; cleanup();
        try { req?.destroy(); } catch { /* fixed failure below */ }
        try { response?.destroy(); } catch { /* fixed failure below */ }
        reject(error());
      };
      const finish = (value) => {
        if (settled) return;
        settled = true;
        if (!cleanup()) {
          try { req?.destroy(); } catch { /* fixed failure below */ }
          try { response?.destroy(); } catch { /* fixed failure below */ }
          reject(error());
          return;
        }
        resolve(value);
      };
      const timer = setTimeout(fail, 4000);
      try { addListener.call(signal, 'abort', fail, { once: true }); } catch { fail(); return; }
      Promise.resolve().then(() => {
        if (settled || aborted.call(signal)) return fail();
        return getAccessToken(signal);
      }).then((token) => {
        if (settled || aborted.call(signal)) return fail();
        if (typeof token !== 'string' || token.length < 1 || token.length > 4096 || !/^[A-Za-z0-9._~+/-]+=*$/.test(token)) return fail();
        const headers = { authorization: `Bearer ${token}` };
        if (method === 'POST') {
          headers['content-type'] = 'application/json';
          headers['content-length'] = String(Buffer.byteLength(body));
        }
        req = requestImpl({ protocol: 'https:', hostname: 'firestore.googleapis.com', port: 443,
          servername: 'firestore.googleapis.com', method, path: target.pathname,
          headers, agent: false, rejectUnauthorized: true }, (res) => {
          try {
          response = res;
          res.on('error', fail);
          if (settled) { res.destroy(); return; }
          const status = res.statusCode;
          if (!Number.isInteger(status) || status < 100 || status > 599) return fail();
          if (status !== 200) { res.destroy(); finish({ status, body: '{}' }); return; }
          res.once('aborted', fail);
          res.once('close', () => { if (!settled) fail(); });
          const chunks = [];
          let size = 0;
          let chunkCount = 0;
          res.on('data', (chunk) => {
            if (settled) return;
            try {
              if (++chunkCount > MAX_RESPONSE_CHUNKS) return fail();
              const bytes = snapshotBytes(chunk, maxResponseBytes - size);
              size += bytes.length;
              if (bytes.length) chunks.push(bytes);
            } catch { fail(); }
          });
          res.once('end', () => {
            if (settled) return;
            try { finish({ status: 200, body: new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size)) }); }
            catch { fail(); }
          });
          } catch { fail(); }
        });
        req.on('error', fail);
        req.setTimeout(4000, fail);
        req.end(method === 'POST' ? body : undefined);
      }).catch(fail);
    });
  };
}

import { createHash, X509Certificate } from 'node:crypto';

// Request preparation only. Pins are asserted by the caller, not an approval.
// Certificate linkage is not trust-anchor, identity, revocation or clock proof,
// and it does not prove that a Worker binding contains the matching private key.
// transmitWorkerSts is deliberately hard-disabled before touching the binding.
const ENDPOINT = 'https://sts.mtls.googleapis.com/v1/token';
const ACCESS = 'urn:ietf:params:oauth:token-type:access_token';
const AUDIENCE = /^\/\/iam\.googleapis\.com\/projects\/[0-9]{6,20}\/locations\/global\/workloadIdentityPools\/[a-z0-9][a-z0-9-]{0,62}\/providers\/[a-z0-9][a-z0-9-]{0,62}(?![\s\S])/;
const unknown = () => ({ state: 'unknown', identity_verified: false, capture_authorized: false, cleanup_authorized: false });
const keys = (value, expected) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).length === expected.length && expected.every(key => Object.hasOwn(value, key));
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const parse = (raw, cap) => {
  if (typeof raw !== 'string' || Buffer.byteLength(raw, 'utf8') > cap) throw new Error('invalid');
  const value = JSON.parse(raw);
  if (JSON.stringify(value) !== raw) throw new Error('invalid');
  return value;
};

export function prepareWorkerStsRequest(configJson, pinsJson) {
  try {
    const config = parse(configJson, 100000), pins = parse(pinsJson, 4096);
    if (!keys(config, ['audience', 'binding_id', 'leaf_sha256', 'chain_der_base64']) ||
        !keys(pins, ['audience', 'binding_id', 'leaf_sha256']) ||
        typeof config.audience !== 'string' || !AUDIENCE.test(config.audience) || config.audience !== pins.audience ||
        typeof config.binding_id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(config.binding_id) ||
        config.binding_id !== pins.binding_id || !digest(config.leaf_sha256) || config.leaf_sha256 !== pins.leaf_sha256 ||
        !Array.isArray(config.chain_der_base64) || config.chain_der_base64.length < 1 || config.chain_der_base64.length > 5) return unknown();
    let total = 0;
    const certs = config.chain_der_base64.map(value => {
      if (typeof value !== 'string' || value.length < 4 || value.length > 43692 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new Error('invalid');
      const bytes = Buffer.from(value, 'base64');
      if (bytes.length < 1 || bytes.length > 32768 || bytes.toString('base64') !== value || (total += bytes.length) > 65536) throw new Error('invalid');
      const cert = new X509Certificate(bytes);
      if (!cert.raw.equals(bytes)) throw new Error('invalid');
      return cert;
    });
    if (certs[0].ca || createHash('sha256').update(certs[0].raw).digest('hex') !== pins.leaf_sha256) return unknown();
    for (let i = 1; i < certs.length; i++) {
      if (!certs[i].ca || !certs[i - 1].checkIssued(certs[i]) || !certs[i - 1].verify(certs[i].publicKey)) return unknown();
    }
    const body = JSON.stringify({ subject_token_type: 'urn:ietf:params:oauth:token-type:mtls',
      grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange', audience: config.audience,
      requested_token_type: ACCESS, scope: 'https://www.googleapis.com/auth/cloud-platform',
      subject_token: JSON.stringify(config.chain_der_base64) });
    const request = Object.freeze({ url: ENDPOINT, method: 'POST', redirect: 'error',
      headers: Object.freeze({ 'content-type': 'application/json' }), body });
    return Object.freeze({ ...unknown(), state: 'prepared_unverified', binding_id: config.binding_id, request });
  } catch { return unknown(); }
}

export async function transmitWorkerSts() {
  // No caller-provided flag, injected function or claimed pin authorizes this.
  // A future independently reviewed authority must replace this hard refusal.
  return unknown();
}

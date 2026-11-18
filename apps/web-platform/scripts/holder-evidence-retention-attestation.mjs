// Offline synthetic signature check only: signed claims do not prove the
// existence, independence or operation of any real deletion infrastructure.
import { createHash, verify } from 'node:crypto';

const day = 24 * 60 * 60 * 1000;
const identity = (v) => typeof v === 'string' && /^[a-z0-9][a-z0-9._-]{0,79}$/.test(v);
const time = (v) => Number.isSafeInteger(v) && v >= 0;
const claims = ['job_readback', 'storage_identity', 'copy_controls', 'clock_verified', 'host_loss_rehearsed'];
const result = (state) => ({ state, real_admission: false, independent_deletion_proven: false, writer_clearance: false });

export function attestationMessage(contract, entry) {
  return Buffer.from(JSON.stringify(['holder-retention-attestation-v1', contract.operation_id, contract.vault_id,
    contract.owner_id, contract.generation, contract.manifest_sha256, contract.collector_domain, contract.vault_domain,
    contract.capture_start_ms, contract.deadline_ms, entry.witness_id, entry.role, entry.domain,
    entry.issued_at_ms, entry.expires_at_ms, ...claims.map((key) => entry[key])]));
}

export function verifyRetentionAttestations(input) {
  try {
    const { contract: c, attestations: entries, trust, now_ms: now } = input;
    if (!c || !['operation_id', 'vault_id', 'owner_id', 'generation', 'collector_domain', 'vault_domain'].every((k) => identity(c[k])) ||
      !/^[a-f0-9]{64}$/.test(c.manifest_sha256) || !time(c.capture_start_ms) || !time(c.deadline_ms) || !time(now) ||
      c.deadline_ms <= c.capture_start_ms || c.deadline_ms - c.capture_start_ms > day || now < c.capture_start_ms || now >= c.deadline_ms ||
      !trust || !Array.isArray(entries) || entries.length !== 3) return result('unknown');
    const ids = new Set(), domains = new Set([c.collector_domain, c.vault_domain]), keys = new Set();
    if (domains.size !== 2) return result('unknown');
    let workers = 0, verifiers = 0;
    for (const e of entries) {
      if (!e || !identity(e.witness_id) || !identity(e.domain) || !Object.hasOwn(trust, e.witness_id) ||
        ids.has(e.witness_id) || domains.has(e.domain) || !time(e.issued_at_ms) || !time(e.expires_at_ms) ||
        e.issued_at_ms > c.capture_start_ms || c.capture_start_ms - e.issued_at_ms > 60000 ||
        e.issued_at_ms > now || e.expires_at_ms <= now || e.expires_at_ms > c.deadline_ms ||
        !claims.every((k) => e[k] === true) || typeof e.signature !== 'string') return result('unknown');
      const t = trust[e.witness_id];
      if (!t || t.role !== e.role || t.domain !== e.domain || t.publicKey?.type !== 'public' || t.publicKey.asymmetricKeyType !== 'ed25519') return result('unknown');
      if (e.role === 'worker') workers++; else if (e.role === 'verifier') verifiers++; else return result('unknown');
      const fingerprint = createHash('sha256').update(t.publicKey.export({ type: 'spki', format: 'der' })).digest('hex');
      const sig = Buffer.from(e.signature, 'base64');
      if (keys.has(fingerprint) || sig.length !== 64 || sig.toString('base64') !== e.signature ||
        !verify(null, attestationMessage(c, e), t.publicKey, sig)) return result('unknown');
      ids.add(e.witness_id); domains.add(e.domain); keys.add(fingerprint);
    }
    return result(workers === 2 && verifiers === 1 ? 'signatures_valid_only' : 'unknown');
  } catch { return result('unknown'); }
}

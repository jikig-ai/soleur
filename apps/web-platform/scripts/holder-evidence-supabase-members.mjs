import { snapshotBytes } from './holder-evidence-byte-snapshot.mjs';

// Offline projection only; no transport, credential access, or persistence.
export function projectOrganizationMembers(bytes, limits) {
  const result = (state, members = []) => ({ state, members, project_access: 'unknown', holder_coverage: 'unknown', writer_clearance: false });
  try {
    if (!(bytes instanceof Uint8Array) || !Number.isSafeInteger(limits?.maxBytes) || limits.maxBytes < 1 || limits.maxBytes > 1048576 ||
        !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 1 || limits.maxRows > 10000) return result('failed');
    const raw = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(snapshotBytes(bytes, limits.maxBytes)));
    if (!Array.isArray(raw) || raw.length > limits.maxRows) return result('failed');
    const seen = new Set();
    const members = raw.map((entry) => {
      if (!entry || typeof entry.user_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(entry.user_id) ||
          typeof entry.role_name !== 'string' || seen.has(entry.user_id)) throw new Error('invalid');
      seen.add(entry.user_id);
      return { user_id: entry.user_id, role: entry.role_name === 'Owner' ? 'owner' : 'unknown' };
    });
    // Pagination, identity format and role mapping are not established by the
    // documented example; even a valid projection cannot establish a census.
    return result('partial', members);
  } catch { return result('failed'); }
}

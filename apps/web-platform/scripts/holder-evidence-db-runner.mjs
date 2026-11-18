import { createHash } from 'node:crypto';
import { inspectEmbeddedRoles } from './holder-evidence-db-role-core.mjs';
import { readLocalFile } from './holder-evidence-db-local-source.mjs';

export { inspectEmbeddedRoles };

// Offline fixture loader only. These hashes bind query bytes, not the code
// executing them. A live caller needs a separately reviewed bundle and launcher.
const failure = () => ({ state: 'failed', observed_count: null, holder_coverage: 'unknown', writer_clearance: false });
const readQuery = () => readLocalFile('holder-evidence-db-roles.sql');

export async function readLocalRoleBindings() {
  const query = await readQuery();
  return { query_sha256: createHash('sha256').update(query).digest('hex') };
}

export async function inspectBoundRoles(database, expected, options = {}) {
  try {
    return await inspectEmbeddedRoles(database, await readQuery(), expected?.query_sha256, options);
  } catch { return failure(); }
}

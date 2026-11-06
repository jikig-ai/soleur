import { createHash } from 'node:crypto';
import { inspectEmbeddedRoster } from './holder-evidence-db-roster-core.mjs';
import { readLocalFile } from './holder-evidence-db-local-source.mjs';

export { inspectEmbeddedRoster };

// Offline fixture loader only; file hashes do not bind the executing code.
const failure = () => ({ state: 'failed', rows: [] });
const wholeFailure = () => ({ roles: failure(), memberships: failure(), cross_reference: 'unknown', cross_reference_scope: 'returned_rows_only', backend_stop:'unknown', holder_coverage: 'unknown', writer_clearance: false });
const sha = (value) => createHash('sha256').update(value).digest('hex');

async function inputs() {
  const [roles, memberships] = await Promise.all([
    readLocalFile('holder-evidence-db-roles.sql'), readLocalFile('holder-evidence-db-memberships.sql'),
  ]);
  return { roles, memberships };
}

export async function readLocalRosterBindings() {
  const source = await inputs();
  return { roles_sha256: sha(source.roles), memberships_sha256: sha(source.memberships) };
}

export async function inspectBoundRoster(database, expected, options = {}) {
  try { return await inspectEmbeddedRoster(database, await inputs(), expected, options); }
  catch { return wholeFailure(); }
}

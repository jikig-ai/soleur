import { constants, promises as fs } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Offline fixture reads only. These bytes do not attest executable identity.
const directory = dirname(fileURLToPath(import.meta.url));
const names = new Set(['holder-evidence-db-roles.sql', 'holder-evidence-db-memberships.sql', 'holder-evidence-db-roles-projected.sql', 'holder-evidence-db-memberships-projected.sql', 'holder-evidence-db-functions-projected.sql', 'holder-evidence-db-schemas-projected.sql', 'holder-evidence-db-tables-projected.sql', 'holder-evidence-db-sessions-projected.sql', 'holder-evidence-db-acls-projected.sql', 'holder-evidence-db-control-acls-projected.sql', 'holder-evidence-db-policies-projected.sql', 'holder-evidence-db-triggers-projected.sql', 'holder-evidence-db-sequences-projected.sql', 'holder-evidence-db-materialized-projected.sql', 'holder-evidence-db-sequence-acls-projected.sql',
  'holder-evidence-db-roster-core.mjs', 'holder-evidence-db-query-source.mjs']);
const maxBytes = 1024 * 1024;

export async function readBoundedHandle(handle) {
  const stat = await handle.stat();
  if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size < 1 || stat.size > maxBytes) throw new Error('source');
  const buffer = Buffer.allocUnsafe(stat.size + 1);
  let read = 0;
  while (read < buffer.length) {
    const length = Math.min(65536, buffer.length - read);
    const result = await handle.read(buffer, read, length, read);
    if (!Number.isSafeInteger(result.bytesRead) || result.bytesRead < 0 || result.bytesRead > length) throw new Error('source');
    if (result.bytesRead === 0) break;
    read += result.bytesRead;
  }
  if (read !== stat.size) throw new Error('source');
  return buffer.subarray(0, read);
}

export async function readLocalFile(name) {
  if (!names.has(name)) throw new Error('source');
  const handle = await fs.open(join(directory, name), constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try { return await readBoundedHandle(handle); }
  finally { await handle.close(); }
}

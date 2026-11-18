import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import ts from 'typescript';
import { readLocalFile } from './holder-evidence-db-local-source.mjs';
import { verifiedQuery } from './holder-evidence-db-query-source.mjs';

// Offline build only: this bundle has no credentials, provider transport,
// receipt writer or independent retention service. Its digest is not approval.
const directory = dirname(fileURLToPath(import.meta.url));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const allowedInputs = new Set(['holder-query-entry.mjs', 'holder-evidence-db-roster-core.mjs', 'holder-evidence-db-query-source.mjs']);

// A narrow syntactic check, not proof against all computed execution or a
// replacement for reviewing the resulting bundle and its runtime.
export function assertStaticSource(source) {
  const file = ts.createSourceFile('holder-source.mjs', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  if (file.parseDiagnostics.length) throw new Error('bundle_source');
  const visit = (node) => {
    if ((ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) ||
        ts.isImportEqualsDeclaration(node) ||
        (ts.isIdentifier(node) && ['require', 'eval', 'Function', 'createRequire'].includes(node.text))) throw new Error('bundle_source');
    ts.forEachChild(node, visit);
  };
  visit(file);
}

export async function buildQueryBundle() {
  const [roles, memberships, functions, schemas, tables, sessions, relationAcls, controlAcls, policies, triggers, sequences, materializedViews, sequenceAcls, rosterSource, querySource] = await Promise.all([
    readLocalFile('holder-evidence-db-roles-projected.sql'), readLocalFile('holder-evidence-db-memberships-projected.sql'),
    readLocalFile('holder-evidence-db-functions-projected.sql'),
    readLocalFile('holder-evidence-db-schemas-projected.sql'),
    readLocalFile('holder-evidence-db-tables-projected.sql'),
    readLocalFile('holder-evidence-db-sessions-projected.sql'),
    readLocalFile('holder-evidence-db-acls-projected.sql'),
    readLocalFile('holder-evidence-db-control-acls-projected.sql'),
    readLocalFile('holder-evidence-db-policies-projected.sql'),
    readLocalFile('holder-evidence-db-triggers-projected.sql'),
    readLocalFile('holder-evidence-db-sequences-projected.sql'),
    readLocalFile('holder-evidence-db-materialized-projected.sql'),
    readLocalFile('holder-evidence-db-sequence-acls-projected.sql'),
    readLocalFile('holder-evidence-db-roster-core.mjs'), readLocalFile('holder-evidence-db-query-source.mjs'),
  ]);
  const queries = { roles_sha256: sha(roles), memberships_sha256: sha(memberships), functions_sha256: sha(functions), schemas_sha256: sha(schemas), tables_sha256: sha(tables), sessions_sha256: sha(sessions), relation_acls_sha256: sha(relationAcls), control_acls_sha256: sha(controlAcls), policies_sha256: sha(policies), triggers_sha256: sha(triggers), sequences_sha256: sha(sequences), materialized_views_sha256: sha(materializedViews), sequence_acls_sha256: sha(sequenceAcls) };
  verifiedQuery(roles, queries.roles_sha256);
  verifiedQuery(memberships, queries.memberships_sha256);
  verifiedQuery(functions, queries.functions_sha256);
  verifiedQuery(schemas, queries.schemas_sha256);
  verifiedQuery(tables, queries.tables_sha256);
  verifiedQuery(sessions, queries.sessions_sha256);
  verifiedQuery(relationAcls, queries.relation_acls_sha256);
  verifiedQuery(controlAcls, queries.control_acls_sha256);
  verifiedQuery(policies, queries.policies_sha256);
  verifiedQuery(triggers, queries.triggers_sha256);
  verifiedQuery(sequences, queries.sequences_sha256);
  verifiedQuery(materializedViews, queries.materialized_views_sha256);
  verifiedQuery(sequenceAcls, queries.sequence_acls_sha256);
  const snapshots = new Map([
    [join(directory, 'holder-evidence-db-roster-core.mjs'), verifiedQuery(rosterSource, sha(rosterSource))],
    [join(directory, 'holder-evidence-db-query-source.mjs'), verifiedQuery(querySource, sha(querySource))],
  ]);
  for (const text of snapshots.values()) assertStaticSource(text);
  const source = `import { inspectEmbeddedRoster } from './holder-evidence-db-roster-core.mjs';\n` +
    `const roles = Buffer.from(${JSON.stringify(roles.toString('base64'))}, 'base64');\n` +
    `const memberships = Buffer.from(${JSON.stringify(memberships.toString('base64'))}, 'base64');\n` +
    `const functions = Buffer.from(${JSON.stringify(functions.toString('base64'))}, 'base64');\n` +
    `const schemas = Buffer.from(${JSON.stringify(schemas.toString('base64'))}, 'base64');\n` +
    `const tables = Buffer.from(${JSON.stringify(tables.toString('base64'))}, 'base64');\n` +
    `const sessions = Buffer.from(${JSON.stringify(sessions.toString('base64'))}, 'base64');\n` +
    `const relation_acls = Buffer.from(${JSON.stringify(relationAcls.toString('base64'))}, 'base64');\n` +
    `const control_acls = Buffer.from(${JSON.stringify(controlAcls.toString('base64'))}, 'base64');\n` +
    `const policies = Buffer.from(${JSON.stringify(policies.toString('base64'))}, 'base64');\n` +
    `const triggers = Buffer.from(${JSON.stringify(triggers.toString('base64'))}, 'base64');\n` +
    `const sequences = Buffer.from(${JSON.stringify(sequences.toString('base64'))}, 'base64');\n` +
    `const materialized_views = Buffer.from(${JSON.stringify(materializedViews.toString('base64'))}, 'base64');\n` +
    `const sequence_acls = Buffer.from(${JSON.stringify(sequenceAcls.toString('base64'))}, 'base64');\n` +
    `export function inspectBundledRoster(db, pins, options) { return inspectEmbeddedRoster(db, { roles, memberships, functions, schemas, tables, sessions, relation_acls, control_acls, policies, triggers, sequences, materialized_views, sequence_acls }, pins, options, true); }\n`;
  const result = await build({ absWorkingDir: directory, stdin: { contents: source, resolveDir: directory, sourcefile: 'holder-query-entry.mjs', loader: 'js' },
    bundle: true, platform: 'node', format: 'esm', target: 'node22', write: false, metafile: true, outfile: 'holder-query-bundle.mjs', logLevel: 'silent',
    plugins: [{ name: 'snapshot-inputs', setup(builder) {
      builder.onLoad({ filter: /holder-evidence-db-(?:roster-core|query-source)\.mjs$/ }, (args) => {
        if (!snapshots.has(args.path)) throw new Error('bundle_scope');
        return { contents: snapshots.get(args.path), loader: 'js', resolveDir: directory };
      });
    } }] });
  const inputs = Object.keys(result.metafile.inputs);
  const externals = [...new Set(Object.values(result.metafile.outputs).flatMap((output) => output.imports.filter((item) => item.external).map((item) => item.path)))].sort();
  if (inputs.length !== allowedInputs.size || inputs.some((input) => !allowedInputs.has(input)) ||
      externals.length !== 2 || externals[0] !== 'node:crypto' || externals[1] !== 'node:util' || result.outputFiles.length !== 1) throw new Error('bundle_scope');
  const bytes = Buffer.from(result.outputFiles[0].contents);
  if (bytes.length < 1 || bytes.length > 4 * 1024 * 1024) throw new Error('bundle_size');
  return { scope: 'offline_query_bundle_only', bytes, bundle_sha256: sha(bytes), queries, external_imports: externals, writer_clearance: false };
}

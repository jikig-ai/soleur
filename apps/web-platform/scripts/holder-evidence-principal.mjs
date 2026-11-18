// Offline interpretation of supplied observations, not a principal attestation.
// Even a complete modeled input cannot prove the absence of unmodeled paths.
const oid = (n) => Number.isSafeInteger(n) && n > 0 && n <= 4294967295;
const nonemptyDense = (value, valid) => {
  try {
    if (!Array.isArray(value)) return false;
    const length=Object.getOwnPropertyDescriptor(value,'length')?.value;
    if (!Number.isInteger(length) || length < 1 || length > 1600) return false;
    for (let i=0;i<length;i++) {
      const descriptor=Object.getOwnPropertyDescriptor(value,String(i));
      if (!descriptor || !Object.hasOwn(descriptor,'value') || !valid(descriptor.value)) return false;
    }
    return true;
  } catch { return false; }
};
const strings = (value) => nonemptyDense(value, item => typeof item === 'string');
const columnNumbers = (value) => nonemptyDense(value, item => Number.isInteger(item) && item > 0 && item <= 32767);

export function assessPrincipal(input, principalOid) {
  const detected = [];
  const names = ['roles', 'memberships', 'schemas', 'tables', 'functions', 'sequences', 'materialized_views'];
  const arms = {};
  for (const name of names) {
    const arm = input?.[name];
    if (!arm || !['complete', 'partial'].includes(arm.state) || !Array.isArray(arm.rows)) { arms[name] = []; }
    else arms[name] = arm.rows;
  }
  const roleFields = ['superuser', 'bypass_rls', 'can_create_role', 'can_create_database', 'replication'];
  const validators = {
    roles: (r) => oid(r?.role_oid),
    memberships: (r) => oid(r?.member_oid) && oid(r?.role_oid),
    schemas: (r) => oid(r?.role_oid),
    tables: (r) => oid(r?.role_oid),
    functions: (r) => oid(r?.role_oid),
    sequences: (r) => oid(r?.role_oid),
    materialized_views: (r) => oid(r?.role_oid),
  };
  for (const name of names) arms[name] = arms[name].filter(validators[name]);
  const principals = arms.roles.filter((row) => row.role_oid === principalOid);
  if (principals.some((row) => roleFields.some((key) => row[key] === true))) detected.push('privileged_role');
  if (arms.memberships.some((row) => row.member_oid === principalOid && row.can_set_role === true)) detected.push('role_switch');
  if (arms.schemas.some((row) => row.role_oid === principalOid && (row.schema_create === true || row.database_create === true))) detected.push('schema_or_database_create');
  if (arms.tables.some((row) => row.role_oid === principalOid && (row.can_insert === true || row.can_update_table === true || row.can_delete === true || row.can_truncate === true ||
    strings(row.insertable_columns) || strings(row.updatable_columns) ||
    columnNumbers(row.insertable_column_numbers) || columnNumbers(row.updatable_column_numbers)))) detected.push('table_write');
  if (arms.functions.some((row) => row.role_oid === principalOid && row.security_definer === true && row.can_execute === true)) detected.push('security_definer_execute');
  if (arms.sequences.some((row) => row.role_oid === principalOid && (row.can_usage === true || row.can_update === true))) detected.push('sequence_write');
  if (arms.materialized_views.some((row) => row.role_oid === principalOid && row.can_maintain === true)) detected.push('materialized_maintain');
  // Arm status and cross-references cannot establish the expected target matrix.
  // Until that matrix is bound and checked, no input can establish coverage.
  return { modeled_coverage: 'unknown', detected, read_only: 'unknown', writer_clearance: false };
}

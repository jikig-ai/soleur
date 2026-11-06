import { verifiedQuery } from './holder-evidence-db-query-source.mjs';

// Query integrity only; this does not bind the executable or grant clearance.
// A timeout returns a failure but does not cancel or prove backend termination.
const failure = () => ({ state: 'failed', rows: [] });
const sessionFailure = () => ({ ...failure(), scope:'current_database_visible_rows', capped:'unknown', future_reconnects:'unknown', write_capability:'unknown', stats_freshness:'unknown' });
const wholeFailure = () => ({ roles: failure(), memberships: failure(), cross_reference: 'unknown', cross_reference_scope: 'returned_rows_only', backend_stop: 'unknown', holder_coverage: 'unknown', writer_clearance: false });
const roleFlags = ['can_login', 'superuser', 'bypass_rls', 'inherits_by_default', 'can_create_role', 'can_create_database', 'replication'];
const edgeFlags = ['admin_option', 'inherit_option', 'set_option', 'inherits_privileges', 'can_set_role'];
const oid = (value) => Number.isSafeInteger(value) && value > 0 && value <= 4294967295;
const unimplemented = () => ({});
const objectFailures = () => ({sequences:{...failure(),scope:'filtered_query_walk'},materialized_views:{...failure(),scope:'filtered_query_walk',maintain_support:'unknown'},sequence_acls:{...failure(),scope:'filtered_query_walk'},object_coverage:'unknown'});


function project(raw, kind) {
  if (kind === 'sequences' || kind === 'materialized_views') {
    const ids=['role_oid','schema_oid','object_oid','owner_oid'];
    const flags=kind==='sequences'?['schema_usage','can_usage','can_select','can_update']:['schema_usage','can_maintain'];
    const expected=kind==='sequences'?'sequence_privilege':'materialized_view_privilege';
    if (!raw || raw.kind!==expected || !ids.every(key=>oid(raw[key])) || !flags.every(key=>typeof raw[key]==='boolean')) throw new Error('shape');
    return Object.fromEntries([...ids,...flags].map(key=>[key,raw[key]]));
  }
  if (kind === 'sequence_acls') {
    const names=['schema_oid','sequence_oid','owner_oid','grantee_oid','grantor_oid','privilege','grantable'];
    if (!raw || raw.kind!=='sequence_acl' || !['schema_oid','sequence_oid','owner_oid','grantor_oid'].every(key=>oid(raw[key])) ||
        !(raw.grantee_oid===0 || oid(raw.grantee_oid)) || !['USAGE','SELECT','UPDATE'].includes(raw.privilege) || typeof raw.grantable!=='boolean') throw new Error('shape');
    return Object.fromEntries(names.map(key=>[key,raw[key]]));
  }
  if (kind === 'triggers') {
    const names=['trigger_oid','schema_oid','relation_oid','function_oid','function_owner_oid','trigger_type','enabled','internal','security_definer'];
    if (!raw || raw.kind!=='trigger' || !['trigger_oid','schema_oid','relation_oid','function_oid','function_owner_oid'].every(key=>oid(raw[key])) ||
        !Number.isInteger(raw.trigger_type) || raw.trigger_type<1 || raw.trigger_type>127 || (raw.trigger_type & 60)===0 || !['O','D','R','A'].includes(raw.enabled) ||
        typeof raw.internal!=='boolean' || typeof raw.security_definer!=='boolean') throw new Error('shape');
    return Object.fromEntries(names.map(key=>[key,raw[key]]));
  }
  if (kind === 'policies') {
    const names=['policy_oid','schema_oid','relation_oid','command','permissive','role_oids','has_using','has_check','policy_effect'];
    if (!raw || raw.kind!=='policy' || !['policy_oid','schema_oid','relation_oid'].every(key=>oid(raw[key])) ||
        !['*','r','a','w','d'].includes(raw.command) || typeof raw.permissive!=='boolean' ||
        !Array.isArray(raw.role_oids) || raw.role_oids.length<1 || raw.role_oids.length>1600 ||
        !raw.role_oids.every((n,i,a)=>(n===0 || oid(n)) && (i===0 || a[i-1]<n)) ||
        typeof raw.has_using!=='boolean' || typeof raw.has_check!=='boolean' || raw.policy_effect!=='unknown') throw new Error('shape');
    return Object.fromEntries(names.map(key=>[key,raw[key]]));
  }
  if (kind === 'control_acls') {
    const names=['scope','object_oid','owner_oid','grantee_oid','grantor_oid','privilege','grantable'];
    if (!raw || raw.kind!=='control_acl' || !['schema','database'].includes(raw.scope) || !oid(raw.object_oid) || !oid(raw.owner_oid) ||
        !(raw.grantee_oid===0 || oid(raw.grantee_oid)) || !oid(raw.grantor_oid) ||
        !(raw.scope==='schema' ? ['USAGE','CREATE'] : ['CREATE','CONNECT','TEMPORARY']).includes(raw.privilege) || typeof raw.grantable!=='boolean') throw new Error('shape');
    return Object.fromEntries(names.map(key=>[key,raw[key]]));
  }
  if (kind === 'relation_acls') {
    const names=['scope','schema_oid','relation_oid','column_number','grantee_oid','grantor_oid','privilege','grantable'];
    if (!raw || raw.kind!=='relation_acl' || !['table','column'].includes(raw.scope) || !oid(raw.schema_oid) || !oid(raw.relation_oid) ||
        (raw.scope==='table' ? raw.column_number!==null : !Number.isInteger(raw.column_number) || raw.column_number<1 || raw.column_number>32767) ||
        !(raw.grantee_oid===0 || oid(raw.grantee_oid)) || !oid(raw.grantor_oid) ||
        !(raw.scope==='column' ? ['SELECT','INSERT','UPDATE','REFERENCES'] : ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']).includes(raw.privilege) || typeof raw.grantable!=='boolean') throw new Error('shape');
    return Object.fromEntries(names.map(key=>[key,raw[key]]));
  }
  if (kind === 'sessions') {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('shape');
    if (raw.kind === 'session_summary') {
      if (!Number.isSafeInteger(raw.observed_count) || raw.observed_count < 0 || raw.observed_count > 257 ||
          typeof raw.capped !== 'boolean' || raw.capped !== (raw.observed_count === 257) ||
          !['restricted','full_stats_privilege'].includes(raw.visibility) || raw.future_reconnects !== 'unknown') throw new Error('shape');
      return {kind:'session_summary',observed_count:raw.observed_count,capped:raw.capped,visibility:raw.visibility};
    }
    if (raw.kind !== 'session') throw new Error('shape');
    if (!oid(raw.role_oid) || raw.application_class !== 'other' ||
        !['active','idle','idle in transaction','idle in transaction (aborted)','fastpath function call'].includes(raw.state_class) ||
        !['none_or_hidden','under_1m','1m_to_15m','15m_or_more'].includes(raw.transaction_age_bucket) || raw.write_capability !== 'unknown') return {kind:'session',partial:true};
    return {kind:'session',role_oid:raw.role_oid,application_class:'other',state_class:raw.state_class,transaction_age_bucket:raw.transaction_age_bucket,write_capability:'unknown'};
  }
  if (kind === 'tables') {
    const ids = ['role_oid','schema_oid','relation_oid','owner_oid'];
    const flags = ['rls_enabled','rls_forced','schema_usage','can_insert','can_update_table','can_delete','can_truncate'];
    const columns = ['insertable_column_numbers','updatable_column_numbers'];
    if (!raw || !ids.every(key => oid(raw[key])) || !['r','p','v','f'].includes(raw.relkind) ||
        !flags.every(key => typeof raw[key] === 'boolean') || !columns.every(key => Array.isArray(raw[key]) && raw[key].length <= 1600 &&
          raw[key].every((n,i,a) => Number.isInteger(n) && n > 0 && n <= 32767 && (i===0 || a[i-1]<n)))) throw new Error('shape');
    return Object.fromEntries([...ids,'relkind',...flags,...columns].map(key => [key,raw[key]]));
  }
  if (kind === 'schemas') {
    const ids = ['role_oid','schema_oid','owner_oid'];
    const flags = ['schema_usage','schema_create','database_connect','database_create','database_temporary'];
    if (!raw || raw.kind !== 'schema_privilege' || !ids.every(key => oid(raw[key])) ||
        !flags.every(key => typeof raw[key] === 'boolean')) throw new Error('shape');
    return Object.fromEntries([...ids,...flags].map(key => [key,raw[key]]));
  }
  if (kind === 'functions') {
    const ids = ['role_oid','schema_oid','function_oid','owner_oid'];
    const flags = ['security_definer','schema_usage','can_execute'];
    if (!raw || !ids.every(key => oid(raw[key])) || !['f','p'].includes(raw.prokind) ||
        !flags.every(key => typeof raw[key] === 'boolean')) throw new Error('shape');
    return Object.fromEntries([...ids,'prokind',...flags].map(key => [key,raw[key]]));
  }
  const keys = kind === 'roles' ? ['role_oid', ...roleFlags] : ['member_oid', 'role_oid', 'grantor_oid', ...edgeFlags];
  const idKeys = kind === 'roles' ? ['role_oid'] : ['member_oid', 'role_oid', 'grantor_oid'];
  const flags = kind === 'roles' ? roleFlags : edgeFlags;
  if (!raw || (kind === 'roles' && raw.kind !== 'role') || !idKeys.every((key) => oid(raw[key])) ||
      !flags.every((key) => typeof raw[key] === 'boolean')) throw new Error('shape');
  return Object.fromEntries(keys.map((key) => [key, raw[key]]));
}

export async function inspectEmbeddedRoster(database, bytes, expected, options = {}, includeExtended = false) {
  let timeoutMs, includeFunctions;
  const optionFailure = () => includeExtended === true ? { ...wholeFailure(), functions: { ...failure(), scope: 'filtered_query_walk' }, function_cross_reference: 'unknown', function_coverage: 'unknown', schemas: { ...failure(), scope: 'filtered_query_walk' }, schema_coverage: 'unknown', tables: { ...failure(), scope: 'filtered_query_walk' }, table_coverage: 'unknown', sessions: sessionFailure(), session_coverage:'unknown', relation_acls:{...failure(),scope:'filtered_query_walk'}, relation_acl_coverage:'unknown', control_acls:{...failure(),scope:'filtered_query_walk'}, control_acl_coverage:'unknown', policies:{...failure(),scope:'filtered_query_walk',effect:'unknown'}, policy_coverage:'unknown', triggers:{...failure(),scope:'filtered_query_walk',effect:'unknown'}, trigger_coverage:'unknown', ...objectFailures(), unimplemented_arms: unimplemented() } : wholeFailure();
  try {
    if (!options || typeof options !== 'object' || Array.isArray(options)) return optionFailure();
    const descriptors = Object.getOwnPropertyDescriptors(options);
    if (['timeoutMs','includeFunctions'].some(key => descriptors[key] && !Object.hasOwn(descriptors[key], 'value'))) return optionFailure();
    timeoutMs = descriptors.timeoutMs?.value ?? 15000;
    includeFunctions = includeExtended === true || descriptors.includeFunctions?.value === true;
  } catch { return optionFailure(); }
  const allFailed = () => ({ ...wholeFailure(), ...(includeFunctions ? { functions: { ...failure(), scope: 'filtered_query_walk' }, function_cross_reference: 'unknown', function_coverage: 'unknown' } : {}), ...(includeExtended === true ? { schemas: { ...failure(), scope: 'filtered_query_walk' }, schema_coverage: 'unknown', tables: { ...failure(), scope: 'filtered_query_walk' }, table_coverage: 'unknown', sessions: sessionFailure(), session_coverage:'unknown', relation_acls:{...failure(),scope:'filtered_query_walk'}, relation_acl_coverage:'unknown', control_acls:{...failure(),scope:'filtered_query_walk'}, control_acl_coverage:'unknown', policies:{...failure(),scope:'filtered_query_walk',effect:'unknown'}, policy_coverage:'unknown', triggers:{...failure(),scope:'filtered_query_walk',effect:'unknown'}, trigger_coverage:'unknown', ...objectFailures(), unimplemented_arms: unimplemented() } : {}) });
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) return allFailed();
  try {
    if (!bytes || !expected || typeof database?.begin !== 'function') return allFailed();
    const source = { roles: verifiedQuery(bytes.roles, expected.roles_sha256), memberships: verifiedQuery(bytes.memberships, expected.memberships_sha256) };
    if (includeFunctions) source.functions = verifiedQuery(bytes.functions, expected.functions_sha256);
    if (includeExtended === true) source.schemas = verifiedQuery(bytes.schemas, expected.schemas_sha256);
    if (includeExtended === true) source.tables = verifiedQuery(bytes.tables, expected.tables_sha256);
    if (includeExtended === true) source.sessions = verifiedQuery(bytes.sessions, expected.sessions_sha256);
    if (includeExtended === true) source.relation_acls = verifiedQuery(bytes.relation_acls, expected.relation_acls_sha256);
    if (includeExtended === true) source.control_acls = verifiedQuery(bytes.control_acls, expected.control_acls_sha256);
    if (includeExtended === true) source.policies = verifiedQuery(bytes.policies, expected.policies_sha256);
    if (includeExtended === true) source.triggers = verifiedQuery(bytes.triggers, expected.triggers_sha256);
    if (includeExtended === true) source.sequences = verifiedQuery(bytes.sequences, expected.sequences_sha256);
    if (includeExtended === true) source.materialized_views = verifiedQuery(bytes.materialized_views, expected.materialized_views_sha256);
    if (includeExtended === true) source.sequence_acls = verifiedQuery(bytes.sequence_acls, expected.sequence_acls_sha256);
    let expired = false;
    let timer;
    const deadlineAt = performance.now() + timeoutMs;
    const ensureActive = () => { if (expired || performance.now() >= deadlineAt) throw new Error('deadline'); };
    const deadline = new Promise((resolve) => { timer = setTimeout(() => { expired = true; resolve(allFailed()); }, timeoutMs); });
    const task = Promise.resolve().then(() => database.begin('isolation level repeatable read read only', async (tx) => {
      ensureActive();
      await tx.unsafe("SET LOCAL statement_timeout = '10s'; SET LOCAL lock_timeout = '1s'; SET LOCAL idle_in_transaction_session_timeout = '15s'; SET LOCAL search_path = pg_catalog, pg_temp");
      ensureActive();
      const state = await tx.unsafe("SELECT current_setting('transaction_read_only') AS read_only, current_setting('transaction_isolation') AS isolation, current_setting('search_path') AS search_path");
      ensureActive();
      if (!Array.isArray(state) || state.length !== 1 || state[0].read_only !== 'on' || state[0].isolation !== 'repeatable read' || state[0].search_path !== 'pg_catalog, pg_temp' || typeof tx.savepoint !== 'function') throw new Error('transaction');
      let bytes = 0;
      async function arm(kind) {
        try {
          return await tx.savepoint(async (sp) => {
            ensureActive();
            const rows = [];
            const seen = new Set();
            for await (const batch of sp.unsafe(source[kind]).cursor(1)) {
              ensureActive();
              if (!Array.isArray(batch) || batch.length !== 1 || typeof batch[0]?.row_to_json !== 'string') throw new Error('shape');
              const raw = batch[0].row_to_json;
              if (Buffer.byteLength(raw, 'utf8') > 4096) throw new Error('shape');
              if (kind === 'sessions' && rows.length >= 258) throw new Error('shape');
              if (rows.length >= 10000) return { state: 'partial', rows: [] };
              bytes += Buffer.byteLength(raw, 'utf8');
              if (bytes > 4 * 1024 * 1024) return kind === 'sessions' ? {state:'partial',rows:[],partial_reasons:['output_limit']} : { state: 'partial', rows: [] };
              const value = project(JSON.parse(raw), kind);
              if (kind === 'sessions') { rows.push(value); continue; }
              const key = kind === 'roles' ? String(value.role_oid) : kind === 'functions' ? `${value.role_oid}/${value.function_oid}` : kind === 'schemas' ? `${value.role_oid}/${value.schema_oid}` : kind === 'tables' ? `${value.role_oid}/${value.relation_oid}` : kind === 'relation_acls' ? `${value.scope}/${value.relation_oid}/${value.column_number}/${value.grantee_oid}/${value.grantor_oid}/${value.privilege}` : kind === 'control_acls' ? `${value.scope}/${value.object_oid}/${value.grantee_oid}/${value.grantor_oid}/${value.privilege}` : kind === 'policies' ? String(value.policy_oid) : kind === 'triggers' ? String(value.trigger_oid) : kind === 'sequences' || kind === 'materialized_views' ? `${value.role_oid}/${value.object_oid}` : kind === 'sequence_acls' ? `${value.sequence_oid}/${value.grantee_oid}/${value.grantor_oid}/${value.privilege}` : `${value.member_oid}/${value.role_oid}/${value.grantor_oid}`;
              if (seen.has(key)) throw new Error('duplicate');
              seen.add(key);
              rows.push(value);
            }
            ensureActive();
            if (kind === 'sessions') {
              const summaries=rows.filter(row=>row.kind==='session_summary'), sessions=rows.filter(row=>row.kind==='session');
              if (summaries.length!==1 || summaries[0].observed_count!==sessions.length) throw new Error('shape');
              const summary=summaries[0];
              const reasons=[...(summary.capped?['row_limit']:[]),...(summary.visibility==='restricted'?['restricted_visibility']:[]),...(sessions.some(row=>row.partial)?['unclassified_row']:[])];
              if (reasons.length) return {state:'partial',rows:[],observed_count:summary.observed_count,visibility:summary.visibility,capped:summary.capped,partial_reasons:reasons};
              return {state:'complete',rows:sessions,observed_count:summary.observed_count,visibility:summary.visibility,capped:false};
            }
            return { state: 'complete', rows };
          });
        } catch { return failure(); }
      }
      const roles = await arm('roles');
      ensureActive();
      const memberships = await arm('memberships');
      ensureActive();
      const functions = includeFunctions ? { ...await arm('functions'), scope: 'filtered_query_walk' } : null;
      ensureActive();
      const schemas = includeExtended === true ? { ...await arm('schemas'), scope: 'filtered_query_walk' } : null;
      ensureActive();
      const tables = includeExtended === true ? { ...await arm('tables'), scope: 'filtered_query_walk' } : null;
      ensureActive();
      const sessions = includeExtended === true ? { capped:'unknown', ...await arm('sessions'), scope:'current_database_visible_rows', future_reconnects:'unknown', write_capability:'unknown', stats_freshness:'unknown' } : null;
      ensureActive();
      const relation_acls = includeExtended === true ? { ...await arm('relation_acls'),scope:'filtered_query_walk' } : null;
      ensureActive();
      const control_acls = includeExtended === true ? { ...await arm('control_acls'),scope:'filtered_query_walk' } : null;
      ensureActive();
      const policies = includeExtended === true ? { ...await arm('policies'),scope:'filtered_query_walk',effect:'unknown' } : null;
      ensureActive();
      const triggers = includeExtended === true ? { ...await arm('triggers'),scope:'filtered_query_walk',effect:'unknown' } : null;
      ensureActive();
      const sequences = includeExtended === true ? { ...await arm('sequences'),scope:'filtered_query_walk' } : null;
      ensureActive();
      const materialized_views = includeExtended === true ? { ...await arm('materialized_views'),scope:'filtered_query_walk',maintain_support:'unknown' } : null;
      ensureActive();
      const sequence_acls = includeExtended === true ? { ...await arm('sequence_acls'),scope:'filtered_query_walk' } : null;
      ensureActive();
      const ids = new Set(roles.rows.map((role) => role.role_oid));
      const consistent = roles.state === 'complete' && memberships.state === 'complete' &&
        memberships.rows.every((edge) => ids.has(edge.member_oid) && ids.has(edge.role_oid) && ids.has(edge.grantor_oid));
      // A successful cursor walk does not independently enumerate functions or
      // prove every role/function pair; omitted rows cannot establish coverage.
      return { roles, memberships, ...(includeFunctions ? { functions, function_cross_reference: 'unknown', function_coverage: 'unknown' } : {}), ...(includeExtended === true ? { schemas, schema_coverage: 'unknown', tables, table_coverage: 'unknown', sessions, session_coverage:'unknown', relation_acls, relation_acl_coverage:'unknown', control_acls, control_acl_coverage:'unknown', policies, policy_coverage:'unknown', triggers, trigger_coverage:'unknown', sequences, materialized_views, sequence_acls, object_coverage:'unknown', unimplemented_arms: unimplemented() } : {}),
        cross_reference: consistent ? 'consistent' : 'unknown', cross_reference_scope: 'returned_rows_only', role_names: 'omitted', backend_stop:'unknown', holder_coverage: 'unknown', writer_clearance: false };
    }));
    try { return await Promise.race([task, deadline]); }
    finally { expired = true; clearTimeout(timer); }
  } catch { return allFailed(); }
}

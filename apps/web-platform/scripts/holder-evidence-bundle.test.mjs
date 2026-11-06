import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { appendFile, copyFile, mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { assertStaticSource, buildQueryBundle } from './holder-evidence-bundle.mjs';

test('dynamic imports and obvious runtime code loaders are refused by source inspection', () => {
  for (const source of ['if (globalThis.x) import(globalThis.x);', "import('node:fs');",
    "require('node:fs');", "eval('1');", "new Function('return 1');"]) {
    assert.throws(() => assertStaticSource(source));
  }
  assert.doesNotThrow(() => assertStaticSource("// import(x)\nexport const name = 'require';"));
});

test('the real builder refuses a computed import in its source snapshot', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'synthetic-query-bundle-'));
  try {
    for (const name of ['holder-evidence-bundle.mjs', 'holder-evidence-db-local-source.mjs',
      'holder-evidence-db-query-source.mjs', 'holder-evidence-db-roster-core.mjs',
      'holder-evidence-db-roles-projected.sql', 'holder-evidence-db-memberships-projected.sql', 'holder-evidence-db-functions-projected.sql', 'holder-evidence-db-schemas-projected.sql', 'holder-evidence-db-tables-projected.sql', 'holder-evidence-db-sessions-projected.sql', 'holder-evidence-db-acls-projected.sql', 'holder-evidence-db-control-acls-projected.sql', 'holder-evidence-db-policies-projected.sql', 'holder-evidence-db-triggers-projected.sql', 'holder-evidence-db-sequences-projected.sql', 'holder-evidence-db-materialized-projected.sql', 'holder-evidence-db-sequence-acls-projected.sql']) {
      await copyFile(new URL(`./${name}`, import.meta.url), join(directory, name));
    }
    await symlink(fileURLToPath(new URL('../node_modules', import.meta.url)), join(directory, 'node_modules'), 'dir');
    const isolated = await import(pathToFileURL(join(directory, 'holder-evidence-bundle.mjs')).href);
    assert.equal((await isolated.buildQueryBundle()).scope, 'offline_query_bundle_only');
    await appendFile(join(directory, 'holder-evidence-db-roster-core.mjs'), '\nif (globalThis.x) import(globalThis.x);\n');
    await assert.rejects(isolated.buildQueryBundle(), /bundle_source/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('offline bundle binds role and membership SQL and its executable bytes', async () => {
  const first = await buildQueryBundle();
  const second = await buildQueryBundle();
  assert.equal(first.scope, 'offline_query_bundle_only');
  assert.equal(first.writer_clearance, false);
  assert.equal(first.bundle_sha256, createHash('sha256').update(first.bytes).digest('hex'));
  assert.equal(first.bundle_sha256, second.bundle_sha256);
  const roles = await readFile(new URL('./holder-evidence-db-roles-projected.sql', import.meta.url));
  const memberships = await readFile(new URL('./holder-evidence-db-memberships-projected.sql', import.meta.url));
  const functions = await readFile(new URL('./holder-evidence-db-functions-projected.sql', import.meta.url));
  const schemas = await readFile(new URL('./holder-evidence-db-schemas-projected.sql', import.meta.url));
  const tables = await readFile(new URL('./holder-evidence-db-tables-projected.sql', import.meta.url));
  const sessions = await readFile(new URL('./holder-evidence-db-sessions-projected.sql', import.meta.url));
  const acls = await readFile(new URL('./holder-evidence-db-acls-projected.sql', import.meta.url));
  const controlAcls = await readFile(new URL('./holder-evidence-db-control-acls-projected.sql', import.meta.url));
  const policies = await readFile(new URL('./holder-evidence-db-policies-projected.sql', import.meta.url));
  const triggers = await readFile(new URL('./holder-evidence-db-triggers-projected.sql', import.meta.url));
  const sequences = await readFile(new URL('./holder-evidence-db-sequences-projected.sql', import.meta.url));
  const materialized = await readFile(new URL('./holder-evidence-db-materialized-projected.sql', import.meta.url));
  const sequenceAcls = await readFile(new URL('./holder-evidence-db-sequence-acls-projected.sql', import.meta.url));
  assert.equal(first.queries.roles_sha256, createHash('sha256').update(roles).digest('hex'));
  assert.equal(first.queries.memberships_sha256, createHash('sha256').update(memberships).digest('hex'));
  assert.equal(first.queries.functions_sha256, createHash('sha256').update(functions).digest('hex'));
  assert.equal(first.queries.schemas_sha256, createHash('sha256').update(schemas).digest('hex'));
  assert.equal(first.queries.tables_sha256, createHash('sha256').update(tables).digest('hex'));
  assert.equal(first.queries.sessions_sha256, createHash('sha256').update(sessions).digest('hex'));
  assert.equal(first.queries.relation_acls_sha256, createHash('sha256').update(acls).digest('hex'));
  assert.equal(first.queries.control_acls_sha256, createHash('sha256').update(controlAcls).digest('hex'));
  assert.equal(first.queries.policies_sha256, createHash('sha256').update(policies).digest('hex'));
  assert.equal(first.queries.triggers_sha256, createHash('sha256').update(triggers).digest('hex'));
  assert.equal(first.queries.sequences_sha256, createHash('sha256').update(sequences).digest('hex'));
  assert.equal(first.queries.materialized_views_sha256, createHash('sha256').update(materialized).digest('hex'));
  assert.equal(first.queries.sequence_acls_sha256, createHash('sha256').update(sequenceAcls).digest('hex'));
  assert.deepEqual(first.external_imports, ['node:crypto', 'node:util']);
});

test('bundled runner refuses wrong query pins before using the adapter', async () => {
  const bundle = await buildQueryBundle();
  const module = await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  let calls = 0;
  const db = { async begin() { calls++; throw new Error('private'); } };
  const result = await module.inspectBundledRoster(db, { ...bundle.queries, memberships_sha256: '0'.repeat(64) });
  assert.equal(result.roles.state, 'failed');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.equal(result.backend_stop, 'unknown');
  assert.equal(calls, 0);
  const functions = await module.inspectBundledRoster(db, { ...bundle.queries, functions_sha256: '0'.repeat(64) });
  assert.equal(functions.functions.state,'failed');
  assert.equal(calls,0);
  const schemas = await module.inspectBundledRoster(db, { ...bundle.queries, schemas_sha256: '0'.repeat(64) });
  assert.equal(schemas.schemas.state,'failed');
  assert.equal(calls,0);
  const tables = await module.inspectBundledRoster(db, { ...bundle.queries, tables_sha256: '0'.repeat(64) });
  assert.equal(tables.tables.state,'failed');
  assert.equal(calls,0);
  const sessions = await module.inspectBundledRoster(db, { ...bundle.queries, sessions_sha256: '0'.repeat(64) });
  assert.equal(sessions.sessions.state,'failed');
  assert.equal(sessions.sessions.future_reconnects,'unknown');
  assert.equal(sessions.sessions.write_capability,'unknown');
  assert.equal(sessions.sessions.stats_freshness,'unknown');
  assert.equal(sessions.session_coverage,'unknown');
  assert.deepEqual(sessions.unimplemented_arms,{});
  assert.equal(calls,0);
  const control = await module.inspectBundledRoster(db, { ...bundle.queries, control_acls_sha256: '0'.repeat(64) });
  assert.equal(control.control_acls.state,'failed');
  assert.equal(control.control_acl_coverage,'unknown');
  assert.equal(calls,0);
  const policies = await module.inspectBundledRoster(db, { ...bundle.queries, policies_sha256: '0'.repeat(64) });
  assert.equal(policies.policies.state,'failed');
  assert.equal(policies.policies.effect,'unknown');
  assert.equal(calls,0);
  for (const arm of ['triggers','sequences','materialized_views','sequence_acls']) {
    const rejected=await module.inspectBundledRoster(db,{...bundle.queries,[`${arm}_sha256`]:'0'.repeat(64)});
    assert.equal(rejected[arm].state,'failed');
    assert.equal(calls,0);
  }
});

test('bundled runner executes thirteen embedded query snapshots through the adapter', async () => {
  const bundle = await buildQueryBundle();
  const module = await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const queries = [];
  const tx = {
    async savepoint(callback) { return callback(tx); },
    unsafe(sql) {
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{ read_only: 'on', isolation: 'repeatable read', search_path: 'pg_catalog, pg_temp' }]);
      queries.push(sql);
      return { cursor() { return { async *[Symbol.asyncIterator]() {} }; } };
    },
  };
  const db = { async begin(_mode, callback) { return callback(tx); } };
  const result = await module.inspectBundledRoster(db, bundle.queries);
  assert.equal(result.cross_reference, 'consistent');
  assert.equal(result.functions.state, 'complete');
  assert.equal(result.functions.scope, 'filtered_query_walk');
  assert.equal(result.function_cross_reference, 'unknown');
  assert.equal(result.function_coverage, 'unknown');
  assert.equal(result.schemas.state, 'complete');
  assert.equal(result.schemas.scope, 'filtered_query_walk');
  assert.equal(result.schema_coverage, 'unknown');
  assert.equal(result.tables.state, 'complete');
  assert.equal(result.table_coverage, 'unknown');
  assert.equal(result.sessions.state,'failed'); // This mock supplied no required summary.
  assert.equal(result.session_coverage,'unknown');
  assert.equal(result.relation_acls.state,'complete');
  assert.equal(result.relation_acl_coverage,'unknown');
  assert.equal(result.control_acls.state,'complete');
  assert.equal(result.control_acl_coverage,'unknown');
  assert.equal(result.policies.state,'complete');
  assert.equal(result.policy_coverage,'unknown');
  assert.equal(result.triggers.state,'complete');
  assert.equal(result.trigger_coverage,'unknown');
  for (const arm of ['sequences','materialized_views','sequence_acls']) assert.equal(result[arm].state,'complete');
  assert.equal(result.materialized_views.maintain_support,'unknown');
  assert.deepEqual(result.unimplemented_arms,{});
  assert.equal(result.object_coverage,'unknown');
  assert.equal(result.writer_clearance, false);
  assert.deepEqual(queries, [await readFile(new URL('./holder-evidence-db-roles-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-memberships-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-functions-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-schemas-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-tables-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-sessions-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-acls-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-control-acls-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-policies-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-triggers-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-sequences-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-materialized-projected.sql', import.meta.url), 'utf8'),
    await readFile(new URL('./holder-evidence-db-sequence-acls-projected.sql', import.meta.url), 'utf8')]);
});

test('function-arm failure is isolated and function names are not returned', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const functionRow={role_oid:1,schema_oid:2,function_oid:3,owner_oid:1,prokind:'f',security_definer:true,schema_usage:true,can_execute:false,role_name:'private-role',function_name:'private-function'};
  for (const fail of [false,true]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      if (sql.includes('CROSS JOIN pg_catalog.pg_proc p')) {
        if (fail) throw Error('private-error');
        return {cursor(){return {async *[Symbol.asyncIterator](){yield [{row_to_json:JSON.stringify(functionRow)}];}};}};
      }
      return {cursor(){return {async *[Symbol.asyncIterator](){}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.roles.state,'complete');
    assert.equal(result.memberships.state,'complete');
    assert.equal(result.functions.state,fail?'failed':'complete');
    assert.equal(result.function_cross_reference,'unknown');
    assert.equal(JSON.stringify(result).includes('private'),false);
    assert.equal(result.writer_clearance,false);
  }
});

test('function duplicates, malformed rows, row cap and shared byte cap fail closed', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={role_oid:1,schema_oid:2,function_oid:3,owner_oid:1,prokind:'f',security_definer:true,schema_usage:true,can_execute:false};
  for (const [items,expected] of [
    [[row,row],'failed'],
    [[{...row,can_execute:'yes'}],'failed'],
    [Array.from({length:10001},(_,i)=>({...row,function_oid:i+1})),'partial'],
    [Array.from({length:1500},(_,i)=>({...row,function_oid:i+1,padding:'x'.repeat(3000)})),'partial'],
  ]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('CROSS JOIN pg_catalog.pg_proc p')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.functions.state,expected);
    assert.deepEqual(result.functions.rows,[]);
    assert.equal(result.functions.scope,'filtered_query_walk');
    assert.equal(result.function_coverage,'unknown');
  }
});

test('bad bundle options return an explicit failed function arm', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  let calls=0;
  const result=await module.inspectBundledRoster({begin(){calls++;}},bundle.queries,{get timeoutMs(){throw Error('private');}});
  assert.equal(result.functions.state,'failed');
  assert.equal(result.function_coverage,'unknown');
  assert.equal(result.sessions.state,'failed');
  assert.equal(result.sessions.future_reconnects,'unknown');
  assert.equal(result.sessions.write_capability,'unknown');
  assert.equal(result.sessions.stats_freshness,'unknown');
  assert.deepEqual(result.unimplemented_arms,{});
  assert.equal(calls,0);
  assert.equal(JSON.stringify(result).includes('private'),false);
});

test('schema arm strips extra names, rejects duplicate or malformed entries and records partial limits', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={kind:'schema_privilege',role_oid:1,schema_oid:2,owner_oid:1,schema_usage:true,schema_create:false,database_connect:true,database_create:false,database_temporary:true,schema_name:'private-schema'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,database_create:'yes'}],'failed'],[Array.from({length:10001},(_,i)=>({...row,schema_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('CROSS JOIN pg_catalog.pg_database d')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.schemas.state,expected);
    assert.equal(result.schema_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-schema'),false);
    if (expected!=='complete') assert.deepEqual(result.schemas.rows,[]);
  }
});

test('table arm rejects malformed column identifiers and preserves unknown coverage', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={role_oid:1,schema_oid:2,relation_oid:3,owner_oid:1,relkind:'r',rls_enabled:false,rls_forced:false,schema_usage:true,can_insert:false,can_update_table:false,can_delete:false,can_truncate:false,insertable_column_numbers:[2],updatable_column_numbers:[],relation:'private-table'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,insertable_column_numbers:[2,2]}],'failed'],[[{...row,updatable_column_numbers:['private-column']}],'failed'],[[{...row,insertable_column_numbers:Array.from({length:1600},(_,i)=>i+1)}],'failed'],[Array.from({length:10001},(_,i)=>({...row,relation_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('AS insertable_column_numbers')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.tables.state,expected);
    assert.equal(result.table_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-table'),false);
    if (expected!=='complete') assert.deepEqual(result.tables.rows,[]);
  }
});

test('session arm refuses incomplete summaries and limits restricted visibility', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const session={kind:'session',role_oid:1,application_class:'other',state_class:'active',transaction_age_bucket:'under_1m',write_capability:'unknown',role_name:'private'};
  const summary=(observed_count,capped,visibility)=>({kind:'session_summary',observed_count,capped,visibility,future_reconnects:'unknown'});
  const cases=[[[summary(1,false,'full_stats_privilege'),session],'complete'],[[session,summary(1,false,'full_stats_privilege')],'complete'],[[summary(1,false,'restricted'),session],'partial'],
    [[summary(2,false,'full_stats_privilege'),session],'failed'],[[session],'failed'],
    [[summary(1,false,'full_stats_privilege'),summary(1,false,'full_stats_privilege'),session],'failed'],
    [[summary(258,true,'full_stats_privilege'),...Array(258).fill(session)],'failed'],
    [[summary(1,false,'full_stats_privilege'),{...session,state_class:'unknown'}],'partial'],
    [[summary(1,false,'full_stats_privilege'),{...session,role_oid:null}],'partial'],
    [[summary(257,true,'full_stats_privilege'),...Array(257).fill(session)],'partial']];
  for (const [items,expected] of cases) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('FROM pg_catalog.pg_stat_activity')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.sessions.state,expected);
    if (expected==='partial' && items[0]?.capped===true) assert.equal(result.sessions.capped,true);
    if (expected==='partial' && items[0]?.capped===true) assert.ok(result.sessions.partial_reasons.includes('row_limit'));
    if (expected==='partial' && items[0]?.visibility==='restricted') assert.ok(result.sessions.partial_reasons.includes('restricted_visibility'));
    assert.equal(result.session_coverage,'unknown');
    assert.equal(result.sessions.stats_freshness,'unknown');
    assert.equal(result.backend_stop,'unknown');
    assert.equal(result.writer_clearance,false);
    assert.equal(JSON.stringify(result).includes('private'),false);
    if (expected!=='complete') assert.deepEqual(result.sessions.rows,[]);
  }
});

test('transaction failure and deadline retain all explicit session unknowns', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  for (const db of [{begin(){throw Error('private');}},{begin(){return new Promise(()=>{});}}]) {
    const result=await module.inspectBundledRoster(db,bundle.queries,{timeoutMs:10});
    assert.equal(result.sessions.state,'failed');
    assert.equal(result.sessions.future_reconnects,'unknown');
    assert.equal(result.sessions.write_capability,'unknown');
    assert.equal(result.sessions.stats_freshness,'unknown');
    assert.deepEqual(result.unimplemented_arms,{});
    assert.equal(JSON.stringify(result).includes('private'),false);
  }
});

test('relation ACL projection validates PUBLIC, column scope, duplicates and limits', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={kind:'relation_acl',scope:'table',schema_oid:1,relation_oid:2,column_number:null,grantee_oid:0,grantor_oid:3,privilege:'SELECT',grantable:false,relation:'private-name'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,scope:'column',column_number:null}],'failed'],[[{...row,privilege:'private'}],'failed'],
    ...['DELETE','TRUNCATE','TRIGGER','MAINTAIN'].map(privilege=>[[{...row,scope:'column',column_number:2,privilege}],'failed']),
    [Array.from({length:10001},(_,i)=>({...row,relation_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes("'relation_acl' AS kind")?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.relation_acls.state,expected);
    assert.equal(result.relation_acl_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-name'),false);
    if (expected!=='complete') assert.deepEqual(result.relation_acls.rows,[]);
  }
});

test('control ACL projection validates scope-specific permissions and drops names', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={kind:'control_acl',scope:'schema',object_oid:1,owner_oid:2,grantee_oid:0,grantor_oid:2,privilege:'USAGE',grantable:false,object_name:'private-schema'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,scope:'schema',privilege:'CONNECT'}],'failed'],[[{...row,scope:'database',privilege:'USAGE'}],'failed'],[Array.from({length:10001},(_,i)=>({...row,object_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes("'control_acl' AS kind")?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.control_acls.state,expected);
    assert.equal(result.control_acl_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-schema'),false);
    if (expected!=='complete') assert.deepEqual(result.control_acls.rows,[]);
  }
});

test('policy metadata strips names and never asserts policy effects', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={kind:'policy',policy_oid:1,schema_oid:2,relation_oid:3,command:'r',permissive:true,role_oids:[0],has_using:true,has_check:false,policy_effect:'unknown',policy_name:'private-policy'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,command:'bad'}],'failed'],[[{...row,policy_effect:'allow'}],'failed'],[[{...row,role_oids:[1,1]}],'failed'],[[{...row,role_oids:Array(1601).fill(0)}],'failed'],[Array.from({length:10001},(_,i)=>({...row,policy_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('FROM pg_catalog.pg_policy p')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.policies.state,expected);
    assert.equal(result.policy_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-policy'),false);
    if (expected!=='complete') assert.deepEqual(result.policies.rows,[]);
  }
});

test('trigger metadata rejects malformed modes and never asserts body effects', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const row={kind:'trigger',trigger_oid:1,schema_oid:2,relation_oid:3,function_oid:4,function_owner_oid:5,trigger_type:7,enabled:'O',internal:false,security_definer:false,trigger_name:'private-trigger'};
  for (const [items,expected] of [[[row],'complete'],[[row,row],'failed'],[[{...row,enabled:'private'}],'failed'],[[{...row,trigger_type:128}],'failed'],[[{...row,trigger_type:1}],'failed'],[[{...row,trigger_type:3}],'failed'],[[{...row,security_definer:'true'}],'failed'],[Array.from({length:10001},(_,i)=>({...row,trigger_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const selected=sql.includes('FROM pg_catalog.pg_trigger t')?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result.triggers.state,expected);
    assert.equal(result.triggers.effect,'unknown');
    assert.equal(result.trigger_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private-trigger'),false);
    if (expected!=='complete') assert.deepEqual(result.triggers.rows,[]);
  }
});

test('object arms validate independent permissions without emitting names', async () => {
  const bundle=await buildQueryBundle();
  const module=await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const sequence={kind:'sequence_privilege',role_oid:1,schema_oid:2,object_oid:3,owner_oid:1,schema_usage:true,can_usage:true,can_select:false,can_update:false,object_name:'private'};
  const view={kind:'materialized_view_privilege',role_oid:1,schema_oid:2,object_oid:4,owner_oid:1,schema_usage:true,can_maintain:true,object_name:'private'};
  const acl={kind:'sequence_acl',schema_oid:2,sequence_oid:3,owner_oid:1,grantee_oid:0,grantor_oid:1,privilege:'USAGE',grantable:false,object_name:'private'};
  for (const [arm,items,expected] of [['sequences',[sequence],'complete'],['materialized_views',[view],'complete'],['sequence_acls',[acl],'complete'],
    ['sequences',[{...sequence,can_usage:'true'}],'failed'],['materialized_views',[{...view,can_maintain:'true'}],'failed'],['sequence_acls',[{...acl,privilege:'DELETE'}],'failed'],
    ['sequences',[sequence,sequence],'failed'],['materialized_views',[view,view],'failed'],['sequence_acls',[acl,acl],'failed'],
    ['sequences',Array.from({length:10001},(_,i)=>({...sequence,object_oid:i+1})),'partial'],
    ['materialized_views',Array.from({length:10001},(_,i)=>({...view,object_oid:i+1})),'partial'],
    ['sequence_acls',Array.from({length:10001},(_,i)=>({...acl,sequence_oid:i+1})),'partial']]) {
    const tx={async savepoint(callback){return callback(tx);},unsafe(sql){
      if (sql.startsWith('SET LOCAL')) return Promise.resolve([]);
      if (sql.startsWith('SELECT current_setting')) return Promise.resolve([{read_only:'on',isolation:'repeatable read',search_path:'pg_catalog, pg_temp'}]);
      const marker=arm==='sequences'?"'sequence_privilege' AS kind":arm==='materialized_views'?"'materialized_view_privilege' AS kind":"'sequence_acl' AS kind";
      const selected=sql.includes(marker)?items:[];
      return {cursor(){return {async *[Symbol.asyncIterator](){for (const item of selected) yield [{row_to_json:JSON.stringify(item)}];}};}};
    }};
    const result=await module.inspectBundledRoster({begin:async (_mode,fn)=>fn(tx)},bundle.queries);
    assert.equal(result[arm].state,expected);
    assert.equal(result.object_coverage,'unknown');
    assert.equal(JSON.stringify(result).includes('private'),false);
    if (expected!=='complete') assert.deepEqual(result[arm].rows,[]);
  }
});

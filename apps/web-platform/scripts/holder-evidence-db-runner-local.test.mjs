// Called only by the disposable local PostgreSQL fixture.
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import postgres from '../node_modules/postgres/src/index.js';
import { readLocalRoleBindings, inspectBoundRoles } from './holder-evidence-db-runner.mjs';
import { readLocalRosterBindings, inspectBoundRoster } from './holder-evidence-db-roster.mjs';
import { buildQueryBundle } from './holder-evidence-bundle.mjs';
import { createFixtureSocket } from './holder-evidence-test-docker-socket.mjs';
import { trackInspectionTransaction } from './holder-evidence-transaction-tracker.mjs';

const databaseName = process.env.SYNTHETIC_DB;
assert.match(databaseName ?? '', /^holder_evidence_test_[0-9]+$/);
const password = process.env.SYNTHETIC_PASSWORD;
assert.match(password ?? '', /^[a-f0-9]{48}$/);
const fixture = { id: process.env.SYNTHETIC_CONTAINER_ID, image: process.env.SYNTHETIC_CONTAINER_IMAGE,
  marker: process.env.SYNTHETIC_CONTAINER_MARKER, password };
const socket = () => createFixtureSocket(fixture);
const database = postgres({ host: '127.0.0.1', port: 5432, socket, database: databaseName,
  username: 'postgres', password, max: 1, connect_timeout: 5 });
try {
  await database.unsafe("CREATE FUNCTION public.current_setting(text) RETURNS text LANGUAGE sql AS $$ SELECT 'synthetic-spoof'::text $$");
  await database.unsafe('CREATE ROLE synthetic_fn_allowed NOLOGIN; CREATE ROLE synthetic_fn_denied NOLOGIN; CREATE ROLE synthetic_fn_child NOLOGIN INHERIT; GRANT synthetic_fn_allowed TO synthetic_fn_child');
  await database.unsafe('CREATE SCHEMA synthetic_private; REVOKE ALL ON SCHEMA synthetic_private FROM PUBLIC; GRANT USAGE ON SCHEMA synthetic_private TO PUBLIC; GRANT CREATE ON SCHEMA synthetic_private TO synthetic_fn_allowed');
  await database.unsafe('CREATE SCHEMA synthetic_restricted; REVOKE ALL ON SCHEMA synthetic_restricted FROM PUBLIC');
  await database.unsafe(`REVOKE ALL ON DATABASE "${databaseName}" FROM PUBLIC; GRANT CONNECT, CREATE ON DATABASE "${databaseName}" TO synthetic_fn_allowed; GRANT TEMPORARY ON DATABASE "${databaseName}" TO synthetic_fn_denied`);
  await database.unsafe('CREATE TABLE public.synthetic_columns (id integer, private_value text, public_value text); GRANT INSERT (private_value) ON public.synthetic_columns TO synthetic_fn_allowed; GRANT UPDATE (public_value) ON public.synthetic_columns TO synthetic_fn_denied; GRANT SELECT ON public.synthetic_columns TO PUBLIC');
  await database.unsafe('ALTER TABLE public.synthetic_columns ENABLE ROW LEVEL SECURITY; CREATE POLICY synthetic_read ON public.synthetic_columns FOR SELECT TO PUBLIC USING (true)');
  await database.unsafe('CREATE POLICY synthetic_write ON public.synthetic_columns AS RESTRICTIVE FOR UPDATE TO synthetic_fn_allowed, synthetic_fn_denied USING (true) WITH CHECK (public_value IS NOT NULL)');
  await database.unsafe('CREATE FUNCTION public.synthetic_trigger_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$; CREATE TRIGGER synthetic_trigger BEFORE INSERT ON public.synthetic_columns FOR EACH ROW EXECUTE FUNCTION public.synthetic_trigger_fn()');
  await database.unsafe('CREATE SEQUENCE public.synthetic_sequence; GRANT USAGE ON SEQUENCE public.synthetic_sequence TO synthetic_fn_allowed; GRANT SELECT ON SEQUENCE public.synthetic_sequence TO PUBLIC; CREATE MATERIALIZED VIEW public.synthetic_materialized AS SELECT 1 AS value; GRANT MAINTAIN ON TABLE public.synthetic_materialized TO synthetic_fn_allowed');
  await database.unsafe('CREATE FUNCTION public.synthetic_definer() RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$ SELECT 1 $$');
  await database.unsafe('CREATE FUNCTION synthetic_restricted.synthetic_definer() RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$ SELECT 1 $$');
  await database.unsafe('REVOKE ALL ON FUNCTION synthetic_restricted.synthetic_definer() FROM PUBLIC; GRANT EXECUTE ON FUNCTION synthetic_restricted.synthetic_definer() TO synthetic_fn_denied');
  await database.unsafe('REVOKE ALL ON FUNCTION public.synthetic_definer() FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.synthetic_definer() TO synthetic_fn_allowed');
  await database.unsafe('SET search_path = public, pg_catalog');
  const result = await inspectBoundRoles(database, await readLocalRoleBindings());
  assert.equal(result.state, 'complete');
  assert.ok(result.observed_count > 0);
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  const roster = await inspectBoundRoster(database, await readLocalRosterBindings());
  assert.equal(roster.roles.state, 'complete');
  assert.equal(roster.memberships.state, 'complete');
  assert.equal(roster.cross_reference, 'consistent');
  assert.equal(roster.holder_coverage, 'unknown');
  assert.equal(roster.writer_clearance, false);
  const bundle = await buildQueryBundle();
  for (const filename of ['holder-evidence-db-roles-projected.sql','holder-evidence-db-memberships-projected.sql']) {
    const query=await readFile(new URL(`./${filename}`,import.meta.url),'utf8');
    const rawRows=await database.unsafe(query);
    assert.ok(rawRows.length>0);
    for (const raw of rawRows) {
      const value=JSON.parse(raw.row_to_json);
      for (const forbidden of ['role_name','member_name','grantor_name','rolname']) assert.equal(Object.hasOwn(value,forbidden),false);
      assert.equal(JSON.stringify(value).includes('synthetic_fn_allowed'),false);
    }
  }
  const bundled = await import(`data:text/javascript;base64,${bundle.bytes.toString('base64')}`);
  const bundledRoster = await bundled.inspectBundledRoster(database, bundle.queries);
  assert.equal(bundledRoster.roles.state, 'complete');
  assert.equal(bundledRoster.memberships.state, 'complete');
  assert.equal(bundledRoster.functions.state, 'complete');
  assert.equal(bundledRoster.functions.scope, 'filtered_query_walk');
  assert.equal(bundledRoster.function_coverage, 'unknown');
  assert.equal(bundledRoster.schemas.state, 'complete');
  assert.equal(bundledRoster.schema_coverage, 'unknown');
  assert.equal(bundledRoster.tables.state, 'complete');
  assert.equal(bundledRoster.table_coverage, 'unknown');
  assert.equal(bundledRoster.sessions.state, 'complete');
  assert.equal(bundledRoster.sessions.scope, 'current_database_visible_rows');
  assert.ok(bundledRoster.sessions.observed_count >= 1);
  assert.equal(bundledRoster.sessions.future_reconnects, 'unknown');
  assert.equal(bundledRoster.sessions.write_capability, 'unknown');
  assert.equal(bundledRoster.session_coverage, 'unknown');
  assert.equal(bundledRoster.relation_acls.state, 'complete');
  assert.equal(bundledRoster.relation_acl_coverage, 'unknown');
  assert.equal(bundledRoster.control_acls.state, 'complete');
  assert.equal(bundledRoster.control_acl_coverage, 'unknown');
  assert.equal(bundledRoster.policies.state, 'complete');
  assert.equal(bundledRoster.policy_coverage, 'unknown');
  assert.equal(bundledRoster.triggers.state, 'complete');
  assert.equal(bundledRoster.trigger_coverage, 'unknown');
  assert.equal(bundledRoster.sequences.state, 'complete');
  assert.equal(bundledRoster.materialized_views.state, 'complete');
  assert.equal(bundledRoster.sequence_acls.state, 'complete');
  assert.equal(bundledRoster.object_coverage, 'unknown');
  const ids=await database.unsafe("SELECT (SELECT oid::bigint FROM pg_roles WHERE rolname='synthetic_fn_allowed') AS allowed, (SELECT oid::bigint FROM pg_roles WHERE rolname='synthetic_fn_denied') AS denied, (SELECT oid::bigint FROM pg_roles WHERE rolname='synthetic_fn_child') AS child, 'public.synthetic_definer()'::regprocedure::oid::bigint AS fn, 'synthetic_restricted.synthetic_definer()'::regprocedure::oid::bigint AS hidden_fn, 'synthetic_private'::regnamespace::oid::bigint AS schema, 'synthetic_restricted'::regnamespace::oid::bigint AS restricted, 'public.synthetic_columns'::regclass::oid::bigint AS relation, 'public.synthetic_sequence'::regclass::oid::bigint AS sequence, 'public.synthetic_materialized'::regclass::oid::bigint AS materialized, (SELECT oid::bigint FROM pg_database WHERE datname=current_database()) AS db");
  assert.equal(bundledRoster.sequences.rows.find(x=>x.object_oid===Number(ids[0].sequence) && x.role_oid===Number(ids[0].allowed))?.can_usage,true);
  assert.equal(bundledRoster.sequences.rows.find(x=>x.object_oid===Number(ids[0].sequence) && x.role_oid===Number(ids[0].denied))?.can_usage,false);
  assert.equal(bundledRoster.materialized_views.rows.find(x=>x.object_oid===Number(ids[0].materialized) && x.role_oid===Number(ids[0].allowed))?.can_maintain,true);
  assert.equal(bundledRoster.materialized_views.rows.find(x=>x.object_oid===Number(ids[0].materialized) && x.role_oid===Number(ids[0].denied))?.can_maintain,false);
  assert.ok(bundledRoster.sequence_acls.rows.some(x=>x.sequence_oid===Number(ids[0].sequence) && x.grantee_oid===0 && x.privilege==='SELECT'));
  assert.equal(JSON.stringify(bundledRoster.sequences).includes('synthetic_sequence'),false);
  assert.ok(bundledRoster.control_acls.rows.some(x=>x.scope==='schema' && x.object_oid===Number(ids[0].schema) && x.grantee_oid===0 && x.privilege==='USAGE'));
  assert.ok(bundledRoster.control_acls.rows.some(x=>x.scope==='database' && x.object_oid===Number(ids[0].db) && x.grantee_oid===Number(ids[0].allowed) && x.privilege==='CREATE'));
  assert.equal(JSON.stringify(bundledRoster.control_acls).includes('synthetic_private'),false);
  const tableRows=bundledRoster.tables.rows.filter(x=>x.relation_oid===Number(ids[0].relation));
  assert.deepEqual(tableRows.find(x=>x.role_oid===Number(ids[0].allowed))?.insertable_column_numbers,[2]);
  assert.deepEqual(tableRows.find(x=>x.role_oid===Number(ids[0].child))?.insertable_column_numbers,[2]);
  assert.deepEqual(tableRows.find(x=>x.role_oid===Number(ids[0].denied))?.updatable_column_numbers,[3]);
  assert.equal(JSON.stringify(bundledRoster.tables).includes('private_value'),false);
  assert.equal(JSON.stringify(bundledRoster.tables).includes('synthetic_columns'),false);
  const aclRows=bundledRoster.relation_acls.rows.filter(x=>x.relation_oid===Number(ids[0].relation));
  assert.ok(aclRows.some(x=>x.scope==='table' && x.grantee_oid===0 && x.privilege==='SELECT'));
  assert.ok(aclRows.some(x=>x.scope==='column' && x.column_number===2 && x.grantee_oid===Number(ids[0].allowed) && x.privilege==='INSERT'));
  assert.ok(aclRows.some(x=>x.scope==='column' && x.column_number===3 && x.grantee_oid===Number(ids[0].denied) && x.privilege==='UPDATE'));
  assert.equal(JSON.stringify(bundledRoster.relation_acls).includes('private_value'),false);
  const policy=bundledRoster.policies.rows.find(x=>x.relation_oid===Number(ids[0].relation) && x.command==='r');
  assert.equal(policy?.command,'r');
  assert.deepEqual(policy?.role_oids,[0]);
  assert.equal(policy?.has_using,true);
  assert.equal(policy?.policy_effect,'unknown');
  const writePolicy=bundledRoster.policies.rows.find(x=>x.relation_oid===Number(ids[0].relation) && x.command==='w');
  assert.equal(writePolicy?.permissive,false);
  assert.equal(writePolicy?.has_check,true);
  assert.deepEqual(writePolicy?.role_oids,[Number(ids[0].allowed),Number(ids[0].denied)].sort((a,b)=>a-b));
  assert.equal(writePolicy?.policy_effect,'unknown');
  const trigger=bundledRoster.triggers.rows.find(x=>x.relation_oid===Number(ids[0].relation) && x.internal===false);
  assert.equal(trigger?.trigger_type,7);
  assert.equal(trigger?.enabled,'O');
  assert.equal(bundledRoster.triggers.effect,'unknown');
  assert.equal(JSON.stringify(bundledRoster.triggers).includes('synthetic_trigger'),false);
  assert.equal(JSON.stringify(bundledRoster.policies).includes('synthetic_read'),false);
  const schemaRows=bundledRoster.schemas.rows.filter(x=>x.schema_oid===Number(ids[0].schema));
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].allowed))?.schema_create,true);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].denied))?.schema_create,false);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].child))?.schema_create,true);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].denied))?.schema_usage,true);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].allowed))?.database_create,true);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].child))?.database_create,true);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].denied))?.database_create,false);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].denied))?.database_connect,false);
  assert.equal(schemaRows.find(x=>x.role_oid===Number(ids[0].denied))?.database_temporary,true);
  assert.equal(bundledRoster.schemas.rows.find(x=>x.schema_oid===Number(ids[0].restricted) && x.role_oid===Number(ids[0].denied))?.schema_usage,false);
  assert.equal(JSON.stringify(bundledRoster.schemas).includes('synthetic_private'),false);
  const matching=bundledRoster.functions.rows.filter(x=>x.function_oid===Number(ids[0].fn));
  assert.equal(matching.find(x=>x.role_oid===Number(ids[0].allowed))?.can_execute,true);
  assert.equal(matching.find(x=>x.role_oid===Number(ids[0].denied))?.can_execute,false);
  assert.equal(matching.find(x=>x.role_oid===Number(ids[0].child))?.can_execute,true);
  const restrictedFunction=bundledRoster.functions.rows.find(x=>x.function_oid===Number(ids[0].hidden_fn) && x.role_oid===Number(ids[0].denied));
  assert.equal(restrictedFunction?.can_execute,true);
  assert.equal(restrictedFunction?.schema_usage,false);
  assert.ok(matching.every(x=>x.security_definer===true));
  assert.equal(JSON.stringify(bundledRoster.functions).includes('synthetic_definer'),false);
  assert.equal(JSON.stringify(bundledRoster.functions).includes('synthetic_fn_allowed'),false);
  assert.equal(bundledRoster.cross_reference, 'consistent');
  assert.equal(bundledRoster.writer_clearance, false);
  const faulted = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('FROM pg_catalog.pg_auth_members') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const partial = await inspectBoundRoster(faulted, await readLocalRosterBindings());
  assert.equal(partial.roles.state, 'complete');
  assert.equal(partial.memberships.state, 'failed');
  assert.equal(partial.cross_reference, 'unknown');
  const functionFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('CROSS JOIN pg_catalog.pg_proc p') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const functionPartial=await bundled.inspectBundledRoster(functionFault,bundle.queries);
  assert.equal(functionPartial.roles.state,'complete');
  assert.equal(functionPartial.memberships.state,'complete');
  assert.equal(functionPartial.functions.state,'failed');
  assert.equal(functionPartial.function_coverage,'unknown');
  const functionMutation = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => {
        if (!sql.includes('CROSS JOIN pg_catalog.pg_proc p')) return sp.unsafe(sql);
        const marker="pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE')";
        assert.equal(sql.split(marker).length,2);
        return sp.unsafe(sql.replace(marker,'true'));
      },
    })),
  })) };
  const altered=await bundled.inspectBundledRoster(functionMutation,bundle.queries);
  const alteredDenied=altered.functions.rows.find(x=>x.function_oid===Number(ids[0].fn) && x.role_oid===Number(ids[0].denied));
  assert.equal(alteredDenied?.can_execute,true);
  const schemaFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('CROSS JOIN pg_catalog.pg_database d') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const schemaPartial=await bundled.inspectBundledRoster(schemaFault,bundle.queries);
  assert.equal(schemaPartial.functions.state,'complete');
  assert.equal(schemaPartial.schemas.state,'failed');
  assert.equal(schemaPartial.schema_coverage,'unknown');
  const schemaMutation = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => {
        if (!sql.includes('CROSS JOIN pg_catalog.pg_database d')) return sp.unsafe(sql);
        const marker="pg_catalog.has_schema_privilege(r.oid, n.oid, 'CREATE')";
        assert.equal(sql.split(marker).length,2);
        return sp.unsafe(sql.replace(marker,'true'));
      },
    })),
  })) };
  const changedSchemas=await bundled.inspectBundledRoster(schemaMutation,bundle.queries);
  assert.equal(changedSchemas.schemas.rows.find(x=>x.schema_oid===Number(ids[0].schema) && x.role_oid===Number(ids[0].denied))?.schema_create,true);
  const tableFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('AS insertable_column_numbers') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const tablePartial=await bundled.inspectBundledRoster(tableFault,bundle.queries);
  assert.equal(tablePartial.schemas.state,'complete');
  assert.equal(tablePartial.tables.state,'failed');
  assert.equal(tablePartial.table_coverage,'unknown');
  const tableMutation = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => {
        if (!sql.includes('AS insertable_column_numbers')) return sp.unsafe(sql);
        const marker="pg_catalog.has_column_privilege(r.oid,c.oid,a.attnum,'INSERT')";
        assert.equal(sql.split(marker).length,2);
        return sp.unsafe(sql.replace(marker,'false'));
      },
    })),
  })) };
  const changedTables=await bundled.inspectBundledRoster(tableMutation,bundle.queries);
  assert.deepEqual(changedTables.tables.rows.find(x=>x.relation_oid===Number(ids[0].relation) && x.role_oid===Number(ids[0].allowed))?.insertable_column_numbers,[]);
  const sessionFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('FROM pg_catalog.pg_stat_activity') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const sessionPartial=await bundled.inspectBundledRoster(sessionFault,bundle.queries);
  assert.equal(sessionPartial.tables.state,'complete');
  assert.equal(sessionPartial.sessions.state,'failed');
  assert.equal(sessionPartial.session_coverage,'unknown');
  const aclFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes("'relation_acl' AS kind") ? 'SELECT 1/0' : sql),
    })),
  })) };
  const aclPartial=await bundled.inspectBundledRoster(aclFault,bundle.queries);
  assert.equal(aclPartial.tables.state,'complete');
  assert.equal(aclPartial.relation_acls.state,'failed');
  assert.equal(aclPartial.relation_acl_coverage,'unknown');
  const aclMutation = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => {
        if (!sql.includes("'relation_acl' AS kind")) return sp.unsafe(sql);
        const marker='pg_catalog.aclexplode(a.attacl)';
        assert.equal(sql.split(marker).length,2);
        return sp.unsafe(sql.replace(marker,'pg_catalog.aclexplode(NULL::pg_catalog.aclitem[])'));
      },
    })),
  })) };
  const changedAcls=await bundled.inspectBundledRoster(aclMutation,bundle.queries);
  assert.equal(changedAcls.relation_acls.rows.some(x=>x.relation_oid===Number(ids[0].relation) && x.scope==='column' && x.column_number===2 && x.grantee_oid===Number(ids[0].allowed) && x.privilege==='INSERT'),false);
  const controlFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes("'control_acl' AS kind") ? 'SELECT 1/0' : sql),
    })),
  })) };
  const controlPartial=await bundled.inspectBundledRoster(controlFault,bundle.queries);
  assert.equal(controlPartial.relation_acls.state,'complete');
  assert.equal(controlPartial.control_acls.state,'failed');
  assert.equal(controlPartial.control_acl_coverage,'unknown');
  const policyFault = { begin: (mode, callback) => database.begin(mode, (tx) => callback({
    unsafe: (sql) => tx.unsafe(sql),
    savepoint: (arm) => tx.savepoint((sp) => arm({
      unsafe: (sql) => sp.unsafe(sql.includes('FROM pg_catalog.pg_policy p') ? 'SELECT 1/0' : sql),
    })),
  })) };
  const policyPartial=await bundled.inspectBundledRoster(policyFault,bundle.queries);
  assert.equal(policyPartial.control_acls.state,'complete');
  assert.equal(policyPartial.policies.state,'failed');
  assert.equal(policyPartial.policies.effect,'unknown');
  for (const [marker,arm] of [['FROM pg_catalog.pg_trigger t','triggers'],["'sequence_privilege' AS kind",'sequences'],["'materialized_view_privilege' AS kind",'materialized_views'],["'sequence_acl' AS kind",'sequence_acls']]) {
    const fault={begin:(mode,callback)=>database.begin(mode,tx=>callback({unsafe:sql=>tx.unsafe(sql),
      savepoint:fn=>tx.savepoint(sp=>fn({unsafe:sql=>sp.unsafe(sql.includes(marker)?'SELECT 1/0':sql)}))}))};
    const partial=await bundled.inspectBundledRoster(fault,bundle.queries);
    assert.equal(partial[arm].state,'failed');
    assert.equal(partial.roles.state,'complete');
    assert.equal(partial.holder_coverage,'unknown');
    assert.equal(partial.writer_clearance,false);
  }
  await database.begin('isolation level repeatable read read only', async (tx) => {
    let seen = 0;
    for await (const batch of tx.unsafe('SELECT generate_series(1, 10) AS value').cursor(1)) {
      assert.equal(batch.length, 1);
      if (++seen === 2) break;
    }
    assert.equal(seen, 2);
    assert.equal((await tx.unsafe('SELECT 1 AS value'))[0].value, 1);
  });
  await assert.rejects(database.begin('isolation level repeatable read read only', async (tx) => {
    await tx.unsafe('CREATE TABLE public.synthetic_readonly_violation (id integer)');
  }), (error) => error.code === '25006');
  // This probe is restricted to the disposable local fixture. Its observations
  // are not a cancellation or backend-termination guarantee for a live service.
  const dedicated = postgres({ host: '127.0.0.1', port: 5432, socket, database: databaseName,
    username: 'postgres', password, max: 1, connect_timeout: 5 });
  let identity, transaction, arms = 0;
  const stalled = { begin: (mode, callback) => {
    transaction = dedicated.begin(mode, async (tx) => {
      const rows = await tx.unsafe("SELECT pg_backend_pid() AS pid, to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US') AS started FROM pg_stat_activity WHERE pid=pg_backend_pid()");
      assert.equal(rows.length, 1);
      identity = rows[0];
      return callback({ unsafe: sql => tx.unsafe(sql), savepoint: fn => tx.savepoint(sp => fn({
        unsafe: sql => { arms++; return sp.unsafe(arms === 1 ? 'SELECT pg_sleep(10)' : sql); },
      })) });
    });
    return transaction;
  } };
  try {
    const tracked = trackInspectionTransaction(stalled, db => bundled.inspectBundledRoster(db, bundle.queries, { timeoutMs: 1000 }));
    const pending = tracked.inspection;
    let active = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      if (identity && arms === 1) {
        const rows = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2 AND state='active' AND query='SELECT pg_sleep(10)'", [identity.pid, identity.started]);
        if (rows[0].count === 1) { active = true; break; }
      }
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    if (!active && identity) {
      const diagnostic = await database.unsafe("SELECT count(*)::int AS present, count(*) FILTER (WHERE to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2)::int AS started, count(*) FILTER (WHERE state='active')::int AS active, count(*) FILTER (WHERE query='SELECT pg_sleep(10)')::int AS matching FROM pg_stat_activity WHERE pid=$1", [identity.pid, identity.started]);
      assert.equal(diagnostic[0].present, 1);
      assert.equal(diagnostic[0].started, 1);
      assert.equal(diagnostic[0].active, 1);
      assert.equal(diagnostic[0].matching, 1);
    }
    assert.equal(active, true);
    const timedOut = await pending;
    assert.equal(timedOut.roles.state, 'failed');
    assert.equal(timedOut.backend_stop, 'unknown');
    assert.equal(timedOut.writer_clearance, false);
    let trackerSettled = false;
    tracked.settlement.then(() => { trackerSettled = true; });
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(trackerSettled, false);
    const stillActive = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2 AND state='active' AND query='SELECT pg_sleep(10)'", [identity.pid, identity.started]);
    assert.equal(stillActive[0].count, 1);
    await dedicated.end({ timeout: 0 });
    await transaction.then(() => undefined, () => undefined);
    const trackerResult = await tracked.settlement;
    assert.ok(['fulfilled', 'rejected'].includes(trackerResult.state));
    assert.equal(trackerResult.backend_stop, 'unknown');
    assert.equal(trackerResult.writer_clearance, false);
    let gone = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const rows = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2", [identity.pid, identity.started]);
      if (rows[0].count === 0) { gone = true; break; }
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.equal(gone, true);
    assert.equal((await database.unsafe('SELECT 1 AS healthy'))[0].healthy, 1);
    assert.equal(arms, 1);
  } finally {
    await dedicated.end({ timeout: 0 });
  }
  // Compare natural completion with a canceled query in this disposable
  // fixture. Cancellation must not count as delivery of a completed cursor.
  const guardDir = await mkdtemp(join(tmpdir(), 'synthetic-collector-guard-'));
  const guardPath = join(guardDir, 'fixture.sqlite');
  const guardScript = fileURLToPath(new URL('./holder-evidence-guard-fixture.py', import.meta.url));
  const guard = operation => {
    const result = spawnSync('python3', [guardScript, guardPath, operation], {
      encoding: 'utf8', timeout: 5000, maxBuffer: 4096, env: { PATH: '/usr/bin:/bin' },
    });
    assert.equal(result.status, 0, `synthetic guard operation failed: ${operation}`);
    return JSON.parse(result.stdout);
  };
  assert.equal(guard('initialize').state, 'active');
  try {
  for (const cancelAfterTimeout of [false, true]) {
    const lateClient = postgres({ host: '127.0.0.1', port: 5432, socket, database: databaseName,
      username: 'postgres', password, max: 1, connect_timeout: 5 });
    let lateArms = 0, lateTransaction, lateIdentity, lateCursorError, lateDelivered = false;
    let guardAttempts = 0, guardResult, guardError;
    const late = { begin: (mode, callback) => {
      lateTransaction = lateClient.begin(mode, async tx => {
        const rows = await tx.unsafe("SELECT pg_backend_pid() AS pid, to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US') AS started FROM pg_stat_activity WHERE pid=pg_backend_pid()");
        assert.equal(rows.length, 1);
        lateIdentity = rows[0];
        return callback({ unsafe: sql => tx.unsafe(sql), savepoint: fn => tx.savepoint(sp => fn({ unsafe: sql => {
          lateArms++;
          if (lateArms !== 1) return sp.unsafe(sql);
          return { cursor(size) {
            const cursor = sp.unsafe('SELECT pg_sleep(4)').cursor(size);
            return (async function* () {
              try {
                for await (const batch of cursor) {
                  lateDelivered = true;
                  if (!cancelAfterTimeout) {
                    guardAttempts++;
                    try { guardResult = guard('write'); } catch (error) { guardError = error; }
                  }
                  yield batch;
                }
              } catch (error) {
                lateCursorError = error.code;
                throw error;
              }
            })();
          } };
        } })) });
      });
      return lateTransaction;
    } };
    try {
      const trackedLate = trackInspectionTransaction(late, db => bundled.inspectBundledRoster(db, bundle.queries, { timeoutMs: 1500 }));
      const pending = trackedLate.inspection;
      let observed = false;
      for (let attempt = 0; attempt < 200; attempt++) {
        if (lateIdentity && lateArms === 1) {
          const rows = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2 AND state='active' AND query='SELECT pg_sleep(4)'", [lateIdentity.pid, lateIdentity.started]);
          if (rows[0].count === 1) { observed = true; break; }
        }
        await new Promise(resolve => setTimeout(resolve, 5));
      }
      assert.equal(observed, true);
      const lateResult = await pending;
      assert.equal(lateResult.roles.state, 'failed');
      assert.equal(lateResult.backend_stop, 'unknown');
      assert.equal(lateResult.writer_clearance, false);
      assert.equal(lateDelivered, false);
      const activeAfterDeadline = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2 AND state='active' AND query='SELECT pg_sleep(4)'", [lateIdentity.pid, lateIdentity.started]);
      assert.equal(activeAfterDeadline[0].count, 1);
      if (!cancelAfterTimeout) {
        assert.equal(guard('quarantine').state, 'quarantined');
        assert.equal(guard('inspect').writes, 0);
      }
      if (cancelAfterTimeout) {
        // PID-only cancellation is confined to this owned test server. The
        // preceding observation is not an atomic production identity fence.
        const active = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE pid=$1 AND to_char(backend_start AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')=$2 AND state='active' AND query='SELECT pg_sleep(4)'", [lateIdentity.pid, lateIdentity.started]);
        assert.equal(active[0].count, 1);
        assert.equal((await database.unsafe('SELECT pg_cancel_backend($1) AS canceled', [lateIdentity.pid]))[0].canceled, true);
      }
      let timer;
      const outcome = await Promise.race([
        lateTransaction.then(() => 'unexpected_success', error => error.message),
        new Promise(resolve => { timer = setTimeout(() => resolve('settlement_timeout'), 6000); }),
      ]).finally(() => clearTimeout(timer));
      assert.equal(outcome, 'deadline');
      const settlement = await trackedLate.settlement;
      assert.equal(settlement.state, 'rejected');
      assert.equal(settlement.backend_stop, 'unknown');
      assert.equal(settlement.writer_clearance, false);
      assert.equal(lateDelivered, !cancelAfterTimeout);
      if (!cancelAfterTimeout) {
        assert.equal(guardAttempts, 1);
        assert.equal(guardError, undefined);
        assert.equal(guardResult?.state, 'rejected');
        assert.equal(guardResult?.backend_stop, 'unknown');
        assert.equal(guardResult?.writer_clearance, false);
      }
      assert.equal(guard('inspect').writes, 0);
      assert.equal(lateCursorError, cancelAfterTimeout ? '57014' : undefined);
      assert.equal(lateArms, 1);
      assert.equal((await database.unsafe('SELECT 1 AS healthy'))[0].healthy, 1);
    } finally {
      await lateClient.end({ timeout: 0 });
    }
  }
  // The opposite sequential ordering must retain the prior synthetic write
  // while refusing subsequent writes with the now-stale epoch.
  await rm(guardPath);
  assert.equal(guard('initialize').state, 'active');
  assert.equal(guard('write').state, 'written');
  assert.equal(guard('quarantine').state, 'quarantined');
  assert.equal(guard('write').state, 'rejected');
  assert.equal(guard('inspect').writes, 1);
  } finally { await rm(guardDir, { recursive: true, force: true }); }
  const cancellable = postgres({ host: '127.0.0.1', port: 5432, socket, database: databaseName,
    username: 'postgres', password, max: 1, connect_timeout: 5,
    connection: { application_name: 'synthetic-cancel-probe' } });
  try {
    const pending = cancellable.unsafe('SELECT pg_sleep(10)').execute();
    const outcome = pending.then(() => 'completed', (error) => error.code);
    let active = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const rows = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE datname=current_database() AND application_name='synthetic-cancel-probe' AND state='active'");
      if (rows[0].count === 1) { active = true; break; }
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(active, true);
    // In this pinned driver cancel() does not return the canceller's promise;
    // the query outcome and separate observation below are the evidence here.
    pending.cancel();
    assert.equal(await outcome, '57014');
    let stopped = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      const remaining = await database.unsafe("SELECT count(*)::int AS count FROM pg_stat_activity WHERE datname=current_database() AND application_name='synthetic-cancel-probe' AND state='active'");
      if (remaining[0].count === 0) { stopped = true; break; }
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(stopped, true);
  } finally {
    await cancellable.end({ timeout: 5 });
  }
  process.stdout.write('synthetic read-only boundary passed\n');
} finally {
  await database.end({ timeout: 5 });
}

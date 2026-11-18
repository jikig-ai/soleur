import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assessPrincipal } from './holder-evidence-principal.mjs';

const role = { role_oid: 7, superuser: false, bypass_rls: false, can_create_role: false, can_create_database: false, replication: false };
const empty = () => ({ snapshot_consistent: true, roles: { state: 'complete', rows: [role] },
  memberships: { state: 'complete', rows: [] }, schemas: { state: 'complete', rows: [] },
  tables: { state: 'complete', rows: [] }, functions: { state: 'complete', rows: [] },
  sequences: { state: 'complete', rows: [] }, materialized_views: { state: 'complete', rows: [] } });

test('absence of modeled signals never asserts read-only or writer clearance', () => {
  const result = assessPrincipal(empty(), 7);
  assert.deepEqual(result.detected, []);
  assert.equal(result.modeled_coverage, 'unknown');
  assert.equal(result.read_only, 'unknown');
  assert.equal(result.writer_clearance, false);
});

test('missing, partial, malformed and inconsistent inputs remain unknown', () => {
  const missing = empty(); delete missing.tables;
  assert.equal(assessPrincipal(missing, 7).modeled_coverage, 'unknown');
  const partial = empty(); partial.memberships.state = 'partial';
  assert.equal(assessPrincipal(partial, 7).modeled_coverage, 'unknown');
  const malformed = empty(); malformed.sequences.rows = [null];
  assert.equal(assessPrincipal(malformed, 7).modeled_coverage, 'unknown');
  const drift = empty(); drift.snapshot_consistent = false;
  assert.equal(assessPrincipal(drift, 7).modeled_coverage, 'unknown');
  assert.equal(assessPrincipal(empty(), 8).modeled_coverage, 'unknown');
});

test('direct and switchable privilege paths are detected without copying names', () => {
  const data = empty();
  data.memberships.rows.push({ member_oid: 7, role_oid: 8, can_set_role: true, secret: 'private' });
  data.schemas.rows.push({ role_oid: 7, schema_create: true, database_create: false });
  data.tables.rows.push({ role_oid: 7, can_insert: false, can_update_table: false, can_delete: false, can_truncate: false, insertable_columns: [], updatable_columns: ['private_column'] });
  data.functions.rows.push({ role_oid: 7, security_definer: true, can_execute: true });
  data.sequences.rows.push({ role_oid: 7, can_usage: false, can_update: true });
  data.materialized_views.rows.push({ role_oid: 7, can_maintain: true });
  const result = assessPrincipal(data, 7);
  assert.deepEqual(result.detected, ['role_switch', 'schema_or_database_create', 'table_write', 'security_definer_execute', 'sequence_write', 'materialized_maintain']);
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.equal(result.read_only, 'unknown');
});

test('unknown role flags or a non-boolean permission cannot imply completeness', () => {
  const data = empty();
  data.roles.rows = [{ ...role, superuser: 'secret' }];
  assert.equal(assessPrincipal(data, 7).modeled_coverage, 'unknown');
  const invalid = empty();
  invalid.tables.rows = [{ role_oid: 7, can_insert: 'true' }];
  assert.equal(assessPrincipal(invalid, 7).modeled_coverage, 'unknown');
});

test('unmatched or duplicated role identities cannot imply a consistent snapshot', () => {
  const missingParent = empty();
  missingParent.memberships.rows = [{ member_oid: 7, role_oid: 8, can_set_role: true }];
  const result = assessPrincipal(missingParent, 7);
  assert.equal(result.modeled_coverage, 'unknown');
  assert.deepEqual(result.detected, ['role_switch']);
  const duplicate = empty();
  duplicate.roles.rows = [role, role];
  assert.equal(assessPrincipal(duplicate, 7).modeled_coverage, 'unknown');
  const orphan = empty();
  orphan.schemas.rows = [{ role_oid: 8, schema_create: true, database_create: false }];
  assert.equal(assessPrincipal(orphan, 7).modeled_coverage, 'unknown');
});

test('a partial or malformed arm retains valid positive observations without claiming coverage', () => {
  const data = empty();
  data.tables = { state: 'partial', rows: [null, { role_oid: 7, can_insert: true, can_update_table: false,
    can_delete: false, can_truncate: false, insertable_columns: [], updatable_columns: [] }] };
  const result = assessPrincipal(data, 7);
  assert.deepEqual(result.detected, ['table_write']);
  assert.equal(result.modeled_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
});

test('number-only column privilege observations remain detectable', () => {
  const data=empty();
  data.tables.rows=[{role_oid:7,can_insert:false,can_update_table:false,can_delete:false,can_truncate:false,
    insertable_column_numbers:[2],updatable_column_numbers:[]}];
  const result=assessPrincipal(data,7);
  assert.deepEqual(result.detected,['table_write']);
  assert.equal(result.modeled_coverage,'unknown');
  assert.equal(result.writer_clearance,false);
});

test('valid positive table fields survive unrelated malformed sibling fields', () => {
  const data=empty();
  for (const positive of [{can_insert:true},{insertable_column_numbers:[2]},{updatable_column_numbers:[3]},{insertable_columns:['x']},{updatable_columns:['x']}]) {
    data.tables={state:'partial',rows:[{role_oid:7,can_insert:null,can_update_table:null,can_delete:null,can_truncate:null,
      insertable_columns:null,updatable_columns:null,insertable_column_numbers:null,updatable_column_numbers:null,...positive}]};
    assert.deepEqual(assessPrincipal(data,7).detected,['table_write']);
    assert.equal(assessPrincipal(data,7).writer_clearance,false);
  }
  data.tables.rows=[{role_oid:7,can_insert:'true',insertable_column_numbers:['2']}];
  assert.deepEqual(assessPrincipal(data,7).detected,[]);
});

test('valid positive signals in other arms survive malformed unrelated fields', () => {
  const data=empty();
  data.roles.rows=[{role_oid:7,superuser:true,bypass_rls:null}];
  data.schemas.rows=[{role_oid:7,schema_create:true,database_create:null}];
  data.sequences.rows=[{role_oid:7,can_usage:true,can_update:null}];
  data.memberships.rows=[{member_oid:7,role_oid:8,can_set_role:true,other:null}];
  data.functions.rows=[{role_oid:7,security_definer:true,can_execute:true,other:null}];
  data.materialized_views.rows=[{role_oid:7,can_maintain:true}];
  assert.deepEqual(assessPrincipal(data,7).detected,['privileged_role','role_switch','schema_or_database_create','security_definer_execute','sequence_write','materialized_maintain']);
  data.roles.rows=[{role_oid:7,superuser:'true'}];
  data.schemas.rows=[{role_oid:7,schema_create:'true'}];
  data.sequences.rows=[{role_oid:7,can_usage:'true'}];
  data.memberships.rows=[]; data.functions.rows=[]; data.materialized_views.rows=[];
  assert.deepEqual(assessPrincipal(data,7).detected,[]);
});

test('sparse or accessor column arrays do not create positive observations', () => {
  const data=empty();
  const accessor=[]; Object.defineProperty(accessor,0,{get(){throw Error('private');},enumerable:true});
  for (const value of [Array(1),[undefined],accessor]) {
    for (const field of ['insertable_columns','updatable_columns','insertable_column_numbers','updatable_column_numbers']) {
      data.tables={state:'partial',rows:[{role_oid:7,[field]:value}]};
      assert.deepEqual(assessPrincipal(data,7).detected,[]);
    }
  }
});

test('a changing proxy length cannot fabricate a positive column observation', () => {
  let reads=0;
  const value=new Proxy([],{get(target,key,receiver){if(key==='length') return ++reads<=2?0:1; return Reflect.get(target,key,receiver);}});
  const data=empty(); data.tables={state:'partial',rows:[{role_oid:7,insertable_column_numbers:value}]};
  assert.deepEqual(assessPrincipal(data,7).detected,[]);
});

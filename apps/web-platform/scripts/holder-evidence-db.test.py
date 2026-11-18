"""Synthetic catalog test against an isolated local-only PostgreSQL database."""
from pathlib import Path
import json
import os
import re
import secrets
import subprocess
import time
import unittest
from holder_evidence_test_postgres import temporary_postgres

QUERY = Path(__file__).with_name('holder-evidence-db-table.sql')
MEMBERSHIPS = Path(__file__).with_name('holder-evidence-db-memberships.sql')
FUNCTIONS = Path(__file__).with_name('holder-evidence-db-functions.sql')
ROLES = Path(__file__).with_name('holder-evidence-db-roles.sql')
SESSIONS = Path(__file__).with_name('holder-evidence-db-sessions.sql')
ACLS = Path(__file__).with_name('holder-evidence-db-acls.sql')
SCHEMAS = Path(__file__).with_name('holder-evidence-db-schemas.sql')
CONTROL_ACLS = Path(__file__).with_name('holder-evidence-db-control-acls.sql')
TRIGGERS = Path(__file__).with_name('holder-evidence-db-triggers.sql')
POLICIES = Path(__file__).with_name('holder-evidence-db-policies.sql')
OBJECTS = Path(__file__).with_name('holder-evidence-db-objects.sql')
SEQUENCE_ACLS = Path(__file__).with_name('holder-evidence-db-sequence-acls.sql')
NAME = f'holder_evidence_test_{os.getpid()}'
assert re.fullmatch(r'holder_evidence_test_[0-9]+', NAME)
PARENT, CHILD, OTHER = (NAME + suffix for suffix in ('_parent', '_child', '_other'))
LIMITED = NAME + '_limited'
LIMITED_PASSWORD = secrets.token_hex(24)
ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent', 'PGCONNECT_TIMEOUT': '5'}
DB = None


def sql(database, text, user='postgres', password=None):
    if DB is None:
        raise RuntimeError('synthetic database not bound')
    command = DB.psql_command(database, user, password) + ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']
    result = subprocess.run(command, input='\\set VERBOSITY sqlstate\n' + text,
                            text=True, capture_output=True, env=ENV, timeout=20)
    if result.returncode:
        match = re.search(r'ERROR:\s+([0-9A-Z]{5})', result.stderr)
        raise RuntimeError('synthetic PostgreSQL command failed: ' + (match.group(1) if match else 'unknown'))
    return result.stdout


class CatalogTest(unittest.TestCase):
    def setUp(self):
        global DB
        self.container = temporary_postgres()
        DB = self.container.__enter__()

    def tearDown(self):
        global DB
        try:
            self.container.__exit__(None, None, None)
        finally:
            DB = None

    def test_effective_and_inherited_privileges(self):
        query = QUERY.read_text()
        memberships_query = MEMBERSHIPS.read_text()
        functions_query = FUNCTIONS.read_text()
        roles_query = ROLES.read_text()
        sessions_query = SESSIONS.read_text()
        acls_query = ACLS.read_text()
        schemas_query = SCHEMAS.read_text()
        control_acls_query = CONTROL_ACLS.read_text()
        triggers_query = TRIGGERS.read_text()
        policies_query = POLICIES.read_text()
        objects_query = OBJECTS.read_text()
        sequence_acls_query = SEQUENCE_ACLS.read_text()
        if sql('postgres', f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');").strip() != 'f':
            self.fail('test database name already exists')
        created = False
        role_created = False
        other_session = None
        try:
            sql('postgres', f'CREATE DATABASE "{NAME}" TEMPLATE template0;')
            created = True
            sql('postgres', f"CREATE ROLE {LIMITED} LOGIN PASSWORD '{LIMITED_PASSWORD}';")
            role_created = True
            other_session = subprocess.Popen(DB.psql_command(NAME, 'postgres') + ['-X', '-q', '-v', 'ON_ERROR_STOP=1',
                                              '-c', "SET application_name='SYNTHETIC_PRIVATE_PEER'; SELECT pg_sleep(4);"],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=ENV)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if sql(NAME, "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='SYNTHETIC_PRIVATE_PEER');").strip() == 't':
                    break
                if other_session.poll() is not None:
                    self.fail('synthetic peer exited before observation')
                time.sleep(0.05)
            else:
                self.fail('synthetic peer did not become visible')
            output = sql(NAME, f'''
BEGIN;
CREATE ROLE {PARENT} NOLOGIN;
CREATE ROLE {CHILD} LOGIN INHERIT;
CREATE ROLE {OTHER} LOGIN;
GRANT {PARENT} TO {CHILD};
GRANT {PARENT} TO {OTHER} WITH INHERIT FALSE, SET TRUE;
CREATE TABLE public.holder_test_items (id integer, public_value integer, private_value integer);
ALTER TABLE public.holder_test_items ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO PUBLIC;
GRANT UPDATE (public_value) ON public.holder_test_items TO PUBLIC;
GRANT INSERT ON public.holder_test_items TO {PARENT} WITH GRANT OPTION;
GRANT INSERT (private_value) ON public.holder_test_items TO {OTHER};
CREATE SCHEMA holder_test_private;
GRANT CREATE ON SCHEMA holder_test_private TO {PARENT} WITH GRANT OPTION;
GRANT CREATE ON DATABASE "{NAME}" TO {OTHER};
CREATE TABLE holder_test_private.items (id integer);
GRANT USAGE ON SCHEMA holder_test_private TO {CHILD};
GRANT DELETE ON holder_test_private.items TO {CHILD};
CREATE SEQUENCE holder_test_private.synthetic_sequence;
GRANT USAGE, UPDATE ON SEQUENCE holder_test_private.synthetic_sequence TO {PARENT};
GRANT UPDATE ON SEQUENCE holder_test_private.synthetic_sequence TO {OTHER} WITH GRANT OPTION;
CREATE MATERIALIZED VIEW holder_test_private.synthetic_view AS SELECT 1 AS id;
GRANT MAINTAIN ON holder_test_private.synthetic_view TO {CHILD};
CREATE FUNCTION holder_test_private.writer() RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;
REVOKE ALL ON FUNCTION holder_test_private.writer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION holder_test_private.writer() TO {CHILD};
CREATE FUNCTION public.holder_test_write() RETURNS void LANGUAGE sql SECURITY DEFINER
  SET search_path = public, pg_temp AS $$ INSERT INTO public.holder_test_items VALUES (1, 2, 3) $$;
REVOKE ALL ON FUNCTION public.holder_test_write() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.holder_test_write() TO {PARENT};
CREATE POLICY holder_test_policy ON public.holder_test_items FOR UPDATE TO PUBLIC USING (true) WITH CHECK (false);
CREATE FUNCTION public.holder_test_trigger() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE TRIGGER holder_test_trigger BEFORE INSERT ON public.holder_test_items FOR EACH ROW EXECUTE FUNCTION public.holder_test_trigger();
SET LOCAL application_name = 'SYNTHETIC_PRIVATE_APPLICATION';
''' + query + '\n' + memberships_query + '\n' + functions_query + '\n' + roles_query + '\n' + acls_query + '\n' + schemas_query + '\n' + control_acls_query + '\n' + triggers_query + '\n' + policies_query + '\n' + objects_query + '\n' + sequence_acls_query + '\n' + sessions_query + '\nROLLBACK;')
            output += sql(NAME, sessions_query, user=LIMITED, password=LIMITED_PASSWORD)
            rows = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
            selected = {row['role_name']: row for row in rows if row.get('relation') == 'holder_test_items' and 'role_name' in row}
            child = selected[CHILD]
            other = selected[OTHER]
            self.assertTrue(child['can_insert'])
            self.assertFalse(other['can_insert'])
            self.assertEqual(other['insertable_columns'], ['private_value'])
            self.assertFalse(child['can_update_table'])
            self.assertEqual(child['updatable_columns'], ['public_value'])
            self.assertEqual(other['updatable_columns'], ['public_value'])
            self.assertTrue(child['rls_enabled'])
            self.assertTrue(child['schema_usage'])
            membership = next(row for row in rows if row.get('member_name') == OTHER and row.get('role_name') == PARENT)
            self.assertFalse(membership['inherit_option'])
            self.assertTrue(membership['set_option'])
            self.assertTrue(membership['can_set_role'])
            self.assertFalse(membership['inherits_privileges'])
            functions = {row['role_name']: row for row in rows if row.get('function_name') == 'holder_test_write'}
            self.assertTrue(functions[CHILD]['can_execute'])
            self.assertFalse(functions[OTHER]['can_execute'])
            self.assertTrue(functions[CHILD]['security_definer'])
            roles = {row['role_name']: row for row in rows if row.get('kind') == 'role'}
            self.assertTrue(roles[CHILD]['can_login'])
            self.assertFalse(roles[PARENT]['can_login'])
            self.assertFalse(roles[CHILD]['superuser'])
            self.assertFalse(roles[CHILD]['bypass_rls'])
            self.assertGreater(roles[CHILD]['role_oid'], 0)
            self.assertEqual(child['role_oid'], roles[CHILD]['role_oid'])
            self.assertEqual(child['owner_oid'], roles['postgres']['role_oid'])
            self.assertEqual(functions[CHILD]['role_oid'], roles[CHILD]['role_oid'])
            self.assertEqual(membership['member_oid'], roles[OTHER]['role_oid'])
            self.assertEqual(membership['role_oid'], roles[PARENT]['role_oid'])
            self.assertIsInstance(membership['grantor_oid'], int)
            acls = [row for row in rows if row.get('kind') == 'relation_acl']
            self.assertTrue(any(row['scope'] == 'column' and row['grantee'] == 'PUBLIC' and row['column_name'] == 'public_value' and row['privilege'] == 'UPDATE' for row in acls))
            self.assertTrue(any(row['scope'] == 'table' and row['grantee'] == PARENT and row['privilege'] == 'INSERT' and row['grantable'] for row in acls))
            self.assertTrue(any(row['schema_name'] == 'holder_test_private' and row['grantee'] == CHILD and row['privilege'] == 'DELETE' for row in acls))
            self.assertTrue(any(row['grantee'] == 'PUBLIC' and row['grantee_oid'] == 0 for row in acls))
            self.assertTrue(any(row['grantee'] == PARENT and row['grantee_oid'] == roles[PARENT]['role_oid'] for row in acls))
            self.assertTrue(any(row['relation'] == 'holder_test_items' and row['relation_oid'] == child['relation_oid'] for row in acls))
            schema = next(row for row in rows if row.get('kind') == 'schema_privilege' and row['schema_name'] == 'holder_test_private' and row['role_name'] == CHILD)
            self.assertTrue(schema['schema_usage'])
            self.assertEqual(schema['role_oid'], roles[CHILD]['role_oid'])
            self.assertEqual(schema['owner_oid'], roles['postgres']['role_oid'])
            self.assertTrue(schema['schema_create'])
            other_schema = next(row for row in rows if row.get('kind') == 'schema_privilege' and row['schema_name'] == 'holder_test_private' and row['role_name'] == OTHER)
            self.assertFalse(other_schema['schema_create'])
            private_table = next((row for row in rows if row.get('schema_name') == 'holder_test_private' and row.get('relation') == 'items' and row.get('role_name') == CHILD), None)
            self.assertIsNotNone(private_table)
            self.assertTrue(private_table['can_delete'])
            self.assertEqual(private_table['schema_oid'], schema['schema_oid'])
            private_function = next((row for row in rows if row.get('schema_name') == 'holder_test_private' and row.get('function_name') == 'writer' and row.get('role_name') == CHILD), None)
            self.assertIsNotNone(private_function)
            self.assertTrue(private_function['can_execute'])
            control_acls = [row for row in rows if row.get('kind') == 'control_acl']
            self.assertTrue(any(row['scope'] == 'schema' and row['object_name'] == 'holder_test_private' and row['grantee'] == PARENT and row['privilege'] == 'CREATE' and row['grantable'] for row in control_acls))
            self.assertTrue(any(row['scope'] == 'database' and row['object_name'] == NAME and row['grantee'] == OTHER and row['privilege'] == 'CREATE' for row in control_acls))
            self.assertTrue(any(row['scope'] == 'database' and row['grantee'] == OTHER and row['grantee_oid'] == roles[OTHER]['role_oid'] for row in control_acls))
            trigger = next((row for row in rows if row.get('kind') == 'trigger' and row['trigger_name'] == 'holder_test_trigger'), None)
            self.assertIsNotNone(trigger)
            self.assertEqual(trigger['function_name'], 'holder_test_trigger')
            trigger_function = next(row for row in rows if row.get('function_name') == 'holder_test_trigger' and row.get('role_name') == CHILD)
            self.assertEqual(trigger['function_oid'], trigger_function['function_oid'])
            self.assertEqual(trigger['function_owner_oid'], roles['postgres']['role_oid'])
            self.assertEqual(trigger['relation_oid'], child['relation_oid'])
            policy = next((row for row in rows if row.get('kind') == 'policy' and row['policy_name'] == 'holder_test_policy'), None)
            self.assertIsNotNone(policy)
            self.assertEqual(policy['command'], 'w')
            self.assertEqual(policy['roles'], ['PUBLIC'])
            self.assertEqual(policy['role_oids'], [0])
            self.assertEqual(policy['relation_oid'], child['relation_oid'])
            self.assertTrue(policy['has_using'])
            self.assertTrue(policy['has_check'])
            self.assertEqual(policy['policy_effect'], 'unknown')
            sequence = next((row for row in rows if row.get('kind') == 'sequence_privilege' and row['object_name'] == 'synthetic_sequence' and row['role_name'] == CHILD), None)
            self.assertIsNotNone(sequence)
            self.assertTrue(sequence['can_usage'])
            self.assertTrue(sequence['can_update'])
            self.assertEqual(sequence['role_oid'], roles[CHILD]['role_oid'])
            self.assertEqual(sequence['owner_oid'], roles['postgres']['role_oid'])
            sequence_acls = [row for row in rows if row.get('kind') == 'sequence_acl']
            self.assertTrue(any(row['sequence_name'] == 'synthetic_sequence' and row['grantee'] == OTHER and row['privilege'] == 'UPDATE' and row['grantable'] for row in sequence_acls))
            self.assertTrue(any(row['grantee'] == OTHER and row['grantee_oid'] == roles[OTHER]['role_oid'] for row in sequence_acls))
            self.assertTrue(any(row['sequence_name'] == 'synthetic_sequence' and row['sequence_oid'] == sequence['object_oid'] for row in sequence_acls))
            matview = next((row for row in rows if row.get('kind') == 'materialized_view_privilege' and row['object_name'] == 'synthetic_view' and row['role_name'] == CHILD), None)
            self.assertIsNotNone(matview)
            self.assertTrue(matview['can_maintain'])
            self.assertEqual(matview['role_oid'], roles[CHILD]['role_oid'])
            summaries = [row for row in rows if row.get('kind') == 'session_summary']
            self.assertEqual([row['visibility'] for row in summaries], ['full_stats_privilege', 'restricted'])
            self.assertTrue(all(row['future_reconnects'] == 'unknown' for row in summaries))
            sessions = [row for row in rows if row.get('kind') == 'session']
            self.assertTrue(sessions)
            self.assertTrue(all(set(row) == {'kind', 'role_oid', 'role_name', 'application_class', 'state_class', 'transaction_age_bucket', 'write_capability'} for row in sessions))
            self.assertTrue(all(row['application_class'] in ('other', 'unknown') for row in sessions))
            self.assertTrue(all(row['write_capability'] == 'unknown' for row in sessions))
            restricted_index = next(i for i, row in enumerate(rows) if row.get('kind') == 'session_summary' and row['visibility'] == 'restricted')
            restricted_sessions = [row for row in rows[restricted_index + 1:] if row.get('kind') == 'session']
            self.assertTrue(any(row['state_class'] == 'unknown' for row in restricted_sessions))
            self.assertNotIn('SYNTHETIC_PRIVATE_APPLICATION', output)
            self.assertNotIn('SYNTHETIC_PRIVATE_PEER', output)
            self.assertNotIn('pg_sleep', output)
        finally:
            if other_session is not None:
                other_session.wait(timeout=8)
            if created:
                sql('postgres', f'DROP DATABASE "{NAME}";')
                self.assertEqual(sql('postgres', f"SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='{NAME}');").strip(), 'f')
            if role_created:
                sql('postgres', f'DROP ROLE {LIMITED};')
                self.assertEqual(sql('postgres', f"SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='{LIMITED}');").strip(), 'f')


if __name__ == '__main__':
    unittest.main()

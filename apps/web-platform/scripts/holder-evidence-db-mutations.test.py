"""Run targeted mutations against a disposable copy of the synthetic DB test."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).parent
files = ['holder-evidence-db.test.py', 'holder-evidence-db-table.sql',
         'holder-evidence-db-memberships.sql', 'holder-evidence-db-functions.sql', 'holder-evidence-db-roles.sql', 'holder-evidence-db-sessions.sql',
         'holder-evidence-db-acls.sql', 'holder-evidence-db-schemas.sql', 'holder-evidence-db-control-acls.sql',
         'holder-evidence-db-triggers.sql', 'holder-evidence-db-policies.sql', 'holder-evidence-db-objects.sql',
         'holder-evidence-db-sequence-acls.sql', 'holder_evidence_test_postgres.py']
mutations = [
    ('table-insert', files[1], "has_table_privilege(r.oid, c.oid, 'INSERT')", 'false'),
    ('column-update', files[1], "has_column_privilege(r.oid, c.oid, a.attnum, 'UPDATE')", 'false'),
    ('set-role', files[2], "pg_catalog.pg_has_role(member.oid, parent.oid, 'SET')", 'false'),
    ('function-execute', files[3], "pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE')", 'false'),
    ('role-login', files[4], 'rolcanlogin AS can_login', 'false AS can_login'),
    ('hidden-session-filter', files[5], 'WHERE datname = current_database()', "WHERE datname = current_database() AND backend_type = 'client backend'"),
    ('raw-application', files[5], "CASE WHEN application_name IS NULL THEN 'unknown' ELSE 'other' END", 'application_name'),
    ('public-column-acl', files[6], "CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END,", "CASE WHEN acl.grantee = 0 THEN 'UNKNOWN' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END,"),
    ('grant-option', files[6], 'acl.is_grantable AS grantable', 'false AS grantable'),
    ('schema-usage', files[7], "pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE')", 'false'),
    ('nonpublic-table', files[1], "n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'", "n.nspname = 'public'"),
    ('nonpublic-function', files[3], "n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'", "n.nspname = 'public'"),
    ('schema-grant-option', files[8], 'acl.is_grantable AS grantable', 'false AS grantable'),
    ('trigger-function', files[9], 'p.proname AS function_name', "'unknown' AS function_name"),
    ('policy-using', files[10], 'p.polqual IS NOT NULL AS has_using', 'false AS has_using'),
    ('policy-effect', files[10], "'unknown' AS policy_effect", "'allowed' AS policy_effect"),
    ('sequence-update', files[11], "pg_catalog.has_sequence_privilege(r.oid, c.oid, 'UPDATE')", 'false'),
    ('materialized-maintain', files[11], "pg_catalog.has_table_privilege(r.oid, c.oid, 'MAINTAIN')", 'false'),
    ('sequence-grant-option', files[12], 'acl.is_grantable AS grantable', 'false AS grantable'),
    ('table-role-id', files[1], 'r.oid::bigint AS role_oid', '1::bigint AS role_oid'),
    ('membership-role-id', files[2], 'member.oid::bigint AS member_oid', '1::bigint AS member_oid'),
    ('function-role-id', files[3], 'r.oid::bigint AS role_oid', '1::bigint AS role_oid'),
    ('control-acl-id', files[8], 'acl.grantee::bigint, acl.grantor::bigint,', '1::bigint, acl.grantor::bigint,'),
    ('relation-id', files[1], 'c.oid::bigint AS relation_oid', '1::bigint AS relation_oid'),
    ('schema-id', files[7], 'n.oid::bigint AS schema_oid', '1::bigint AS schema_oid'),
    ('trigger-function-id', files[9], 'p.oid::bigint AS function_oid', '1::bigint AS function_oid'),
    ('policy-role-ids', files[10], 'role_oid::bigint FROM unnest(p.polroles)', '1::bigint FROM unnest(p.polroles)'),
    ('sequence-id', files[12], 'c.oid::bigint AS sequence_oid', '1::bigint AS sequence_oid'),
    ('table-owner-id', files[1], 'c.relowner::bigint AS owner_oid', '1::bigint AS owner_oid'),
    ('schema-owner-id', files[7], 'n.nspowner::bigint AS owner_oid', '1::bigint AS owner_oid'),
    ('trigger-owner-id', files[9], 'p.proowner::bigint AS function_owner_oid', '1::bigint AS function_owner_oid'),
    ('sequence-owner-id', files[11], "c.relowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(c.relowner) AS owner,\n         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,\n         pg_catalog.has_sequence_privilege", "1::bigint AS owner_oid, pg_catalog.pg_get_userbyid(c.relowner) AS owner,\n         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,\n         pg_catalog.has_sequence_privilege"),
]

requested = set(sys.argv[1:])
if requested and not requested.issubset({mutation[0] for mutation in mutations}):
    raise RuntimeError('unknown mutation name')
selected = [mutation for mutation in mutations if not requested or mutation[0] in requested]

with tempfile.TemporaryDirectory(prefix='holder-evidence-mutation-') as directory:
    target = Path(directory)
    original = {name: (root / name).read_text() for name in files}
    for name, contents in original.items():
        (target / name).write_text(contents)

    def run():
        return subprocess.run([sys.executable, str(target / files[0])], text=True,
                              capture_output=True, timeout=45)

    baseline = run()
    if baseline.returncode or 'OK' not in baseline.stderr:
        raise RuntimeError('synthetic baseline failed; mutations are not measured')
    print('baseline passed', flush=True)
    for label, filename, old, new in selected:
        if original[filename].count(old) != 1:
            raise RuntimeError(f'{label}: mutation target mismatch')
        (target / filename).write_text(original[filename].replace(old, new, 1))
        result = run()
        (target / filename).write_text(original[filename])
        if result.returncode == 0 or 'FAIL:' not in result.stderr or 'ERROR:' in result.stderr:
            raise RuntimeError(f'{label}: no isolating assertion failure')
        print(f'{label} detected', flush=True)

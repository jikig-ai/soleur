"""Exercise the actual policy with synthetic resource receipts; no daemon calls."""
import json
import unittest
from api_policy import Policy, Refused

IMAGE = 'sha256:' + 'a' * 64
NETWORK_ID = 'b' * 64

class ResourceOwnership(unittest.TestCase):
    def setUp(self):
        self.policy = Policy('fixture', 'fixture-internal', '/tmp/fixture', {IMAGE: IMAGE})

    def create(self, kind, name):
        return self.policy.admit('POST', '/' + kind + '/create', json.dumps({
            'Name': name, 'Labels': {'com.supabase.cli.project': 'fixture'},
        }).encode())

    def network(self):
        self.create('networks', 'fixture-internal')
        self.policy.created_network('fixture-internal', {'Id': NETWORK_ID})

    def volume(self):
        self.policy.recorded_volume_absence('supabase_db_fixture')
        self.create('volumes', 'supabase_db_fixture')
        self.policy.created_volume('supabase_db_fixture', {
            'Name': 'supabase_db_fixture', 'Driver': 'local', 'Scope': 'local',
            'CreatedAt': '2026-10-12T12:00:00Z', 'Options': {},
            'Labels': {'soleur.recovery.attempt': 'fixture', 'com.supabase.cli.project': 'fixture'},
        })

    def test_reserved_network_cannot_be_read_or_deleted(self):
        for method in ('GET', 'DELETE'):
            with self.assertRaises(Refused):
                self.policy.admit(method, '/networks/fixture-internal')

    def test_reserved_volume_cannot_be_deleted(self):
        with self.assertRaises(Refused):
            self.policy.admit('DELETE', '/volumes/supabase_db_fixture')

    def test_pending_network_cannot_be_deleted(self):
        self.create('networks', 'fixture-internal')
        with self.assertRaises(Refused):
            self.policy.admit('DELETE', '/networks/fixture-internal')

    def test_network_alias_resolves_only_registered_id(self):
        self.network()
        path, _ = self.policy.admit('DELETE', '/v1.47/networks/fixture-internal')
        self.assertEqual(path, '/v1.47/networks/' + NETWORK_ID)
        self.policy.removed_network(NETWORK_ID)
        with self.assertRaises(Refused):
            self.policy.admit('DELETE', '/networks/fixture-internal')

    def test_volume_cleanup_requires_unchanged_receipt(self):
        self.volume()
        receipt = self.policy.volume_receipts['supabase_db_fixture']
        self.policy.verify_volume('supabase_db_fixture', receipt)
        with self.assertRaises(Refused):
            self.policy.verify_volume('supabase_db_fixture', {**receipt, 'CreatedAt': 'older'})
        with self.assertRaises(Refused):
            self.policy.verify_volume('supabase_db_fixture', {**receipt, 'Labels': {}})
        self.policy.removed_volume('supabase_db_fixture')
        with self.assertRaises(Refused):
            self.policy.admit('DELETE', '/volumes/supabase_db_fixture')

    def test_volume_requires_absence_receipt_before_create(self):
        self.create('volumes', 'supabase_db_fixture')
        with self.assertRaises(Refused):
            self.policy.created_volume('supabase_db_fixture', {
                'Name': 'supabase_db_fixture', 'Driver': 'local', 'Scope': 'local',
                'CreatedAt': '2026-10-12T12:00:00Z', 'Options': {},
                'Labels': {'soleur.recovery.attempt': 'fixture', 'com.supabase.cli.project': 'fixture'},
            })

    def test_unknown_host_privilege_fields_are_refused(self):
        for field, value in [('VolumesFrom', ['foreign']), ('VolumeDriver', 'nfs'),
                             ('Links', ['foreign']), ('DeviceCgroupRules', ['a *:* rwm']),
                             ('GroupAdd', ['0']), ('CapDrop', []), ('StorageOpt', {'size': '1T'})]:
            with self.assertRaises(Refused):
                self.policy.admit('POST', '/containers/create?name=supabase_db_fixture', json.dumps({
                    'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'},
                    'HostConfig': {field: value},
                }).encode())

    def test_ambiguous_paths_and_duplicate_names_are_refused(self):
        for path in ('http://foreign.invalid/networks/fixture-internal',
                     '/containers/create?name=supabase_db_fixture&name=foreign'):
            with self.assertRaises(Refused):
                self.policy.admit('POST', path, json.dumps({
                    'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'},
                }).encode())

    def test_container_environment_cannot_introduce_provider_or_loader_controls(self):
        for field in ('CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY', 'SUPABASE_ACCESS_TOKEN',
                      'DATABASE_URL_POOLER', 'NODE_OPTIONS', 'LD_PRELOAD', 'HTTPS_PROXY'):
            with self.assertRaises(Refused):
                self.policy.admit('POST', '/containers/create?name=supabase_db_fixture', json.dumps({
                    'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'},
                    'Env': [field + '=synthetic-do-not-use'],
                }).encode())

if __name__ == '__main__':
    unittest.main()

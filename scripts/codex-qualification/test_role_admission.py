"""Exact-role execution authority tests; pure requests, no daemon or startup."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from api_policy import Policy, Refused

IMAGE = 'sha256:' + 'a' * 64
OTHER = 'sha256:' + 'f' * 64
NAME = 'supabase_db_fixture'
DEFAULT = {'Entrypoint': ['fixture-entry'], 'Cmd': ['fixture-server'],
           'Env': ['PATH=/usr/bin:/bin'], 'User': '1001', 'WorkingDir': '/app'}

def profiles():
    return {NAME: {'role': 'db', 'image': IMAGE, 'image_config': copy.deepcopy(DEFAULT),
                   'create': copy.deepcopy(DEFAULT), 'exec': [
                       {'Cmd': ['fixture-check'], 'Env': [], 'User': '', 'WorkingDir': ''}],
                   'host': {}, 'aliases': []}}

def policy(profiles_value=None):
    p = Policy('fixture', 'fixture-internal', '/tmp/fixture', {IMAGE: IMAGE, OTHER: OTHER},
               role_profiles=profiles_value)
    p.admit('POST', '/networks/create', json.dumps({'Name': p.network,
            'Labels': {'com.supabase.cli.project': p.project}}).encode())
    p.created_network(p.network, {'Id': 'b' * 64})
    return p

def request(p, change=None):
    data = {'Image': IMAGE, 'Labels': {'com.supabase.cli.project': p.project}}
    data.update(change or {})
    return p.admit('POST', '/containers/create?name=' + NAME, json.dumps(data).encode())

class RoleAdmission(unittest.TestCase):
    def test_no_profile_means_no_executable_authority(self):
        with self.assertRaises(Refused):
            request(policy())

    def test_defaults_are_materialized_in_request(self):
        _, body = request(policy(profiles()))
        actual = json.loads(body)
        for key, value in DEFAULT.items():
            self.assertEqual(actual[key], value)

    def test_arbitrary_create_command_environment_and_image_refused(self):
        for changed in ({'Cmd': ['sh', '-c', 'unreviewed']}, {'Entrypoint': ['/bin/sh']},
                        {'Env': ['PATH=/usr/bin:/bin', 'UNREVIEWED=value']},
                        {'Env': ['PATH=/usr/bin:/bin', 'PATH=/usr/bin:/bin']},
                        {'Env': ['PATH=/foreign']}, {'Env': False},
                        {'Image': OTHER}, {'User': '0'}, {'WorkingDir': '/root'},
                        {'Healthcheck': {'Test': ['CMD', 'unreviewed']}},
                        {'OnBuild': ['unreviewed']}, {'AttachStdin': True}):
            with self.subTest(changed=changed), self.assertRaises(Refused):
                request(policy(profiles()), changed)

    def test_unknown_names_and_auto_jobs_have_no_profile(self):
        for name in ('supabase_auth_fixture', '', 'codex9051-renderer-fixture-first'):
            p = policy(profiles())
            with self.assertRaises(Refused):
                p.admit('POST', '/containers/create?name=' + name, json.dumps({
                        'Image': IMAGE, 'Labels': {'com.supabase.cli.project': 'fixture'}}).encode())

    def test_exec_bound_to_registered_container_profile(self):
        p = policy(profiles())
        request(p)
        p.created_container(NAME, 'c' * 64)
        p.admit('POST', '/containers/' + 'c' * 64 + '/exec', b'{"Cmd":["fixture-check"]}')
        for change in ({'Cmd': ['node', '--version']}, {'Cmd': ['fixture-check'], 'AttachStdin': True},
                       {'Cmd': ['fixture-check'], 'Env': ['LANG=C']},
                       {'Cmd': ['sh', '-c', 'fixture-check']}):
            with self.subTest(change=change), self.assertRaises(Refused):
                p.admit('POST', '/containers/' + 'c' * 64 + '/exec', json.dumps(change).encode())

    def test_provider_and_loader_defaults_cannot_be_profiled(self):
        for key in ('OPENAI_API_KEY', 'NODE_OPTIONS', 'LD_PRELOAD', 'HTTPS_PROXY'):
            value = profiles()
            value[NAME]['image_config']['Env'].append(key + '=synthetic')
            with self.assertRaises(Refused):
                policy(value)

    def test_profile_snapshots_cannot_change_after_construction(self):
        value = profiles()
        p = policy(value)
        value[NAME]['create']['Cmd'] = ['unreviewed']
        _, body = request(p)
        self.assertEqual(json.loads(body)['Cmd'], DEFAULT['Cmd'])

    def test_image_receipt_binds_inherited_configuration(self):
        p = policy(profiles())
        p.roles.verify_image(NAME, {'Id': IMAGE, 'Config': DEFAULT})
        for changed in ({'Id': OTHER, 'Config': DEFAULT}, {'Id': IMAGE, 'Config': {}},
                        {'Id': IMAGE, 'Config': {**DEFAULT, 'Healthcheck': {'Test': ['CMD', 'foreign']}}}):
            with self.assertRaises(Refused):
                p.roles.verify_image(NAME, changed)

    def test_role_cannot_be_attached_to_other_role_name(self):
        value = profiles()
        value[NAME]['role'] = 'renderer'
        with self.assertRaises(Refused):
            policy(value)

    def test_inherited_volumes_need_explicit_bound_destinations(self):
        value = profiles()
        value[NAME]['image_config']['Volumes'] = {'/fixture-data': {}}
        with self.assertRaises(Refused):
            policy(value)
        value[NAME]['host']['Binds'] = ['supabase_db_fixture:/fixture-data']
        p = policy(value)
        p.roles.verify_image(NAME, {'Id': IMAGE, 'Config': value[NAME]['image_config']})
        # A profile is not volume ownership; creation still refuses reserved mounts.
        with self.assertRaises(Refused):
            request(p)

    def test_role_host_dns_mount_alias_and_port_profiles_are_exact(self):
        for host in ({'Dns': ['8.8.8.8']}, {'Binds': ['/tmp/fixture:/unreviewed']},
                     {'PortBindings': {'443/tcp': [{'HostPort': '59051'}]}},
                     {'Sysctls': {'net.ipv4.ip_forward': '1'}}):
            with self.subTest(host=host), self.assertRaises(Refused):
                request(policy(profiles()), {'HostConfig': host})
        with self.assertRaises(Refused):
            request(policy(profiles()), {'NetworkingConfig': {'EndpointsConfig': {
                    'fixture-internal': {'Aliases': ['foreign.invalid']}}}})

    def test_admitted_host_bind_is_rewritten_to_its_canonical_scratch_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'tls-material'
            target.mkdir()
            alias = root / 'tls-alias'
            alias.symlink_to(target, target_is_directory=True)
            role_profiles = profiles()
            role_profiles[NAME]['host']['Binds'] = [f'{alias}:/qualification/tls:ro']
            p = Policy('fixture', 'fixture-internal', root, {IMAGE: IMAGE},
                       role_profiles=role_profiles)
            p.admit('POST', '/networks/create', json.dumps({'Name': p.network,
                    'Labels': {'com.supabase.cli.project': p.project}}).encode())
            p.created_network(p.network, {'Id': 'b' * 64})

            _, body = request(p)

            self.assertEqual(json.loads(body)['HostConfig']['Binds'],
                             [f'{target}:/qualification/tls:ro'])

if __name__ == '__main__':
    unittest.main()

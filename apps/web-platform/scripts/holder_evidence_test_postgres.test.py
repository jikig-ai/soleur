import json
import subprocess
import unittest
from unittest.mock import patch

import holder_evidence_test_postgres as fixture


class DockerFixtureTests(unittest.TestCase):
    def test_mountinfo_requires_each_actual_noexec_nosuid_tmpfs(self):
        good = ('1 0 0:1 / /var/lib/postgresql/data rw,nosuid,noexec - tmpfs tmpfs rw\n'
                '2 0 0:2 / /run/postgresql rw,nosuid,noexec - tmpfs tmpfs rw\n'
                '3 0 0:3 / /tmp rw,nosuid,noexec - tmpfs tmpfs rw\n')
        self.assertTrue(fixture.mounts_verified(good))
        self.assertFalse(fixture.mounts_verified(good.replace(' - tmpfs', ' - ext4', 1)))
        self.assertFalse(fixture.mounts_verified(good.replace('rw,nosuid,noexec', 'rw,nosuid', 1)))
        self.assertFalse(fixture.mounts_verified(good.rsplit('\n', 2)[0]))

    def test_owned_instance_has_no_host_port_and_uses_exact_container_id(self):
        calls = []
        marker = None
        password = None
        removed = False
        image = 'sha256:' + 'a' * 64
        container = 'b' * 64
        def run(command, **kwargs):
            nonlocal marker, password, removed
            calls.append(command)
            if 'image' in command:
                out = image
            elif 'run' in command:
                marker = command[command.index('--label') + 1].split('=', 1)[1]
                password = command[command.index('--env') + 1]
                out = container
            elif 'inspect' in command:
                out = json.dumps({'Id': container, 'Image': image, 'State': {'Running': True},
                                  'Config': {'Labels': {'soleur.holder-evidence-test': marker}, 'User': '70:70', 'Env': [password]},
                                  'HostConfig': {'Binds': None, 'NetworkMode': 'none', 'ReadonlyRootfs': True,
                                                 'CapDrop': ['ALL'], 'SecurityOpt': ['no-new-privileges'],
                                                 'Tmpfs': fixture._TMPFS},
                                  'Mounts': [], 'NetworkSettings': {'Ports': {}}})
            elif 'cat' in command:
                out = ('1 0 0:1 / /var/lib/postgresql/data rw,nosuid,noexec - tmpfs tmpfs rw\n'
                       '2 0 0:2 / /run/postgresql rw,nosuid,noexec - tmpfs tmpfs rw\n'
                       '3 0 0:3 / /tmp rw,nosuid,noexec - tmpfs tmpfs rw\n')
            elif 'rm' in command:
                removed = True
                out = ''
            elif 'ps' in command:
                out = '' if removed else container
            else:
                out = ''
            return subprocess.CompletedProcess(command, 0, out, '')
        with patch.object(fixture.subprocess, 'run', side_effect=run):
            with fixture.temporary_postgres() as db:
                self.assertEqual(db.container_id, container)
                self.assertGreaterEqual(len(db.password), 32)
                self.assertIn(container, db.psql_command('postgres', 'postgres'))
        run_command = next(command for command in calls if 'run' in command)
        self.assertNotIn('--publish', run_command)
        self.assertEqual(run_command[run_command.index('--network') + 1], 'none')
        self.assertTrue(any('rm' in command and container in command for command in calls))

    def test_wrong_ownership_never_yields_or_removes_container(self):
        image = 'sha256:' + 'a' * 64
        container = 'b' * 64
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            if 'image' in command: out = image
            elif 'run' in command: out = container
            elif 'inspect' in command:
                out = json.dumps({'Id': container, 'Image': image, 'State': {'Running': True},
                                  'Config': {'Labels': {'soleur.holder-evidence-test': 'other'}},
                                  'HostConfig': {'Binds': None, 'NetworkMode': 'none', 'Tmpfs': {'/var/lib/postgresql/data': 'rw'}},
                                  'Mounts': [], 'NetworkSettings': {'Ports': {}}})
            elif 'ps' in command: out = container
            else: out = ''
            return subprocess.CompletedProcess(command, 0, out, '')
        with patch.object(fixture.subprocess, 'run', side_effect=run):
            with self.assertRaises(RuntimeError):
                with fixture.temporary_postgres(): self.fail('must refuse before connecting')
        self.assertFalse(any('rm' in command for command in calls))

    def test_failed_start_with_no_owned_container_preserves_failure(self):
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            if 'image' in command: return subprocess.CompletedProcess(command, 0, 'sha256:' + 'a' * 64, '')
            if 'run' in command: return subprocess.CompletedProcess(command, 1, '', 'private')
            return subprocess.CompletedProcess(command, 0, '', '')
        with patch.object(fixture.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'synthetic container cleanup unknown: name=soleur-holder-test-'):
                with fixture.temporary_postgres(): self.fail('must not yield')
        self.assertFalse(any('rm' in command for command in calls))

    def test_lost_start_response_removes_only_reconciled_owned_container(self):
        image = 'sha256:' + 'a' * 64
        container = 'b' * 64
        marker = None
        removed = False
        def run(command, **kwargs):
            nonlocal marker, removed
            if 'image' in command: out = image
            elif 'run' in command:
                marker = command[command.index('--label') + 1].split('=', 1)[1]
                raise subprocess.TimeoutExpired(command, 15)
            elif 'inspect' in command:
                out = json.dumps({'Id': container, 'Image': image, 'Config': {'Labels': {'soleur.holder-evidence-test': marker}}})
            elif 'rm' in command:
                self.assertIn(container, command)
                removed = True
                out = ''
            elif 'ps' in command: out = '' if removed else container
            else: out = ''
            return subprocess.CompletedProcess(command, 0, out, '')
        with patch.object(fixture.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'synthetic Docker operation timed out'):
                with fixture.temporary_postgres(): self.fail('must not yield')
        self.assertTrue(removed)


if __name__ == '__main__':
    unittest.main()

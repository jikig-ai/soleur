"""Synthetic image Config observation and file-only manifest tests."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

import image_observations as observations
from operational import ROLES
from prepare import Refused, canonical, sha
from test_controller_adapters import contract as adapter_contract, seal


IMAGE_A = 'sha256:' + 'a' * 64
IMAGE_B = 'sha256:' + 'b' * 64
PAIRING = '1' * 64
OPERATIONAL = '2' * 64
CONFIG = {'Entrypoint': ['docker-entrypoint.sh'], 'Cmd': ['node', 'dist/server/index.cjs'],
          'Env': [], 'User': 'soleur', 'WorkingDir': '/app', 'Healthcheck': None,
          'ExposedPorts': {}, 'Volumes': {}, 'OnBuild': None}


class ImageObservations(unittest.TestCase):
    def setUp(self):
        self.ids = {role: IMAGE_A if role in ('renderer', 'browser') else IMAGE_B for role in ROLES}
        self.transport = Mock()
        self.transport.request.side_effect = lambda method, path, payload, *, timeout: (
            200, {'Id': path.split('/')[2], 'Config': copy.deepcopy(CONFIG)})
        self.clock = Mock(return_value=10.0)
        self.contract = adapter_contract()
        self.contract['source_references']['scripts/codex-qualification/image_observations.py'] = {
            'sha256': sha(Path(observations.__file__).read_bytes())}
        seal(self.contract)

    def collector(self):
        return observations.ImageObservationCollector(self.contract, self.transport, self.ids,
                                                     clock=self.clock)

    def test_manifest_is_finite_exact_get_only_and_has_no_authority(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        self.assertEqual(value['version'], 1)
        self.assertEqual(value['pairing_sha256'], PAIRING)
        self.assertEqual(value['operational_sha256'], OPERATIONAL)
        self.assertFalse(value['execute_authorized'])
        self.assertFalse(value['profile_admissible'])
        self.assertEqual(value['issuer_verification'], 'pending')
        self.assertEqual(len(value['actions']), 2)
        self.assertTrue(all(action['method'] == 'GET' and action['payload_sha256'] is None
                            and action['read_only'] is True and action['approval_required'] is True
                            for action in value['actions']))
        self.assertNotIn('endpoint', value)
        self.assertNotIn('image_config', value)

    def test_collector_deduplicates_exact_immutable_ids_and_keeps_authority_pending(self):
        result = self.collector().collect(timeout=30)
        self.assertEqual(self.transport.request.call_count, 2)
        self.transport.request.assert_any_call('GET', '/images/' + IMAGE_A + '/json', b'', timeout=30)
        self.transport.request.assert_any_call('GET', '/images/' + IMAGE_B + '/json', b'', timeout=30)
        self.assertEqual(set(result['roles']), set(ROLES))
        self.assertEqual(result['roles']['renderer']['image_config_sha256'],
                         hashlib.sha256(canonical(CONFIG)).hexdigest())
        for field in ('execute_authorized', 'profile_admissible', 'authentication_established',
                      'ownership_verified', 'quiescence_verified'):
            self.assertFalse(result[field])
        self.assertEqual(result['issuer_verification'], 'pending')
        self.assertEqual(result['independent_review'], 'pending')

    def test_one_deadline_shrinks_across_images_and_pass_cannot_repeat(self):
        self.clock = Mock(side_effect=[10.0, 11.0, 12.0, 15.0, 16.0, 17.0, 18.0, 19.0])
        collector = self.collector()
        collector.collect(timeout=30)
        calls = self.transport.request.call_args_list
        self.assertEqual([call.kwargs['timeout'] for call in calls], [29.0, 24.0])
        with self.assertRaises(Refused):
            collector.collect(timeout=30)

    def test_non_200_wrong_image_incomplete_config_and_oversize_refuse(self):
        variants = [
            (403, {'Id': IMAGE_A, 'Config': CONFIG}),
            (200, {'Id': IMAGE_B, 'Config': CONFIG}),
            (200, {'Id': IMAGE_A, 'Config': {'Cmd': ['x']}}),
            (200, {'Id': IMAGE_A, 'Config': {**CONFIG, 'Env': ['X=' + 'x' * 1_048_576]}}),
        ]
        for status, receipt in variants:
            self.transport.request.reset_mock()
            self.transport.request.side_effect = None
            self.transport.request.return_value = (status, receipt)
            with self.subTest(status=status, keys=tuple(receipt)), self.assertRaises(Refused):
                self.collector().collect(timeout=30)
            self.transport.request.assert_called_once()

    def test_construction_does_no_transport_io_and_invalid_timeout_makes_no_calls(self):
        value = self.collector()
        self.transport.request.assert_not_called()
        with self.assertRaises(Refused):
            value.collect(timeout=0)
        with self.assertRaises(Refused):
            value.collect(timeout=10 ** 1000)
        self.transport.request.assert_not_called()
        self.clock = Mock(return_value=10 ** 1000)
        with self.assertRaises(Refused):
            self.collector()
        self.transport.request.assert_not_called()

    def test_contract_source_binding_is_checked_before_transport_use(self):
        self.contract['source_references']['scripts/codex-qualification/image_observations.py']['sha256'] = '0' * 64
        seal(self.contract)
        with self.assertRaises(Refused):
            self.collector()
        self.transport.request.assert_not_called()

    def test_action_manifest_writer_is_exclusive_file_only_and_content_bound(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'image-observation-manifest.json'
            digest = observations.write_action_manifest(path, value)
            payload = path.read_bytes()
            self.assertEqual(digest, hashlib.sha256(payload).hexdigest())
            self.assertEqual(json.loads(payload), value)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(Refused):
                observations.write_action_manifest(path, value)
            self.assertEqual(path.read_bytes(), payload)

    def test_manifest_writer_refuses_symlink_and_does_not_touch_target(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'target'
            target.write_bytes(b'untouched')
            link = Path(directory) / 'manifest'
            link.symlink_to(target)
            with self.assertRaises(Refused):
                observations.write_action_manifest(link, value)
            self.assertEqual(target.read_bytes(), b'untouched')
            self.assertTrue(link.is_symlink())

    def test_invalid_role_map_or_hashes_refuse_before_transport(self):
        for ids, pairing, operational in [({}, PAIRING, OPERATIONAL),
                                            ({**self.ids, 'unknown': IMAGE_A}, PAIRING, OPERATIONAL),
                                            (self.ids, 'x', OPERATIONAL),
                                            (self.ids, PAIRING, 'x')]:
            with self.subTest(pairing=pairing, operational=operational), self.assertRaises(Refused):
                observations.action_manifest(ids, pairing, operational)
        self.transport.request.assert_not_called()


if __name__ == '__main__':
    unittest.main()

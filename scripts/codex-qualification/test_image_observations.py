"""Synthetic image Config observation and file-only manifest tests."""
import copy
import errno
import hashlib
import json
import os
import stat
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

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
        self.assertIs(value['execute_authorized'], False)
        self.assertIs(value['profile_admissible'], False)
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
            self.assertIs(result[field], False)
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
            digest = observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
            payload = path.read_bytes()
            self.assertEqual(digest, hashlib.sha256(payload).hexdigest())
            self.assertEqual(json.loads(payload), value)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(Refused):
                observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
            self.assertEqual(path.read_bytes(), payload)

    def test_manifest_writer_refuses_symlink_and_does_not_touch_target(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'target'
            target.write_bytes(b'untouched')
            link = Path(directory) / 'manifest'
            link.symlink_to(target)
            with self.assertRaises(Refused):
                observations.write_action_manifest(link, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
            self.assertEqual(target.read_bytes(), b'untouched')
            self.assertTrue(link.is_symlink())

    def test_manifest_writer_rejects_tampering_without_creating_files(self):
        original = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        mutations = []
        for change, message in (
                (lambda value: value['actions'][0].update(method='POST'), 'Exact bounded GET-only'),
                (lambda value: value['actions'][0].update(path='/images/sha256:' + 'c' * 64 + '/json'),
                 'Exact bounded GET-only'),
                (lambda value: value['actions'][0].update(roles=['renderer']), 'Complete role-to-image'),
                (lambda value: value.update(extra='field'), 'Structured action manifest'),
                (lambda value: value.update(pairing_sha256='3' * 64), 'Exact bounded GET-only'),
                (lambda value: value.update(execute_authorized=True), 'Exact bounded GET-only')):
            altered = copy.deepcopy(original)
            change(altered)
            mutations.append((altered, message))
        with tempfile.TemporaryDirectory() as directory:
            for index, (altered, message) in enumerate(mutations):
                path = Path(directory) / ('manifest-' + str(index))
                with self.subTest(index=index), self.assertRaisesRegex(
                        Refused, message):
                    observations.write_action_manifest(path, altered, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
                self.assertFalse(path.exists())

    def test_manifest_writer_cleans_partial_write_zero_progress_and_fsync_failure(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        for failure in ('partial', 'zero', 'fsync'):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'manifest'
                with self.subTest(failure=failure):
                    if failure == 'partial':
                        # The second write fails after a real partial write.
                        calls = [0]
                        real_write = os.write
                        def partial_write(fd, data):
                            calls[0] += 1
                            if calls[0] == 1:
                                return real_write(fd, data[:max(1, len(data) // 2)])
                            raise OSError('SYNTHETIC_WRITE_FAILURE')
                        with patch.object(observations.os, 'write', side_effect=partial_write):
                            with self.assertRaisesRegex(Refused, 'File-only action manifest write failed'):
                                observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
                    elif failure == 'zero':
                        with patch.object(observations.os, 'write', return_value=0):
                            with self.assertRaisesRegex(Refused, 'File-only action manifest write failed'):
                                observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
                    else:
                        with patch.object(observations.os, 'fsync', side_effect=OSError('SYNTHETIC_FSYNC_FAILURE')):
                            with self.assertRaisesRegex(Refused, 'File-only action manifest write failed'):
                                observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
                    self.assertFalse(path.exists())

    def test_manifest_writer_close_errors_are_sanitized_and_cleanup_is_complete(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        for fsync_fails in (True, False):
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'manifest'
                real_close = os.close
                attempts = [0]

                def fail_fsync(fd):
                    raise OSError('SYNTHETIC_FSYNC_FAILURE')

                def close_releases_then_fails(fd):
                    if stat.S_ISREG(os.fstat(fd).st_mode) and attempts[0] == 0:
                        attempts[0] += 1
                        real_close(fd)
                        raise OSError('SYNTHETIC_CLOSE_FAILURE')
                    return real_close(fd)

                fsync_context = (patch.object(observations.os, 'fsync', side_effect=fail_fsync)
                                 if fsync_fails else patch.object(observations.os, 'fsync', wraps=os.fsync))
                with fsync_context, patch.object(observations.os, 'close', side_effect=close_releases_then_fails):
                    with self.subTest(fsync_fails=fsync_fails), self.assertRaisesRegex(
                            Refused, 'File-only action manifest write failed') as caught:
                        observations.write_action_manifest(path, value, pairing_sha256=PAIRING,
                                                           operational_sha256=OPERATIONAL)
                self.assertTrue(caught.exception.__suppress_context__)
                self.assertNotIn('SYNTHETIC_', ''.join(__import__('traceback').format_exception(caught.exception)))
                self.assertEqual(attempts[0], 1)
                self.assertFalse(path.exists())

    def test_manifest_writer_directory_close_failure_does_not_leak_next_descriptor(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest'
            root = os.stat('/')
            real_open = os.open
            real_close = os.close
            attempts = [0]
            opened_directories = []

            def record_open(file, flags, mode=0o777, *, dir_fd=None):
                descriptor = real_open(file, flags, mode, dir_fd=dir_fd)
                if flags & os.O_DIRECTORY:
                    opened_directories.append(descriptor)
                return descriptor

            def root_close_releases_then_fails(fd):
                metadata = os.fstat(fd)
                if (metadata.st_dev, metadata.st_ino) == (root.st_dev, root.st_ino) and attempts[0] == 0:
                    attempts[0] += 1
                    real_close(fd)
                    raise OSError('SYNTHETIC_DIRECTORY_CLOSE_FAILURE')
                return real_close(fd)

            try:
                with patch.object(observations.os, 'open', side_effect=record_open), \
                        patch.object(observations.os, 'close', side_effect=root_close_releases_then_fails):
                    with self.assertRaisesRegex(Refused, 'File-only action manifest write failed') as caught:
                        observations.write_action_manifest(path, value, pairing_sha256=PAIRING,
                                                           operational_sha256=OPERATIONAL)
                self.assertTrue(caught.exception.__suppress_context__)
                self.assertEqual(attempts[0], 1)
                self.assertFalse(path.exists())
                for descriptor in opened_directories:
                    with self.subTest(descriptor=descriptor), self.assertRaises(OSError):
                        os.fstat(descriptor)
            finally:
                for descriptor in opened_directories:
                    try:
                        os.fstat(descriptor)
                    except OSError as error:
                        self.assertEqual(error.errno, errno.EBADF)
                    else:
                        real_close(descriptor)

    def test_manifest_writer_final_parent_close_failure_refuses_success_digest(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest'
            parent = os.stat(directory)
            real_close = os.close
            attempts = []
            def release_final_parent_then_fail(descriptor):
                metadata = os.fstat(descriptor)
                if (metadata.st_dev, metadata.st_ino) == (parent.st_dev, parent.st_ino):
                    attempts.append(descriptor)
                    real_close(descriptor)
                    raise OSError('SYNTHETIC_FINAL_PARENT_CLOSE_FAILURE')
                return real_close(descriptor)
            with patch.object(observations.os, 'close', side_effect=release_final_parent_then_fail):
                with self.assertRaisesRegex(Refused, '^File-only action manifest write failed$') as caught:
                    observations.write_action_manifest(path, value, pairing_sha256=PAIRING,
                                                       operational_sha256=OPERATIONAL)
            self.assertEqual(len(attempts), 1)
            self.assertTrue(caught.exception.__suppress_context__)
            self.assertNotIn('SYNTHETIC_', ''.join(__import__('traceback').format_exception(caught.exception)))
            with self.assertRaises(OSError) as closed:
                os.fstat(attempts[0])
            self.assertEqual(closed.exception.errno, errno.EBADF)

    def test_manifest_writer_unlink_failure_preserves_refusal_without_close_retry(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest'
            real_close = os.close
            regular_closes = []
            def record_close(descriptor):
                if stat.S_ISREG(os.fstat(descriptor).st_mode):
                    regular_closes.append(descriptor)
                return real_close(descriptor)
            with patch.object(observations.os, 'fsync', side_effect=OSError('SYNTHETIC_PRIMARY_FSYNC_FAILURE')), \
                    patch.object(observations.os, 'unlink', side_effect=OSError('SYNTHETIC_UNLINK_FAILURE')) as unlink, \
                    patch.object(observations.os, 'close', side_effect=record_close):
                with self.assertRaisesRegex(Refused, '^File-only action manifest write failed$') as caught:
                    observations.write_action_manifest(path, value, pairing_sha256=PAIRING,
                                                       operational_sha256=OPERATIONAL)
            unlink.assert_called_once()
            self.assertEqual(len(regular_closes), 1)
            self.assertTrue(caught.exception.__suppress_context__)
            self.assertNotIn('SYNTHETIC_', ''.join(__import__('traceback').format_exception(caught.exception)))
            self.assertTrue(path.is_file())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_manifest_writer_pins_parent_and_refuses_parent_swap(self):
        value = observations.action_manifest(self.ids, PAIRING, OPERATIONAL)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / 'parent'
            moved = root / 'moved'
            outside = root / 'outside'
            parent.mkdir()
            outside.mkdir()
            target = outside / 'manifest'
            target.write_bytes(b'untouched')
            path = parent / 'manifest'
            real_open = os.open
            swapped = [False]

            def swap_before_leaf_open(file, flags, mode=0o777, *, dir_fd=None):
                if file == path.name and dir_fd is not None and not swapped[0]:
                    parent.rename(moved)
                    parent.symlink_to(outside, target_is_directory=True)
                    swapped[0] = True
                return real_open(file, flags, mode, dir_fd=dir_fd)

            with patch.object(observations.os, 'open', side_effect=swap_before_leaf_open):
                with self.assertRaisesRegex(Refused, 'File-only action manifest write failed'):
                    observations.write_action_manifest(path, value, pairing_sha256=PAIRING, operational_sha256=OPERATIONAL)
            self.assertTrue(swapped[0])
            self.assertEqual(target.read_bytes(), b'untouched')
            self.assertFalse((moved / 'manifest').exists())

    def test_invalid_role_map_or_hashes_refuse_before_transport(self):
        for ids, pairing, operational in [({}, PAIRING, OPERATIONAL),
                                            ({**self.ids, 'unknown': IMAGE_A}, PAIRING, OPERATIONAL),
                                            (self.ids, 'x', OPERATIONAL),
                                            (self.ids, PAIRING, 'x')]:
            with self.subTest(pairing=pairing, operational=operational), self.assertRaises(Refused):
                observations.action_manifest(ids, pairing, operational)
        self.transport.request.assert_not_called()

    def test_transport_lookup_and_request_errors_are_sanitized_and_pass_cannot_retry(self):
        class BadTransport:
            @property
            def request(self):
                raise RuntimeError('SYNTHETIC_PRIVATE_TRANSPORT_LOOKUP')

        with self.assertRaisesRegex(Refused, 'Explicit read transport required') as caught:
            observations.ImageObservationCollector(self.contract, BadTransport(), self.ids,
                                                   clock=self.clock)
        self.assertTrue(caught.exception.__suppress_context__)
        self.transport.request.side_effect = RuntimeError('SYNTHETIC_PRIVATE_TRANSPORT_REQUEST')
        collector = self.collector()
        with self.assertRaisesRegex(Refused, 'Image Config observation request failed') as caught:
            collector.collect(timeout=30)
        self.assertTrue(caught.exception.__suppress_context__)
        self.assertNotIn('SYNTHETIC_PRIVATE', ''.join(__import__('traceback').format_exception(caught.exception)))
        with self.assertRaisesRegex(Refused, 'One image observation pass only'):
            collector.collect(timeout=30)
        self.assertEqual(self.transport.request.call_count, 1)

    def test_clock_and_config_errors_are_sanitized(self):
        def private_clock_error():
            raise RuntimeError('SYNTHETIC_PRIVATE_CLOCK')
        with self.assertRaisesRegex(Refused, 'Image observation clock failed') as caught:
            observations.ImageObservationCollector(self.contract, self.transport, self.ids,
                                                   clock=private_clock_error)
        self.assertTrue(caught.exception.__suppress_context__)
        self.clock = Mock(side_effect=[10.0, RuntimeError('SYNTHETIC_PRIVATE_CLOCK')])
        collector = self.collector()
        with self.assertRaisesRegex(Refused, 'Image observation clock failed') as caught:
            collector.collect(timeout=30)
        self.assertTrue(caught.exception.__suppress_context__)
        self.assertNotIn('SYNTHETIC_PRIVATE', ''.join(__import__('traceback').format_exception(caught.exception)))
        self.clock = Mock(side_effect=[10.0, 11.0, 12.0])
        collector = self.collector()
        self.transport.request.side_effect = RuntimeError('SYNTHETIC_PRIVATE_CONFIG')
        # Parsing errors arise after a successful request returns a non-JSON object.
        class BadValue:
            def __deepcopy__(self, memo):
                raise RuntimeError('SYNTHETIC_PRIVATE_CONFIG')
        self.transport.request.side_effect = lambda *args, **kwargs: (
            200, {'Id': IMAGE_A, 'Config': {**CONFIG, 'Synthetic': BadValue()}})
        with self.assertRaisesRegex(Refused, 'Image Config observation parsing failed') as caught:
            collector.collect(timeout=30)
        self.assertTrue(caught.exception.__suppress_context__)
        self.assertNotIn('SYNTHETIC_PRIVATE', ''.join(__import__('traceback').format_exception(caught.exception)))

    def test_late_backward_and_nonfinite_collection_clocks_refuse_without_retry(self):
        sequences = (([10.0, 11.0, 41.0], 1),  # Expired after the first response.
                     ([10.0, 11.0, 12.0, 41.0], 1),  # Expired after Config parsing.
                     ([10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 41.0], 2),  # Final return bound.
                     ([10.0, 9.0], 0), ([10.0, float('nan')], 0),
                     ([10.0, 11.0, 9.0], 1), ([10.0, 11.0, float('inf')], 1))
        for values, expected_calls in sequences:
            self.clock = Mock(side_effect=values)
            self.transport.request.reset_mock()
            self.transport.request.side_effect = lambda method, path, payload, *, timeout: (
                200, {'Id': path.split('/')[2], 'Config': copy.deepcopy(CONFIG)})
            collector = self.collector()
            with self.subTest(values=values), self.assertRaises(Refused):
                collector.collect(timeout=30)
            calls = self.transport.request.call_count
            self.assertEqual(calls, expected_calls)
            with self.assertRaisesRegex(Refused, 'One image observation pass only'):
                collector.collect(timeout=30)
            self.assertEqual(self.transport.request.call_count, calls)


if __name__ == '__main__':
    unittest.main()

"""Synthetic descriptor fixtures; no Docker volumes or customer files are read."""
import copy
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from prepare import Refused, canonical, sha
import retained_files


class RetainedFiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex9051-retained-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'nested').mkdir(mode=0o700)
        (self.root / 'nested/object.bin').write_bytes(b'\x00synthetic storage\xff')
        (self.root / 'workspace.txt').write_bytes(b'synthetic workspace\n')
        for name in ('nested/object.bin', 'workspace.txt'):
            (self.root / name).chmod(0o600)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.addCleanup(os.close, self.fd)
        info = os.fstat(self.fd)
        self.binding = {'attempt': 'fixture-attempt', 'source_sha': 'a' * 40,
                        'pairing_sha256': 'b' * 64, 'resource_kind': 'workspace',
                        'resource_id': 'c' * 64, 'root_device': info.st_dev,
                        'root_inode': info.st_ino, 'quiescence_id': 'd' * 64}
        self.census = ['nested', 'nested/object.bin', 'workspace.txt']

    def snapshot(self, **kwargs):
        return retained_files.snapshot(self.fd, self.binding, self.census, **kwargs)

    def test_complete_byte_type_mode_manifest_and_positive_retention(self):
        before = self.snapshot()
        rows = {row['path']: row for row in before['entries']}
        self.assertEqual(set(rows), set(self.census))
        self.assertEqual(rows['nested']['type'], 'directory')
        self.assertEqual(rows['workspace.txt']['mode'], 0o600)
        self.assertEqual(rows['nested/object.bin']['sha256'], sha(b'\x00synthetic storage\xff'))
        self.assertEqual(rows['nested/object.bin']['bytes'], len(b'\x00synthetic storage\xff'))
        self.assertEqual(before['manifest_sha256'], sha(canonical(before['entries'])))
        self.assertNotIn('synthetic storage', str(before))
        after_binding = dict(self.binding, quiescence_id='e' * 64)
        after = retained_files.snapshot(self.fd, after_binding, self.census)
        self.assertEqual(retained_files.compare(before, after)['status'], 'structurally-matched')
        self.assertFalse(before['ownership_verified'])
        self.assertFalse(before['execute_authorized'])

    def test_added_missing_changed_type_and_mode_are_discriminated(self):
        before = self.snapshot()
        (self.root / 'extra').write_bytes(b'synthetic extra')
        with self.assertRaises(Refused):
            self.snapshot()
        (self.root / 'extra').unlink()
        (self.root / 'workspace.txt').write_bytes(b'changed synthetic bytes')
        with self.assertRaises(Refused):
            retained_files.compare(before, self.snapshot())
        (self.root / 'workspace.txt').write_bytes(b'synthetic workspace\n')
        (self.root / 'workspace.txt').chmod(0o644)
        with self.assertRaises(Refused):
            retained_files.compare(before, self.snapshot())
        (self.root / 'workspace.txt').unlink()
        with self.assertRaises(Refused):
            self.snapshot()

    def test_exact_scoped_erasure_preserves_every_other_entry(self):
        before = self.snapshot()
        (self.root / 'nested/object.bin').unlink()
        after = retained_files.snapshot(self.fd, self.binding, ['nested', 'workspace.txt'])
        self.assertEqual(retained_files.compare(before, after, ['nested/object.bin'])['status'],
                         'structurally-matched')
        for removed in ([], ['absent'], ['nested/object.bin', 'nested/object.bin'], ['nested']):
            with self.subTest(removed=removed), self.assertRaises(Refused):
                retained_files.compare(before, after, removed)

    def test_empty_scope_after_exact_full_erasure_is_measured(self):
        before = self.snapshot()
        (self.root / 'nested/object.bin').unlink()
        (self.root / 'nested').rmdir()
        (self.root / 'workspace.txt').unlink()
        after = retained_files.snapshot(self.fd, self.binding, [])
        self.assertEqual(after['entries'], [])
        self.assertEqual(retained_files.compare(before, after, self.census)['status'], 'structurally-matched')

    def test_root_mode_and_incomplete_directory_census_refuse(self):
        before = self.snapshot()
        self.root.chmod(0o755)
        with self.assertRaises(Refused):
            retained_files.compare(before, self.snapshot())
        incomplete = copy.deepcopy(before)
        incomplete['entries'] = [row for row in incomplete['entries'] if row['path'] != 'nested']
        paths = [row['path'] for row in incomplete['entries']]
        incomplete['fixture_census_sha256'] = sha(canonical(paths))
        incomplete['manifest_sha256'] = sha(canonical(incomplete['entries']))
        with self.assertRaises(Refused):
            retained_files.compare(incomplete, incomplete)

    def test_symlink_hardlink_fifo_and_unsafe_census_refuse(self):
        target = self.root / 'workspace.txt'
        original = target.read_bytes()
        target.unlink()
        target.symlink_to('/etc/passwd')
        with self.assertRaises(Refused):
            self.snapshot()
        target.unlink()
        target.write_bytes(original)
        os.link(target, self.root / 'hardlink')
        with self.assertRaises(Refused):
            retained_files.snapshot(self.fd, self.binding, self.census + ['hardlink'])
        (self.root / 'hardlink').unlink()
        target.unlink()
        os.mkfifo(target)
        with self.assertRaises(Refused):
            self.snapshot()
        for census in ([], ['../escape'], ['/etc/passwd'], ['a//b'], ['nested', 'nested']):
            with self.subTest(census=census), self.assertRaises(Refused):
                retained_files.snapshot(self.fd, self.binding, census)

    def test_wrong_root_binding_unbounded_files_and_bytes_refuse(self):
        for key, value in [('root_inode', 0), ('root_device', -1), ('attempt', ''),
                           ('source_sha', 'short'), ('resource_kind', 'customer'),
                           ('resource_id', ''), ('quiescence_id', None)]:
            with self.subTest(key=key), self.assertRaises(Refused):
                retained_files.snapshot(self.fd, dict(self.binding, **{key: value}), self.census)
        with self.assertRaises(Refused):
            self.snapshot(max_entries=2)
        with self.assertRaises(Refused):
            self.snapshot(max_bytes=4)

    def test_replacement_during_descriptor_read_refuses(self):
        original = retained_files.read_regular
        def replace(parent, name, info, remaining):
            value = original(parent, name, info, remaining)
            if name == 'workspace.txt':
                os.rename('workspace.txt', 'old', src_dir_fd=parent, dst_dir_fd=parent)
                with open(self.root / 'workspace.txt', 'wb') as stream:
                    stream.write(b'replaced synthetic bytes')
            return value
        with patch('retained_files.read_regular', side_effect=replace), self.assertRaises(Refused):
            self.snapshot()

    def test_forged_hash_duplicate_inventory_and_binding_drift_refuse(self):
        before = self.snapshot()
        for mutate in (
                lambda x: x['entries'][1].update(sha256='e' * 64),
                lambda x: x['entries'].append(copy.deepcopy(x['entries'][0])),
                lambda x: x['binding'].update(resource_id='e' * 64)):
            after = copy.deepcopy(before)
            mutate(after)
            with self.assertRaises(Refused):
                retained_files.compare(before, after)

    def test_matching_forged_manifests_are_not_retention_evidence(self):
        forged = self.snapshot()
        forged['manifest_sha256'] = 'e' * 64
        with self.assertRaises(Refused):
            retained_files.compare(forged, copy.deepcopy(forged))

    def test_integrity_oracle_detects_deleted_manifest_validation(self):
        result = unittest.TestResult()
        with patch('retained_files.checked_manifest', side_effect=lambda value: value['entries']):
            unittest.FunctionTestCase(self.test_matching_forged_manifests_are_not_retention_evidence).run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(len(result.failures), 1)
        self.assertIn('Refused not raised', result.failures[0][1])


if __name__ == '__main__':
    unittest.main()

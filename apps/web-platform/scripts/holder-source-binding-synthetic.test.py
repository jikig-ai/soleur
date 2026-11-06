import hashlib
import importlib.util
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('source_binding', pathlib.Path(__file__).with_name('holder-source-binding-synthetic.py'))
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)
NODE = shutil.which('node')


@unittest.skipUnless(NODE, 'Node is required for this synthetic test')
class SourceBindingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-source-')
        self.addCleanup(self.temp.cleanup)
        self.artifact = pathlib.Path(self.temp.name) / 'artifact.mjs'
        self.source = b"if (process.env.NODE_OPTIONS || process.env.NODE_PATH) process.exit(9);\n"
        self.artifact.write_bytes(self.source)
        self.digest = hashlib.sha256(self.source).hexdigest()

    def test_executes_the_verified_bytes_in_a_sanitized_environment(self):
        with patch.dict(os.environ, {'NODE_OPTIONS': '--require=/nonexistent', 'NODE_PATH': '/nonexistent'}):
            self.assertEqual(binding.run_synthetic(self.artifact, self.digest, NODE), 'synthetic_pass')

    def test_modified_file_digest_and_symlink_are_refused(self):
        with patch.object(binding.subprocess, 'run') as child:
            self.assertEqual(binding.run_synthetic(self.artifact, '0' * 64, NODE), 'refused')
            child.assert_not_called()
        link = pathlib.Path(self.temp.name) / 'link.mjs'
        link.symlink_to(self.artifact)
        self.assertEqual(binding.run_synthetic(link, self.digest, NODE), 'refused')
        self.artifact.write_bytes(b'process.exit(7);')
        self.assertEqual(binding.run_synthetic(self.artifact, self.digest, NODE), 'refused')

    def test_replacement_after_read_cannot_change_executed_bytes(self):
        original = subprocess.run
        def replace_then_run(*args, **kwargs):
            self.artifact.write_bytes(b'process.exit(7);')
            self.assertEqual(kwargs['input'], self.source)
            return original(*args, **kwargs)
        with patch.object(binding.subprocess, 'run', side_effect=replace_then_run):
            self.assertEqual(binding.run_synthetic(self.artifact, self.digest, NODE), 'synthetic_pass')

    def test_invalid_inputs_and_nonregular_sources_refuse(self):
        self.assertEqual(binding.run_synthetic(self.artifact.parent, self.digest, NODE), 'refused')
        self.assertEqual(binding.run_synthetic(self.artifact, 'not-a-digest', NODE), 'refused')
        self.assertEqual(binding.run_synthetic(self.artifact, self.digest, 'node'), 'refused')
        self.artifact.write_bytes(b'x' * (binding.MAX_BYTES + 1))
        self.assertEqual(binding.run_synthetic(self.artifact, hashlib.sha256(self.artifact.read_bytes()).hexdigest(), NODE), 'refused')

    def test_child_failure_is_refused(self):
        self.artifact.write_bytes(b'process.exit(7);')
        digest = hashlib.sha256(self.artifact.read_bytes()).hexdigest()
        self.assertEqual(binding.run_synthetic(self.artifact, digest, NODE), 'refused')

    def test_child_timeout_is_refused_without_exposing_error(self):
        with patch.object(binding.subprocess, 'run', side_effect=subprocess.TimeoutExpired('private', 5)):
            self.assertEqual(binding.run_synthetic(self.artifact, self.digest, NODE), 'refused')


if __name__ == '__main__':
    unittest.main()

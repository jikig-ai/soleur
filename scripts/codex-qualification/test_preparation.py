"""Current-source/full-schema pairing and synthetic browser admission fixtures."""
import base64
import copy
import hashlib
import hmac
import json
from pathlib import Path
import shutil
import subprocess
import unittest
from prepare import Refused, browser_contract, controlled_dockerfile, git, preparation, synthetic_browser_config, validate_image_receipt

REPO = Path(__file__).resolve().parents[2]

class Preparation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = git(REPO, 'rev-parse', 'HEAD').decode().strip()
        cls.contract = preparation(REPO, cls.source)

    def test_complete_schema_set_matches_source_tree(self):
        actual = {row['path'] for row in self.contract['forward_migrations']}
        expected = set(git(REPO, 'ls-tree', '-r', '--name-only', self.source, '--',
                           'apps/web-platform/supabase/migrations').decode().splitlines())
        expected = {path for path in expected if path.endswith('.sql') and not path.endswith('.down.sql')}
        self.assertEqual(actual, expected)
        self.assertGreater(len(actual), 180)
        for row in self.contract['forward_migrations']:
            content = git(REPO, 'cat-file', 'blob', row['blob'])
            self.assertEqual(hashlib.sha256(content).hexdigest(), row['sha256'])

    def test_no_operational_approval_or_image_is_inferred(self):
        self.assertFalse(self.contract['candidate']['build_authorized'])
        self.assertFalse(self.contract['rehearsal']['execute_available'])
        self.assertIsNone(self.contract['candidate']['image_id'])
        self.assertEqual(set(self.contract['operations'].values()), {0})
        with self.assertRaises(Refused):
            validate_image_receipt(self.contract, None)

    def receipt(self):
        return {'identity': copy.deepcopy(self.contract['identity']),
                'image_id': 'sha256:' + 'a' * 64, 'user': 'soleur',
                'cmd': ['node', 'dist/server/index.cjs'],
                'browser_anon_key_sha256': self.contract['browser']['anon_key_sha256'],
                'browser_auth_probe': 'passed-owned-local-synthetic-auth'}

    def test_receipt_requires_every_identity_dimension(self):
        validate_image_receipt(self.contract, self.receipt())
        for field in self.contract['identity']:
            receipt = self.receipt()
            receipt['identity'][field] = 'different'
            with self.assertRaises(Refused):
                validate_image_receipt(self.contract, receipt)
        for field, value in [('image_id', 'mutable-tag'), ('user', 'root'),
                             ('cmd', ['node', 'mock-server.js']), ('browser_anon_key_sha256', 'different'),
                             ('browser_auth_probe', 'not-run')]:
            receipt = self.receipt()
            receipt[field] = value
            with self.assertRaises(Refused):
                validate_image_receipt(self.contract, receipt)

    def test_synthetic_key_is_signed_and_never_serialized_in_contract(self):
        config = synthetic_browser_config()
        header, payload, signature = config['anon_key'].split('.')
        expected = base64.urlsafe_b64encode(hmac.new(config['signing_material'].encode(),
                      (header + '.' + payload).encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
        self.assertEqual(signature, expected)
        self.assertEqual(json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4))), config['claims'])
        self.assertNotIn(config['anon_key'], json.dumps(self.contract))
        self.assertNotIn(config['signing_material'], json.dumps(self.contract))
        self.assertFalse(browser_contract()['provider_credentials'])

    def test_candidate_passes_actual_production_browser_guards(self):
        config = synthetic_browser_config()
        js = '''import {assertProdSupabaseUrl as url} from './apps/web-platform/lib/supabase/validate-url.ts';
import {assertProdSupabaseAnonKey as key} from './apps/web-platform/lib/supabase/validate-anon-key.ts';
let input='';for await(const chunk of process.stdin)input+=chunk;
const config=JSON.parse(input);url(config.url);key(config.anon_key,config.url);
for(const changed of ['http://127.0.0.1:59051','https://placeholder.supabase.co']){
let refused=false;try{url(changed)}catch{refused=true}if(!refused)throw Error('Unsafe URL admitted')}
let refused=false;try{key('synthetic-build-only-not-authentication',config.url)}catch{refused=true}
if(!refused)throw Error('Old candidate key admitted');console.log('actual-production-guards=pass');'''
        node = shutil.which('node')
        self.assertIsNotNone(node, 'Node is required for the actual validator fixture')
        result = subprocess.run([node, '--experimental-strip-types', '--input-type=module', '-e', js],
                    cwd=REPO, env={'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent/codex9051-fixtures',
                                   'NODE_ENV': 'production', 'NODE_OPTIONS': ''},
                    input=json.dumps(config), text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'actual-production-guards=pass')

    def test_compiler_controls_preserve_production_validator_source(self):
        original = git(REPO, 'show', self.source + ':apps/web-platform/Dockerfile').decode()
        controlled = controlled_dockerfile(original)
        self.assertEqual(controlled.count('RUN --network=none '), 4)
        with self.assertRaises(Refused):
            controlled_dockerfile(original.replace('RUN npm run build\n', 'RUN different-build\n'))
        self.assertEqual(self.contract['live']['hosted_app_server_api_key'], 'blocked')
        self.assertEqual(self.contract['live']['hosted_app_server_managed'], 'blocked')

if __name__ == '__main__':
    unittest.main()

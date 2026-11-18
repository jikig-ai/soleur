"""Offline candidate/rehearsal contract preparation. No operational entrypoint."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import hmac
import json
from pathlib import Path
import posixpath
import re
import subprocess

INPUT_ROOTS = ('apps/web-platform', 'plugins/soleur')
ATTEMPT = 'codex9051-oct19-local-auth-preparation-v1'
ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent/codex9051-preparation',
       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
       'GIT_TERMINAL_PROMPT': '0', 'LANG': 'C.UTF-8'}

class Refused(RuntimeError):
    pass

def require(condition, message):
    if not condition:
        raise Refused(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def encoded(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()

def synthetic_browser_config():
    # Public, deterministic fixture material. It is never a hosted account key.
    ref = sha((ATTEMPT + ':hostname').encode())[:20]
    secret = sha((ATTEMPT + ':synthetic-signing-material').encode()).encode()
    issued = int(datetime(2026, 10, 19, tzinfo=timezone.utc).timestamp())
    expiry = int(datetime(2026, 10, 26, tzinfo=timezone.utc).timestamp())
    claims = {'iss': 'supabase', 'role': 'anon', 'ref': ref, 'iat': issued, 'exp': expiry}
    signing_input = encoded(canonical({'alg': 'HS256', 'typ': 'JWT'})) + b'.' + encoded(canonical(claims))
    token = (signing_input + b'.' + encoded(hmac.new(secret, signing_input, hashlib.sha256).digest())).decode()
    return {'url': 'https://' + ref + '.supabase.co', 'anon_key': token,
            'signing_material': secret.decode(), 'claims': claims}

def browser_contract():
    config = synthetic_browser_config()
    return {'url': config['url'], 'anon_key_sha256': sha(config['anon_key'].encode()),
            'claims': config['claims'], 'hosted_account': False,
            'resolution': 'private-namespace-only-to-owned-TLS-proxy; external-route-absent',
            'tls': 'task-CA-and-exact-SAN; trust-only-in-owned-renderer-and-browser',
            'proxy_upstream': 'owned-kong-on-internal-network',
            'supabase_cli_version': '2.84.2',
            'local_auth_config_fields': ['auth.jwt_secret', 'auth.anon_key', 'auth.service_role_key'],
            'external_oauth': False, 'email_delivery': 'owned-local-mailpit-only',
            'signups': False, 'provider_credentials': False}

def controlled_dockerfile(original):
    controls = (
        ('RUN npm run build\n', 'RUN --network=none NEXT_TELEMETRY_DISABLED=1 NODE_OPTIONS=--max-old-space-size=4096 npm run build\n'),
        ('RUN bash scripts/assert-dev-signin-eliminated.sh\n', 'RUN --network=none bash scripts/assert-dev-signin-eliminated.sh\n'),
        ('RUN npm run build:server\n', 'RUN --network=none npm run build:server\n'),
        ('RUN ./node_modules/.bin/esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs\n',
         'RUN --network=none ./node_modules/.bin/esbuild next.config.ts --bundle --format=esm --platform=node --external:@sentry/nextjs --outfile=next.config.mjs\n'),
    )
    result = original
    for anchor, replacement in controls:
        require(result.count(anchor) == 1, 'Production compiler anchor changed; fresh review required')
        result = result.replace(anchor, replacement)
    return result

def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], env=ENV, timeout=30)

def source_manifest(repo, source):
    require(re.fullmatch(r'[0-9a-f]{40}', source), 'Full source SHA required')
    require(git(repo, 'rev-parse', 'HEAD').decode().strip() == source, 'Source is no longer HEAD')
    # Preparation may add its own scripts/docs; runtime input bytes must be clean.
    require(not git(repo, 'status', '--porcelain', '--untracked-files=no', '--', *INPUT_ROOTS).strip(),
            'Runtime source contains uncommitted changes')
    raw = git(repo, 'ls-tree', '-r', '-z', source, '--', *INPUT_ROOTS)
    entries = {}
    for item in raw.split(b'\0'):
        if item:
            header, path = item.split(b'\t', 1)
            mode, kind, blob = header.decode().split()
            require(kind == 'blob' and mode in ('100644', '100755', '120000'), 'Unsupported source entry')
            entries[path.decode()] = {'mode': mode, 'blob': blob}
    require(entries, 'Source input set is empty')
    manifest = []
    for path, entry in sorted(entries.items()):
        name = Path(path).name
        require(not (name.startswith('.env') and name != '.env.example') and
                not name.endswith(('.pem', '.key')), 'Credential-shaped source export refused')
        content = git(repo, 'cat-file', 'blob', entry['blob'])
        if name == '.npmrc':
            settings = [line.strip() for line in content.decode().splitlines()
                        if line.strip() and not line.lstrip().startswith(('#', ';'))]
            require(settings and all(re.fullmatch(r'min-release-age\s*=\s*[0-9]+', line) for line in settings),
                    'Unreviewed npm configuration refused')
        if entry['mode'] == '120000':
            module = next(root for root in INPUT_ROOTS if path.startswith(root + '/'))
            target = path
            for _ in range(12):
                require(target in entries, 'Symlink target is not admitted source')
                if entries[target]['mode'] != '120000':
                    break
                link = git(repo, 'cat-file', 'blob', entries[target]['blob']).decode()
                require(not link.startswith('/') and '\x00' not in link, 'Absolute source symlink refused')
                target = posixpath.normpath(posixpath.join(posixpath.dirname(target), link))
                require(target.startswith(module + '/'), 'Source symlink escapes its module')
            else:
                raise Refused('Source symlink cycle/depth refused')
        manifest.append({'path': path, **entry, 'sha256': sha(content), 'bytes': len(content)})
    return manifest

def preparation(repo, source):
    manifest = source_manifest(repo, source)
    migrations = [item for item in manifest if item['path'].startswith('apps/web-platform/supabase/migrations/')
                  and item['path'].endswith('.sql') and not item['path'].endswith('.down.sql')]
    require(migrations and all(item['mode'] in ('100644', '100755') for item in migrations),
            'Complete regular-file forward migration set required')
    original = git(repo, 'show', source + ':apps/web-platform/Dockerfile').decode()
    controlled = controlled_dockerfile(original)
    browser = browser_contract()
    component_tree = git(repo, 'ls-tree', '-r', '-z', source, '--',
                         'scripts/codex-qualification', 'scripts/lib/codex-qualification.test.sh')
    components = []
    for item in component_tree.split(b'\0'):
        if item:
            header, path = item.split(b'\t', 1)
            mode, kind, blob = header.decode().split()
            require(kind == 'blob' and mode in ('100644', '100755'),
                    'Preparation components must be committed regular files')
            components.append({'path': path.decode(), 'blob': blob,
                               'sha256': sha(git(repo, 'cat-file', 'blob', blob))})
    require(components, 'Committed preparation component bundle absent')
    identity = {'source_sha': source, 'runtime_input_sha256': sha(canonical(manifest)),
                'schema_sha256': sha(canonical(migrations)), 'browser_contract_sha256': sha(canonical(browser)),
                'production_dockerfile_sha256': sha(original.encode()),
                'controlled_dockerfile_sha256': sha(controlled.encode()),
                'preparation_components_sha256': sha(canonical(components)),
                'supabase_cli_sha256': '3132b218461bf90d4cd5983b27b44031cd9b6c797c259a431b2e2520b5f7bdce'}
    return {'status': 'offline-prepared-runtime-and-independent-review-pending', 'attempt': ATTEMPT,
            'identity': identity, 'pairing_sha256': sha(canonical(identity)),
            'manifest': manifest, 'forward_migrations': migrations, 'browser': browser,
            'component_manifest': components,
            'candidate': {'image_id': None, 'build_authorized': False, 'startup_authorized': False,
                          'source': 'full-production-Dockerfile-with-compiler-network-controls-only',
                          'browser_validation': 'original-production-URL-and-JWT-guards-preserved'},
            'rehearsal': {'execute_available': False, 'all_forward_bodies': True,
                          'migration_runner': 'canonical-current-source-run-migrations.sh --bootstrap=skip',
                          'pre_marked_migrations': [], 'recovery_mode': 'forward-only-retained-schema-replacement',
                          'required_image_identity': identity, 'memory_bytes': 8 * 1024**3,
                          'work_seconds': 1800, 'cleanup_seconds': 300,
                          'scenarios': ['complete-public-auth-storage-row-fingerprints', 'storage-and-workspace-file-retention',
                                        'owner-member-other-tenant-scope', 'generation-checkpoint-race',
                                        'history-transfer-ack', 'scoped-engine-erasure'],
                          'remaining_controls': ['TLS-proxy-and-namespace-runtime-orchestration', 'image-filesystem-auth-receipt',
                                                 'reviewed-operational-role-image-config-profiles',
                                                 'review-all-source-schema-scenarios-and-cleanup', 'fresh-per-command-approval']},
            'live': {'hosted_app_server_api_key': 'blocked', 'hosted_app_server_managed': 'blocked',
                     'alternative_api_funded_route': 'pending', 'customer_content': 'blocked',
                     'flag_default': False, 'routine_consumer': 'none-qualified'},
            'operations': {'docker': 0, 'sql': 0, 'provider': 0, 'credentials_read': 0, 'markers_consumed': 0}}

def validate_image_receipt(contract, receipt):
    require(isinstance(receipt, dict), 'Image receipt absent')
    require(receipt.get('identity') == contract['identity'], 'Source/schema/auth/config image identity differs')
    require(re.fullmatch(r'sha256:[0-9a-f]{64}', receipt.get('image_id', '')), 'Immutable image ID absent')
    require(receipt.get('user') == 'soleur' and receipt.get('cmd') == ['node', 'dist/server/index.cjs'] and
            receipt.get('entrypoint') == ['docker-entrypoint.sh'],
            'Production image user or entrypoint differs')
    require(receipt.get('browser_anon_key_sha256') == contract['browser']['anon_key_sha256'] and
            receipt.get('browser_auth_probe') == 'passed-owned-local-synthetic-auth',
            'Matching local browser authentication receipt absent')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source-sha', required=True)
    parser.add_argument('--preview', action='store_true', required=True)
    args = parser.parse_args()
    require(not git(args.repo, 'status', '--porcelain', '--untracked-files=no', '--',
                    'scripts/codex-qualification', 'scripts/lib/codex-qualification.test.sh').strip(),
            'Preparation components changed; commit and prepare fresh fingerprints')
    result = preparation(args.repo, args.source_sha)
    print(json.dumps({key: value for key, value in result.items() if key not in ('manifest', 'forward_migrations', 'component_manifest')}
                     | {'tracked_input_count': len(result['manifest']),
                        'forward_migration_count': len(result['forward_migrations'])}, indent=2))

if __name__ == '__main__':
    main()

"""Pure pending operational requirements over the existing candidate policy.

No CLI, builder, Docker adapter, sockets, credential access or receipt issuer
authentication exists here. Supplied JSON can establish structural consistency
only. In particular, no returned object is an executable RoleProfiles map.
"""
from pathlib import Path
import re

from candidate import candidate_spec
from prepare import canonical, git, require, sha


ROLES = ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage', 'renderer',
         'browser', 'tls', 'resolver', 'migration')
KINDS = ('build', 'image', 'filesystem', 'namespace', 'auth')
BUDGET = {'memory_bytes': 8 * 1024**3, 'work_seconds': 1800, 'cleanup_seconds': 300}
BASE_FIELDS = {'kind', 'identity', 'pairing_sha256', 'operational_sha256', 'image_id',
               'observed_at', 'expires_at', 'issuer', 'provenance', 'facts'}
RACE_SCENARIOS = ('40_race_holder.sql', '41_race_waiter.sql', '42_race_observe.sql', '43_race_assert.sql')


def prepare_operational(repo, source, directory):
    """Read exact committed inputs; return content-free, non-executable requirements.

    The candidate directory must be a fresh admitted destination, but is never
    created. Raw argv/build values remain in candidate_spec, not this metadata.
    Runtime recipes and image Config snapshots remain absent until independently
    reviewed observations exist; knowing a role's name supplies neither.
    """
    spec = candidate_spec(repo, source, directory)
    # candidate.py › candidate_spec() binds candidate/prepare bytes. This module
    # must also match the executing committed component before emitting identity.
    root = 'scripts/codex-qualification/'
    paths = [root + name for name in ('candidate.py', 'prepare.py', 'role_profiles.py',
             'api_policy.py', 'namespace.py', 'local_tls.py', 'rehearsal.py', 'operational.py',
             'retained_files.py', 'session_controller.py')]
    paths += [root + 'scenarios/' + name for name in RACE_SCENARIOS]
    references = {}
    for entry in git(repo, 'ls-tree', '-z', source, '--', *paths).split(b'\0'):
        if entry:
            header, name = entry.split(b'\t', 1)
            mode, kind, blob = header.decode().split()
            require(kind == 'blob' and mode in ('100644', '100755'), 'Operational inputs must be committed regular files')
            references[name.decode()] = {'blob': blob, 'sha256': sha(git(repo, 'cat-file', 'blob', blob))}
    require(set(references) == set(paths), 'Complete operational component and scenario census required')
    component = root + 'operational.py'
    require(component in references and references[component]['sha256'] == sha(Path(__file__).read_bytes()),
            'Executing operational component is not committed current source')
    require(all(root + 'scenarios/' + name in references for name in RACE_SCENARIOS),
            'Complete committed holder/waiter/observe/assert race inputs required')
    recipe = spec['build_recipe']
    require(recipe['execute_authorized'] is False and recipe['replace_environment'] is True and
            recipe['credential_forwarding'] is False, 'Candidate builder restrictions changed')
    obligations = {
        'db': ['registered-owned-database-and-storage-volumes', 'complete-forward-schema-no-premarking'],
        'kong': ['registered-owned-network-and-container-ID', 'observed-upstream-private-IP'],
        'auth': ['matching-local-synthetic-auth-config', 'external-oauth-and-delivery-absent'],
        'inbucket': ['owned-local-mail-only', 'external-delivery-absent'],
        'rest': ['owned-database-only', 'exact-reviewed-service-config'],
        'storage': ['owned-storage-byte-manifests-before-and-after', 'owned-database-only'],
        'migration': ['canonical-source-bound-forward-runner', 'read-only-mounted-SQL-no-interactive-input'],
        'renderer': ['production-image-config-and-filesystem', 'exact-DNS-and-task-CA-node-trust'],
        'browser': ['immutable-browser-image-config', 'exact-DNS-task-CA-owned-HOME-and-profile-trust'],
        'tls': ['exact-SAN-SNI-Host-and-task-CA', 'observed-owned-Kong-IP', 'exact-low-port-namespace-sysctl'],
        'resolver': ['exact-hostname-to-observed-TLS-IP', 'no-forwarders-NXDOMAIN-unknown',
                     'exact-low-port-namespace-sysctl'],
    }
    observations = {
        'build': ['builder-binary-digest-daemon-identity-and-exact-admission',
                  'full-production-context-controlled-Dockerfile-argv-environment',
                  'reviewed-npm-apt-GitHub-CLI-Playwright-dependency-routes-and-budget'],
        'image': ['immutable-built-image-ID', 'complete-inherited-Config-and-exact-reobservation'],
        'filesystem': ['complete-built-image-path-mode-link-and-byte-census',
                       'separate-retained-storage-and-workspace-file-byte-manifests'],
        'namespace': ['registered-network-volumes-service-Kong-TLS-resolver-and-client-IDs-IPs',
                      'exact-DNS-task-CA-process-profile-trust-and-route-observations'],
        'auth': ['matching-current-source-image-namespace-and-synthetic-config',
                 'owned-local-renderer-and-browser-authentication-and-screenshot-artifacts'],
    }
    roles = {role: {'image_id': None, 'image_config': None, 'recipe': None, 'profile': None,
                    'admissible': False, 'status': 'observations-and-independent-review-pending',
                    'obligations': obligations[role],
                    'required_before_profile': ['complete-observed-immutable-image-Config',
                                                'exact-image-Config-reobservation-match',
                                                'source-bound-command-user-environment-mount-network-recipe',
                                                'independent-source-and-profile-review']}
             for role in ROLES}
    # api_policy.py › Policy.__init__() reserves these names, not observed IDs.
    for role, slot in roles.items():
        if role in ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage'):
            names = ['supabase_' + role + '_{project}']
        elif role == 'renderer':
            names = ['codex9051-renderer-{project}-' + phase for phase in ('first', 'replacement')]
        elif role == 'migration':
            names = ['codex9051-job-{project}-' + str(number) for number in range(1, 9)]
        else:
            names = ['codex9051-' + role + '-{project}']
        slot['container_name_templates'] = names
        slot['profile_field_obligations'] = ['role', 'image', 'complete-observed-image_config',
              'create.Cmd', 'create.Entrypoint', 'create.Env', 'create.User', 'create.WorkingDir',
              'create.Healthcheck', 'create.ExposedPorts', 'host.Binds', 'host.PortBindings',
              'host.Dns', 'host.DnsSearch', 'host.DnsOptions', 'host.Sysctls', 'aliases',
              'exec.Cmd', 'exec.Env', 'exec.User', 'exec.WorkingDir']
    contract = {
        'status': 'offline-operational-requirements-only', 'execute_authorized': False,
        'identity': spec['identity'], 'pairing_sha256': spec['pairing_sha256'],
        'source_references': references, 'budget': dict(BUDGET),
        'session_prerequisites': {
            'scenario_sha256': {name: references[root + 'scenarios/' + name]['sha256'] for name in RACE_SCENARIOS},
            'binding_fields': ['source-identity-and-pairing', 'attempt', 'database-identity',
                               'holder-and-waiter-backend-PIDs-and-birth-times'],
            'dependency': 'observed-holder-lock-waiter-block-and-same-session-assertions-no-elapsed-time-proof',
            'session_authority': 'pending', 'execute_authorized': False},
        'retained_prerequisites': {
            'binding_fields': ['source-identity-and-pairing', 'attempt', 'owner-identity', 'database-identity',
                               'root-identity', 'storage-and-workspace-file-census-before-and-after'],
            'file_fields': ['relative-path', 'file-kind', 'mode', 'bytes', 'sha256', 'root-and-file-device-inode'],
            'traversal': 'descriptor-relative-nofollow-regular-files-only',
            'owner_and_quiescence_proof': 'pending', 'execute_authorized': False},
        'builder': {'export_manifest_sha256': spec['export_manifest_sha256'],
                    'build_recipe_sha256': spec['build_recipe_sha256'],
                    'argv_sha256': sha(canonical(recipe['argv'])),
                    'environment_sha256': sha(canonical(recipe['environment'])),
                    'working_directory': recipe['working_directory'],
                    'controlled_dockerfile_sha256': spec['identity']['controlled_dockerfile_sha256'],
                    'replace_environment': True, 'credential_forwarding': False,
                    'binary_sha256': None, 'daemon_identity': None,
                    'dependency_routes': {route: 'pending' for route in ('npm', 'apt', 'github-cli', 'playwright')},
                    'admission': 'exact-builder-daemon-namespace-network-and-resource-review-pending',
                    'fresh_exact_command_approval': 'required-not-consumed'},
        'roles': roles,
        'namespace_order': [
            {'phase': 'registered-network-and-services', 'requires': ['registered-internal-network-ID',
              'registered-owned-volumes', 'observed-db-auth-inbucket-rest-storage-IDs-and-configs']},
            {'phase': 'observed-kong', 'requires': ['registered-owned-Kong-ID',
              'matching-network-Kong-receipts-and-private-IP']},
            {'phase': 'observed-tls-and-resolver', 'requires': ['registered-TLS-and-resolver-IDs-and-IPs',
              'exact-hostname-to-TLS-IP-and-Kong-upstream', 'exact-task-CA-and-namespace-sysctls']},
            {'phase': 'renderer-and-browser', 'requires': ['registered-client-IDs-and-configs',
              'exact-DNS-task-CA-and-profile-scoped-trust', 'observed-external-route-absence',
              'owned-local-synthetic-auth-in-both-clients']},
        ],
        'browser': {'hostname': spec['browser']['url'].removeprefix('https://'),
                    'anon_key_sha256': spec['browser']['anon_key_sha256'],
                    'expires_at': spec['browser']['claims']['exp']},
        'evidence_requirements': {kind: {'status': 'pending',
              'required_observations': observations[kind],
              'binding': ['full-source-identity', 'pairing', 'operational-contract', 'immutable-image-ID'],
              'provenance': ['issuer-name-and-key-ID', 'observer-ID', 'tool-and-artifact-digests',
                             'observation-and-expiry-times', 'independent-issuer-verification'],
              'authority': 'structural-checks-never-authorize-execution-or-authenticate-issuer'} for kind in KINDS},
        'holds': {'build_authorized': False, 'startup_authorized': False, 'draft': True,
                  'auto_merge': False, 'flag_default': False, 'customer_content': 'blocked',
                  'provider': 'blocked', 'credentials': 'blocked', 'browser_auth_execution': 'blocked',
                  'account_and_shared_writes': 'blocked', 'deployment': 'blocked',
                  'hosted_api_key_auth': 'blocked', 'hosted_managed_auth': 'blocked',
                  'alternative_api_route': 'pending', 'routine_consumer': 'none-qualified'},
        'operations': {'docker': 0, 'build': 0, 'sql': 0, 'network': 0, 'credentials_read': 0,
                       'provider': 0, 'auth': 0, 'approvals_consumed': 0},
    }
    contract['operational_sha256'] = sha(canonical(contract))
    return contract


def digest(value):
    require(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value), 'SHA-256 digest required')


def text_identity(value):
    require(isinstance(value, str) and 0 < len(value) <= 256 and
            all(32 <= ord(char) < 127 for char in value), 'Bounded nonempty observation identity required')


def validate_evidence(contract, kind, receipt, *, now, expected_image=None, expected_namespace=None):
    """Refuse inconsistent supplied evidence; never grant operational authority.

    expected_image and expected_namespace are independent caller-supplied
    observation references, not authenticated inputs. Exact matching of JSON is
    deliberately insufficient for image/profile admission, login proof or an
    approval. Those gates stay pending even for structurally valid receipts.
    """
    require(isinstance(contract, dict) and 'operational_sha256' in contract, 'Operational contract absent')
    content = {key: value for key, value in contract.items() if key != 'operational_sha256'}
    require(contract['operational_sha256'] == sha(canonical(content)) and
            contract.get('execute_authorized') is False, 'Operational contract mutated or grants authority')
    require(isinstance(contract.get('identity'), dict) and
            contract.get('pairing_sha256') == sha(canonical(contract['identity'])) and
            contract.get('budget') == BUDGET, 'Operational pairing or resource limits differ')
    roles = contract.get('roles')
    require(isinstance(roles, dict) and set(roles) == set(ROLES), 'Complete pending role slots required')
    require(all(isinstance(role, dict) and role.get('admissible') is False and
                all(field in role and role[field] is None for field in ('image_id', 'image_config', 'recipe', 'profile'))
                for role in roles.values()), 'Operational requirements cannot supply admitted role profiles')
    require(kind in KINDS, 'Unknown evidence kind')
    require(isinstance(receipt, dict) and set(receipt) == BASE_FIELDS, 'Complete exact evidence fields required')
    require(receipt['kind'] == kind and receipt['identity'] == contract['identity'] and
            receipt['pairing_sha256'] == contract['pairing_sha256'] and
            receipt['operational_sha256'] == contract['operational_sha256'], 'Evidence source/pairing differs')
    require(isinstance(expected_image, dict) and set(expected_image) == {'Id', 'Config'},
            'Independent immutable image/config reference required')
    image_id = expected_image['Id']
    require(isinstance(image_id, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', image_id) and
            receipt['image_id'] == image_id, 'Immutable evidence image differs')
    config = expected_image['Config']
    require(isinstance(config, dict) and all(field in config for field in
            ('Entrypoint', 'Cmd', 'Env', 'User', 'WorkingDir', 'Healthcheck', 'ExposedPorts', 'Volumes', 'OnBuild')),
            'Complete inherited image Config reference required')
    require(config.get('User') == 'soleur' and config.get('Cmd') == ['node', 'dist/server/index.cjs'] and
            config.get('Entrypoint') == ['docker-entrypoint.sh'] and not config.get('OnBuild'),
            'Production image user, command, entrypoint or inherited build triggers differ')
    observed, expiry = receipt['observed_at'], receipt['expires_at']
    require(type(now) is int and type(observed) is int and type(expiry) is int and
            now - BUDGET['work_seconds'] <= observed <= now < expiry <= contract['browser']['expires_at'] and
            expiry - observed <= BUDGET['work_seconds'], 'Stale, future, expired or unbounded evidence times')
    issuer, provenance = receipt['issuer'], receipt['provenance']
    require(isinstance(issuer, dict) and set(issuer) == {'name', 'key_id'}, 'Issuer identity fields required')
    for value in issuer.values():
        text_identity(value)
    require(isinstance(provenance, dict) and set(provenance) == {'observer_id', 'tool_sha256', 'artifact_sha256'},
            'Observation provenance fields required')
    text_identity(provenance['observer_id'])
    digest(provenance['tool_sha256'])
    digest(provenance['artifact_sha256'])
    facts = receipt['facts']
    require(isinstance(facts, dict), 'Evidence facts absent')
    if kind == 'build':
        require(set(facts) == {'builder_binary_sha256', 'daemon_id', 'export_manifest_sha256',
                              'build_recipe_sha256', 'controlled_dockerfile_sha256'}, 'Complete build evidence required')
        digest(facts['builder_binary_sha256'])
        text_identity(facts['daemon_id'])
        for field in ('export_manifest_sha256', 'build_recipe_sha256', 'controlled_dockerfile_sha256'):
            require(facts[field] == contract['builder'][field], 'Build recipe or source context differs')
    elif kind == 'image':
        require(set(facts) == {'Config', 'config_sha256'} and facts['Config'] == config and
                facts['config_sha256'] == sha(canonical(config)), 'Observed immutable image Config differs')
    elif kind == 'filesystem':
        require(set(facts) == {'manifest_sha256', 'inventory_sha256', 'scope'} and
                facts['scope'] == 'complete-production-image-filesystem', 'Complete image filesystem evidence required')
        digest(facts['manifest_sha256'])
        digest(facts['inventory_sha256'])
    else:
        require(isinstance(expected_namespace, dict) and
                set(expected_namespace) == {'manifest_sha256', 'task_ca_sha256'},
                'Independent namespace/CA observation reference required')
        for value in expected_namespace.values():
            digest(value)
        require(facts.get('hostname') == contract['browser']['hostname'] and
                facts.get('task_ca_sha256') == expected_namespace['task_ca_sha256'],
                'Evidence hostname or task CA differs')
        if kind == 'namespace':
            require(set(facts) == {'manifest_sha256', 'task_ca_sha256', 'hostname'} and
                    facts['manifest_sha256'] == expected_namespace['manifest_sha256'], 'Namespace evidence differs')
        else:
            require(set(facts) == {'namespace_manifest_sha256', 'task_ca_sha256', 'hostname',
                    'browser_contract_sha256', 'anon_key_sha256', 'mode', 'provider_credentials',
                    'renderer_authenticated', 'browser_authenticated'}, 'Complete local auth evidence required')
            require(facts['namespace_manifest_sha256'] == expected_namespace['manifest_sha256'] and
                    facts['browser_contract_sha256'] == contract['identity']['browser_contract_sha256'] and
                    facts['anon_key_sha256'] == contract['browser']['anon_key_sha256'] and
                    facts['mode'] == 'owned-local-synthetic' and facts['provider_credentials'] is False and
                    facts['renderer_authenticated'] is True and facts['browser_authenticated'] is True,
                    'Matching owned local renderer/browser auth evidence required')
    return {'status': 'structurally_valid', 'kind': kind, 'receipt_sha256': sha(canonical(receipt)),
            'issuer_verification': 'pending', 'independent_review': 'pending',
            'execute_authorized': False, 'authentication_established': False, 'profile_admissible': False}

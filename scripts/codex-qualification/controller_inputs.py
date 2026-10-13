"""Pure specifications for future reviewed operational adapters.

Every reference is supplied, unauthenticated input. No returned specification
is an executable RoleProfiles map, transport, runtime receipt or approval.
"""
import re
from pathlib import Path

from operational import BUDGET, ROLES, checked_contract, digest, text_identity
from prepare import canonical, require, sha
from role_profiles import FIELDS, HOST_FIELDS, RoleProfiles
import retained_files

ROUTES = ('npm', 'apt', 'github-cli', 'playwright')
CONFIG_FIELDS = FIELDS | {'Volumes', 'OnBuild'}


def checked_inputs(contract):
    checked_contract(contract)
    component = contract.get('source_references', {}).get('scripts/codex-qualification/controller_inputs.py', {})
    require(component.get('sha256') == sha(Path(__file__).read_bytes()),
            'Executing controller-input component differs from source reference')


def pending(contract, value):
    return {'status': 'structurally-consistent-specification-only',
            'pairing_sha256': contract['pairing_sha256'],
            'operational_sha256': contract['operational_sha256'],
            'specification_sha256': sha(canonical(value)),
            'issuer_verification': 'pending', 'independent_review': 'pending',
            'execute_authorized': False, 'profile_admissible': False,
            'authentication_established': False}


def role_names(attempt, role):
    require(isinstance(attempt, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,128}', attempt),
            'Bounded attempt identity required')
    require(isinstance(role, str) and role in ROLES, 'Unknown specification role')
    if role in ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage'):
        return ('supabase_' + role + '_' + attempt,)
    if role == 'renderer':
        return tuple('codex9051-renderer-' + attempt + '-' + phase for phase in ('first', 'replacement'))
    if role == 'migration':
        return tuple('codex9051-job-' + attempt + '-' + str(number) for number in range(1, 9))
    return ('codex9051-' + role + '-' + attempt,)


def profile_spec(contract, attempt, name, proposed, *, reviewed_profile, observed_image, reobserved_image):
    """Compare a proposed recipe to separate review and Config references.

    Equality establishes no provenance. Real immutable observations and review
    remain required; profile recipes are deliberately absent from the result.
    """
    checked_inputs(contract)
    require(isinstance(proposed, dict) and proposed == reviewed_profile,
            'Exact separate reviewed profile specification required')
    role = proposed.get('role')
    require(name in role_names(attempt, role), 'Role name is outside exact attempt reservation')
    for observation in (observed_image, reobserved_image):
        require(isinstance(observation, dict) and set(observation) == {'Id', 'Config'} and
                observation['Id'] == proposed.get('image') and
                observation['Config'] == proposed.get('image_config'),
                'Immutable Config observation or reobservation differs')
    config, create, host = proposed.get('image_config'), proposed.get('create'), proposed.get('host')
    require(isinstance(config, dict) and CONFIG_FIELDS <= set(config), 'Complete inherited Config required')
    require(isinstance(create, dict) and set(create) == FIELDS and
            isinstance(host, dict) and set(host) == HOST_FIELDS, 'Complete effective create and host fields required')
    require(isinstance(create['Env'], list), 'Explicit effective environment required')
    profiles = RoleProfiles({name: proposed}, require)
    profiles.verify_image(name, reobserved_image)
    for value in (config, create, *proposed['exec']):
        require(isinstance(value, dict), 'Command specification required')
        for field in ('Cmd', 'Entrypoint'):
            if field in value:
                command = value[field]
                require(command is None or (isinstance(command, list) and len(command) <= 32 and
                        all(isinstance(word, str) and '\x00' not in word and len(word) <= 8192 for word in command)),
                        'Bounded command specification required')
        for field in ('User', 'WorkingDir'):
            require(isinstance(value.get(field), str) and len(value[field]) <= 2048 and
                    '\x00' not in value[field], 'Explicit user and working directory required')
    user = create['User'].split(':', 1)[0]
    require(user not in ('', 'root', '0') and not (user.isdecimal() and int(user) == 0),
            'Nonroot effective role user required')
    # Docker merges inherited Env by key. An omitted inherited key therefore
    # survives even when absent from create.Env; require every key explicitly.
    inherited_keys = {setting.split('=', 1)[0] for setting in (config['Env'] or [])}
    effective_keys = {setting.split('=', 1)[0] for setting in create['Env']}
    require(inherited_keys <= effective_keys, 'Inherited environment omitted from effective recipe')
    profiles.create(name, {'Image': proposed['image']})
    result = pending(contract, {'attempt': attempt, 'name': name, 'profile': proposed})
    result.update(role=role, image_id=proposed['image'], profile_sha256=sha(canonical(proposed)))
    return result


def builder_spec(contract, observation, *, reviewed):
    """Bind supplied builder references; no process, network or daemon access."""
    checked_inputs(contract)
    recipe_fields = ('export_manifest_sha256', 'build_recipe_sha256', 'controlled_dockerfile_sha256',
                     'argv_sha256', 'environment_sha256')
    require(isinstance(observation, dict) and observation == reviewed and
            set(observation) == set(recipe_fields) | {'binary_sha256', 'daemon_id', 'budget', 'dependency_routes'},
            'Exact separate reviewed builder observation required')
    for field in recipe_fields:
        digest(observation[field])
        require(observation[field] == contract['builder'][field], 'Builder source or replaced environment differs')
    digest(observation['binary_sha256'])
    text_identity(observation['daemon_id'])
    require(observation['budget'] == BUDGET and all(type(value) is int for value in observation['budget'].values()),
            'Exact bounded builder budget required')
    routes = observation['dependency_routes']
    require(isinstance(routes, dict) and set(routes) == set(ROUTES), 'Complete exact dependency-route census required')
    for route in routes.values():
        digest(route)
    return pending(contract, observation)


def adapter_requirements(contract):
    """Interface obligations only; no callbacks, adapters or transports created."""
    checked_inputs(contract)
    requirements = {
        'builder': ['exact-source-export-and-controlled-Dockerfile', 'replaced-environment-and-argv',
                    'binary-daemon-route-and-resource-reobservation', 'fresh-exact-command-approval'],
        'namespace': ['registered-internal-network-and-volume-reobservation', 'service-Kong-TLS-resolver-client-ID-IP-census',
                      'private-subnet-and-exact-host-DNS', 'task-CA-and-profile-scoped-trust',
                      'route-absence-per-role', 'local-synthetic-auth-remains-separate'],
        'session': ['ScenarioBinding-complete-source-hash-census', 'SessionIdentity-process-and-backend-births',
                    'persistent-existing-owned-sessions', 'RaceController-observed-lock-before-commit',
                    'explicit-commit-waiter-exit-and-source-assertion', 'bounded-rollback-and-close-no-stdin-reopen'],
        'retained': ['registered-resource-and-root-descriptor-identity', 'complete-writer-census',
                     'quiescence-window-covers-complete-collection', 'storage-and-workspace-before-after-manifests',
                     'exact-retention-or-scoped-erasure', 'issuer-authentication-remains-pending'],
    }
    result = pending(contract, requirements)
    result['adapters'] = {name: {'implementation': 'pending', 'transport_available': False,
                                'required_observations': fields} for name, fields in requirements.items()}
    return result


def writer_census(writers):
    require(isinstance(writers, list) and len(writers) <= 128, 'Bounded complete writer census required')
    identities = []
    for writer in writers:
        require(isinstance(writer, dict) and set(writer) == {'container_id', 'process_pid', 'process_birth'},
                'Exact registered writer identity required')
        digest(writer['container_id'])
        require(type(writer['process_pid']) is int and writer['process_pid'] > 0, 'Writer PID required')
        text_identity(writer['process_birth'])
        identities.append((writer['container_id'], writer['process_pid'], writer['process_birth']))
    require(len(set(identities)) == len(identities), 'Duplicate writer identity refused')
    return sorted(identities)


def retention_spec(contract, before, after, prior, current, *, expected_owner, expected_database,
                   expected_resource, expected_writers, now, erased_paths=()):
    """Join supplied observation windows to complete retained-file manifests.

    The caller supplies the writer census and all observation references; this
    function cannot discover omitted writers, authenticate ownership or stop a
    writer. Empty censuses need the same future independent review as all others.
    Times share one supplied integer observation clock, never elapsed-time proof.
    """
    checked_inputs(contract)
    text_identity(expected_owner)
    text_identity(expected_database)
    require(type(now) is int and now >= 0, 'Integer observation clock required')
    stable = retained_files.BINDING_FIELDS - {'quiescence_id'}
    require(isinstance(expected_resource, dict) and set(expected_resource) == stable,
            'Separate registered resource and root reference required')
    writers = writer_census(expected_writers)
    times = ('quiescence_start', 'collection_start', 'collection_end', 'quiescence_end',
             'observed_at', 'expires_at')
    fields = {'binding', 'phase', 'owner_id', 'database_id', 'writers', 'quiescent_writers',
              'observer_id', 'artifact_sha256'} | set(times)
    for phase, manifest, observation in (('before', before, prior), ('after', after, current)):
        retained_files.checked_manifest(manifest)
        require(isinstance(observation, dict) and set(observation) == fields, 'Complete retained observation required')
        binding = manifest['binding']
        require(observation['binding'] == binding and observation['phase'] == phase and
                {field: binding[field] for field in stable} == expected_resource and
                binding['source_sha'] == contract['identity']['source_sha'] and
                binding['pairing_sha256'] == contract['pairing_sha256'],
                'Retained observation source, phase or root binding differs')
        require(observation['owner_id'] == expected_owner and observation['database_id'] == expected_database,
                'Retained owner or database reference differs')
        require(writer_census(observation['writers']) == writers and
                writer_census(observation['quiescent_writers']) == writers,
                'Exact complete writer and quiescence census differs')
        require(all(type(observation[field]) is int and observation[field] >= 0 for field in times),
                'Integer observation window required')
        start, collect, end, quiet, observed, expiry = (observation[field] for field in times)
        require(now - BUDGET['work_seconds'] <= start <= collect <= end <= quiet <= observed <= now < expiry and
                expiry <= contract['browser']['expires_at'] and expiry - start <= BUDGET['work_seconds'],
                'Collection is outside fresh bounded quiescence window')
        text_identity(observation['observer_id'])
        digest(observation['artifact_sha256'])
    require(prior['quiescence_end'] <= current['quiescence_start'] and
            before['binding']['quiescence_id'] != after['binding']['quiescence_id'],
            'Distinct ordered before/after quiescence observations required')
    matched = retained_files.compare(before, after, erased_paths)
    result = pending(contract, {'before': before, 'after': after, 'prior': prior, 'current': current,
                                'erased_paths': matched['erased_paths']})
    result.update(ownership_verified=False, quiescence_verified=False)
    return result

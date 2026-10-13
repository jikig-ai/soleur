"""Callable controllers over injected transports; no production wiring or CLI.

Inputs and returned observations establish consistency only. Transport hard
timeouts/cancellation, provenance, independent review and fresh exact operational
approval remain external prerequisites. This module grants none of them.
"""
import copy
from functools import wraps
import math
import os
from pathlib import Path
import re
import stat
from urllib.parse import quote

import candidate
import controller_inputs as inputs
from api_policy import Policy, Refused as PolicyRefused
from namespace import namespace_recipe, Refused as NamespaceRefused
from operational import BUDGET, digest, text_identity
from prepare import Refused, canonical, require, sha
import retained_files
from session_controller import (CLEANUP_SECONDS, MAX_OBSERVATIONS, RaceController,
                                SCENARIOS, ScenarioBinding, SessionIdentity, _token)

MAX_RESPONSE = 16 * 1024**2


def finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value) and value >= 0
    except OverflowError:
        return False


def bounded(value):
    require(isinstance(value, dict) and len(canonical(value)) <= MAX_RESPONSE,
            'Bounded structured transport response required')
    return value


def read_clock(clock, kind):
    try:
        return clock()
    except Exception:
        raise Refused('Injected ' + kind + ' clock failed') from None


def step(method):
    @wraps(method)
    def invoke(self, *args, **kwargs):
        try:
            self._remaining()
            return method(self, *args, **kwargs)
        except Exception as error:
            self._fail(str(error) if isinstance(error, (Refused, PolicyRefused, NamespaceRefused))
                       else 'Adapter operation failed')
    return invoke


class _Adapter:
    def __init__(self, contract, transport, clock):
        self._contract = copy.deepcopy(contract)
        inputs.checked_inputs(self._contract)
        reference = self._contract.get('source_references', {}).get(
            'scripts/codex-qualification/controller_adapters.py', {})
        require(reference.get('sha256') == sha(Path(__file__).read_bytes()),
                'Executing adapter component differs from source reference')
        require(callable(clock), 'Injected monotonic clock required')
        initial = read_clock(clock, 'monotonic')
        require(finite(initial), 'Finite monotonic clock required')
        self._clock, self._last = clock, initial
        self._deadline = initial + BUDGET['work_seconds']
        self._cleanup_deadline = None
        self._transport = transport
        self._state, self._primary = 'ready', None
        self._calls = {}
        self._cleanup_errors = 0

    def _tick(self):
        instant = read_clock(self._clock, 'monotonic')
        require(finite(instant) and instant >= self._last, 'Finite monotonic clock required')
        self._last = instant
        return instant

    def _remaining(self, cleanup=False):
        if cleanup:
            if self._cleanup_deadline is None:
                self._cleanup_deadline = self._last + CLEANUP_SECONDS
            deadline = self._cleanup_deadline
        else:
            require(self._state not in ('failed', 'closed'), 'Adapter progress is terminal')
            deadline = self._deadline
        remaining = deadline - self._tick()
        require(remaining > 0, 'Adapter deadline expired')
        return remaining

    def _fail(self, message):
        if self._primary is None:
            self._primary = message
            self._cleanup_deadline = self._last + CLEANUP_SECONDS
        self._state = 'failed'
        raise Refused(self._primary)

    def _call(self, operation, *args, cleanup=False, check_after=True):
        timeout = self._remaining(cleanup)
        try:
            callback = getattr(self._transport, operation, None)
        except Exception:
            raise Refused('Injected transport operation lookup failed') from None
        require(callable(callback), 'Required injected transport operation absent')
        self._calls[operation] = self._calls.get(operation, 0) + 1
        # A transport cannot mutate the adapter's reviewed recipe/references.
        try:
            result = copy.deepcopy(callback(*copy.deepcopy(args), timeout=timeout))
        except Exception:
            # Exception type is also callback-controlled: even a Refused message
            # can carry raw content. Preserve only a fixed boundary failure.
            raise Refused('Injected transport operation failed') from None
        if check_after:
            self._remaining(cleanup)
        return result

    def snapshot(self):
        return {'state': self._state, 'primary_failure': self._primary,
                'pairing_sha256': self._contract['pairing_sha256'],
                'execute_authorized': False, 'profile_admissible': False,
                'authentication_established': False, 'ownership_verified': False,
                'quiescence_verified': False, 'issuer_verification': 'pending',
                'independent_review': 'pending',
                'runtime_evidence': 'pending-injected-observations-only',
                'injected_calls': dict(self._calls), 'cleanup_errors': self._cleanup_errors}


class BuilderAdapter(_Adapter):
    def __init__(self, contract, spec, observation, *, reviewed, transport, clock):
        super().__init__(contract, transport, clock)
        self._spec = copy.deepcopy(spec)
        inputs.builder_spec(self._contract, copy.deepcopy(observation), reviewed=copy.deepcopy(reviewed))
        value = self._spec
        require(isinstance(value, dict) and value.get('identity') == self._contract['identity'] and
                value.get('pairing_sha256') == self._contract['pairing_sha256'], 'Builder source differs')
        recipe = value.get('build_recipe')
        require(isinstance(recipe, dict) and recipe.get('execute_authorized') is False and
                recipe.get('replace_environment') is True and recipe.get('credential_forwarding') is False,
                'Exact replaced builder environment without credentials required')
        require(isinstance(recipe.get('argv'), list) and 0 < len(recipe['argv']) <= 128 and
                all(isinstance(word, str) and 0 < len(word) <= 8192 and '\x00' not in word
                    for word in recipe['argv']) and isinstance(recipe.get('environment'), dict) and
                all(isinstance(k, str) and isinstance(v, str) and '\x00' not in k + v
                    for k, v in recipe['environment'].items()), 'Bounded exact argv and environment required')
        expected = self._contract['builder']
        require(sha(canonical(value.get('export_manifest'))) == value.get('export_manifest_sha256') ==
                expected['export_manifest_sha256'] and sha(canonical(recipe)) ==
                value.get('build_recipe_sha256') == expected['build_recipe_sha256'] and
                sha(canonical(recipe['argv'])) == expected['argv_sha256'] and
                sha(canonical(recipe['environment'])) == expected['environment_sha256'] and
                value['identity'].get('controlled_dockerfile_sha256') == expected['controlled_dockerfile_sha256'],
                'Builder source, export, argv or environment binding differs')
        self._attempted = False

    def _export_root(self, export_fd):
        directory = Path(self._spec['build_recipe'].get('working_directory', ''))
        project_scratch = Path(__file__).resolve().parents[2] / '.soleur'
        require(directory.is_absolute() and '..' not in directory.parts and
                not any(part in ('.git', '.ssh', '.aws', '.codex', '.agents') for part in directory.parts),
                'Explicit task export root required')
        allowed = project_scratch if directory.is_relative_to(project_scratch) else Path('/tmp')
        require(directory.is_relative_to(allowed) and directory != allowed and
                directory == directory.resolve(strict=True) and
                self._spec.get('destination', str(directory)) == str(directory),
                'Builder directory is outside its reviewed task root')
        root_fd = os.open(allowed, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        opened = None
        try:
            opened = candidate.open_directory(root_fd, directory.relative_to(allowed).parts)
            actual, borrowed = os.fstat(opened), os.fstat(export_fd)
            require(stat.S_ISDIR(borrowed.st_mode) and (actual.st_dev, actual.st_ino) ==
                    (borrowed.st_dev, borrowed.st_ino), 'Export descriptor and recipe directory differ')
        finally:
            if opened is not None:
                os.close(opened)
            os.close(root_fd)

    @step
    def build(self, export_fd):
        require(not self._attempted and type(export_fd) is int and export_fd >= 0,
                'One builder attempt with an opened export descriptor required')
        self._attempted = True
        spec = self._spec
        self._export_root(export_fd)
        auxiliary = [
            {'path': 'candidate-contract.json', 'content': canonical(
                {**candidate.metadata(spec), 'export_manifest': spec['export_manifest']}) + b'\n',
             'permissions': 0o644},
            {'path': 'build-recipe.json', 'content': canonical(spec['build_recipe']) + b'\n',
             'permissions': 0o644},
            {'path': 'docker-config/config.json', 'content': b'{}\n', 'permissions': 0o600}]
        candidate.verify_exports(export_fd, spec['export_manifest'], auxiliary=auxiliary)
        self._export_root(export_fd)
        result = bounded(self._call('build', spec['build_recipe']))
        self._export_root(export_fd)
        require(set(result) == {'image_id', 'exit_code', 'log_sha256', 'log_bytes'} and
                type(result['exit_code']) is int and result['exit_code'] == 0 and
                isinstance(result['image_id'], str) and re.fullmatch(r'sha256:[0-9a-f]{64}', result['image_id']) and
                type(result['log_bytes']) is int and 0 <= result['log_bytes'] <= MAX_RESPONSE,
                'Successful bounded immutable-image build response required')
        digest(result['log_sha256'])
        self._state = 'completed'
        return {**self.snapshot(), 'build_observation_sha256': sha(canonical(result))}


class NamespaceAdapter(_Adapter):
    def __init__(self, contract, attempt, network, scratch, images, profiles, *,
                 reviewed_profiles, transport, clock):
        super().__init__(contract, transport, clock)
        text_identity(attempt)
        require(re.fullmatch(r'[A-Za-z0-9_-]{1,128}', attempt), 'Exact bounded attempt required')
        text_identity(network)
        require(isinstance(profiles, dict) and profiles and profiles == reviewed_profiles,
                'Exact separately reviewed profiles required')
        self._profiles = copy.deepcopy(profiles)
        require(isinstance(images, dict), 'Explicit reviewed image mapping required')
        image_mapping = copy.deepcopy(images)
        for identifier in tuple(image_mapping.values()):
            require(isinstance(identifier, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', identifier),
                    'Immutable reviewed image mapping required')
            image_mapping[identifier] = identifier
        self._reviewed_profiles = copy.deepcopy(reviewed_profiles)
        self._policy = Policy(attempt, network, scratch, image_mapping,
                              role_profiles=copy.deepcopy(profiles))
        self._attempt, self._network = attempt, network
        self._started, self._created = set(), []
        self._requests = {}
        self._deleted = set()
        self._cleanup_attempts = set()

    def _request(self, method, path, data=None, *, cleanup=False):
        payload = canonical(data) if data is not None else b''
        rewritten, body = self._policy.admit(method, path, payload)
        response = self._call('request', method, rewritten, body, cleanup=cleanup)
        require(isinstance(response, tuple) and len(response) == 2 and
                type(response[0]) is int, 'Exact HTTP status and structured receipt required')
        status, receipt = response
        bounded(receipt)
        require(200 <= status < 300, 'Injected Docker-shaped operation failed')
        return status, receipt, body

    def _labels(self):
        return {'com.supabase.cli.project': self._attempt, 'soleur.recovery.attempt': self._attempt}

    def _network_observation(self, cleanup=False):
        _, receipt, _ = self._request('GET', '/networks/' + self._policy.network_id, cleanup=cleanup)
        self._policy.verify_network(receipt)
        members = receipt.get('Containers')
        require(isinstance(members, dict) and set(members) <= self._policy.ids,
                'Network contains an unregistered member')
        return receipt

    def _volumes(self, cleanup=False):
        _, receipt, _ = self._request('GET', '/volumes', cleanup=cleanup)
        require(set(receipt) <= {'Volumes', 'Warnings'} and isinstance(receipt.get('Volumes'), list) and
                len(receipt['Volumes']) <= 128, 'Bounded filtered volume observation required')
        names = [row.get('Name') for row in receipt['Volumes'] if isinstance(row, dict)]
        require(len(names) == len(receipt['Volumes']) and len(set(names)) == len(names),
                'Duplicate or malformed volume observation refused')
        return {row['Name']: row for row in receipt['Volumes']}

    def _reobserve_volumes(self, cleanup=False):
        observed = self._volumes(cleanup)
        for name in self._policy.volume_receipts:
            require(name in observed, 'Registered volume observation absent')
            self._policy.verify_volume(name, observed[name])
        return observed

    def _inspect(self, name, cleanup=False):
        identifier = self._policy.own(name)
        _, receipt, _ = self._request('GET', '/containers/' + identifier + '/json', cleanup=cleanup)
        request = self._requests[name]
        config = receipt.get('Config', {})
        endpoint = receipt.get('NetworkSettings', {}).get('Networks', {})
        require(receipt.get('Id') == identifier and receipt.get('Name') == '/' + name and
                receipt.get('Image') == self._profiles[name]['image'] and isinstance(config, dict) and
                all(config.get(key) == request[key] for key in inputs.FIELDS | {'Labels'}) and
                receipt.get('HostConfig') == request['HostConfig'] and set(endpoint) == {self._network} and
                endpoint[self._network].get('NetworkID') == self._policy.network_id,
                'Registered container identity, profile or network observation differs')
        return receipt

    @step
    def create_network(self):
        status, receipt, _ = self._request('POST', '/networks/create',
                                          {'Name': self._network, 'Labels': self._labels()})
        require(status == 201 and set(receipt) <= {'Id', 'Warning'} and
                isinstance(receipt.get('Id'), str), 'Exact successful new network ID required')
        self._policy.created_network(self._network, receipt)
        self._network_observation()
        return self.snapshot()

    @step
    def create_volume(self, name):
        require(name in self._policy.volume_names and name not in self._policy.volume_attempted,
                'Reserved once-only volume name required')
        require(self._policy.network_id is not None, 'Registered network required')
        self._network_observation()
        require(name not in self._volumes(), 'Supplied reserved-volume absence differs')
        self._policy.recorded_volume_absence(name)
        status, receipt, _ = self._request('POST', '/volumes/create', {'Name': name, 'Labels': self._labels()})
        require(status == 201, 'Successful volume creation required')
        self._policy.created_volume(name, receipt)
        self._reobserve_volumes()
        return self.snapshot()

    def _prerequisites(self, name):
        profile = self._profiles.get(name)
        require(profile is not None and name not in self._policy.creation_names, 'Reserved new role required')
        role = profile['role']
        require(self._policy.network_id is not None and
                set(self._policy.volume_receipts) == self._policy.volume_names, 'Network and both volumes required')
        prerequisites = set()
        if role == 'kong':
            prerequisites = {'supabase_' + role + '_' + self._attempt
                             for role in ('db', 'auth', 'inbucket', 'rest', 'storage')}
        elif role in ('tls', 'resolver'):
            prerequisites = {'supabase_kong_' + self._attempt}
        elif role in ('renderer', 'browser'):
            prerequisites = {'codex9051-' + role + '-' + self._attempt for role in ('tls', 'resolver')}
            if name.endswith('-replacement'):
                prerequisites.add('codex9051-renderer-' + self._attempt + '-first')
        elif role == 'migration':
            prerequisites = {'supabase_db_' + self._attempt}
        require(prerequisites <= self._started, 'Started namespace prerequisites absent')
        for prerequisite in sorted(prerequisites):
            require(self._inspect(prerequisite).get('State', {}).get('Running') is True,
                    'Started prerequisite no longer running')
        return profile

    @step
    def create_role(self, name):
        profile = self._prerequisites(name)
        self._network_observation()
        self._reobserve_volumes()
        _, image, _ = self._request('GET', '/images/' + quote(profile['image'], safe=':') + '/json')
        _, again, _ = self._request('GET', '/images/' + quote(profile['image'], safe=':') + '/json')
        inputs.profile_spec(self._contract, self._attempt, name, profile,
                            reviewed_profile=self._reviewed_profiles[name], observed_image=image, reobserved_image=again)
        self._policy.roles.verify_image(name, again)
        status, receipt, body = self._request('POST', '/containers/create?name=' + quote(name, safe=''),
                                             {'Image': profile['image'], 'Labels': self._labels()})
        require(status == 201 and set(receipt) <= {'Id', 'Warnings'} and
                isinstance(receipt.get('Id'), str) and re.fullmatch(r'[0-9a-f]{64}', receipt['Id']) and
                receipt['Id'] != self._policy.network_id and receipt['Id'] not in self._policy.ids,
                'Distinct successful new container ID required')
        self._policy.created_container(name, receipt['Id'])
        import json
        self._requests[name] = json.loads(body)
        self._created.append(name)
        self._inspect(name)
        return self.snapshot()

    @step
    def start_role(self, name):
        require(name in self._created and name not in self._started, 'Once-only registered start required')
        self._network_observation()
        self._reobserve_volumes()
        self._inspect(name)
        self._request('POST', '/containers/' + self._policy.own(name) + '/start')
        observed = self._inspect(name)
        require(observed.get('State', {}).get('Running') is True, 'Started container observation absent')
        self._started.add(name)
        return self.snapshot()

    @step
    def namespace(self):
        expected = {'supabase_kong_' + self._attempt,
                    'codex9051-tls-' + self._attempt, 'codex9051-resolver-' + self._attempt}
        require(expected <= self._started, 'Started Kong, TLS and resolver required')
        network = self._network_observation()
        for name in sorted(expected):
            self._inspect(name)
        recipe = namespace_recipe(self._policy, network, self._inspect('supabase_kong_' + self._attempt),
                                  self._contract['browser']['hostname'])
        return {**self.snapshot(), 'namespace_specification_sha256': sha(canonical(recipe))}

    def cleanup(self):
        # Never remove parent resources after an unverified/failed child cleanup.
        for name in reversed(self._created):
            if name in self._deleted or ('container', name) in self._cleanup_attempts:
                continue
            try:
                self._remaining(True)
                self._inspect(name, True)
                identifier = self._policy.own(name)
                self._cleanup_attempts.add(('container', name))
                self._request('DELETE', '/containers/' + identifier + '?force=true', cleanup=True)
                self._policy.removed_container(identifier)
                self._deleted.add(name)
            except Exception:
                self._cleanup_errors += 1
        if (len(self._deleted) == len(self._created) and not self._policy.pending and
                not self._policy.volume_pending and not self._policy.network_pending):
            for name in tuple(self._policy.volume_receipts):
                if ('volume', name) in self._cleanup_attempts:
                    continue
                try:
                    self._remaining(True)
                    self._reobserve_volumes(True)
                    self._cleanup_attempts.add(('volume', name))
                    self._request('DELETE', '/volumes/' + quote(name, safe=''), cleanup=True)
                    self._policy.removed_volume(name)
                except Exception:
                    self._cleanup_errors += 1
            if (not self._policy.volume_receipts and self._policy.network_id is not None and
                    ('network', self._policy.network_id) not in self._cleanup_attempts):
                try:
                    self._remaining(True)
                    self._network_observation(True)
                    identifier = self._policy.network_id
                    self._cleanup_attempts.add(('network', identifier))
                    self._request('DELETE', '/networks/' + identifier, cleanup=True)
                    self._policy.removed_network(identifier)
                except Exception:
                    self._cleanup_errors += 1
        if self._cleanup_errors and self._primary is None:
            self._primary = 'Owned namespace cleanup incomplete'
        self._state = 'failed' if self._primary else 'closed'
        return self.snapshot()


class SessionAdapter(_Adapter):
    def __init__(self, contract, attempt, database, binding, handles, *, transport, clock):
        super().__init__(contract, transport, clock)
        require(isinstance(binding, ScenarioBinding) and binding.source_sha == self._contract['identity']['source_sha'] and
                {name: binding.scenario_hash(name) for name in SCENARIOS} ==
                self._contract.get('session_prerequisites', {}).get('scenario_sha256'),
                'Complete current-source scenario binding required')
        require(isinstance(handles, dict) and set(handles) == {'holder', 'waiter'} and
                all(isinstance(handle, SessionIdentity) and handle.attempt == attempt and
                    handle.database == database and type(handle.backend_pid) is int and handle.backend_pid > 0 and
                    type(handle.process_pid) is int and handle.process_pid > 0 and
                    all(_token(value) for value in (handle.backend_birth, handle.process_birth, handle.session_id))
                    for handle in handles.values()), 'Exact complete registered existing handles required')
        holder, waiter = handles['holder'], handles['waiter']
        require(holder.backend_pid != waiter.backend_pid and holder.process_pid != waiter.process_pid and
                holder.session_id != waiter.session_id, 'Distinct registered existing sessions required')
        self._handles = copy.deepcopy(handles)
        self._binding = binding
        self._race = RaceController(attempt, database, binding, lambda: read_clock(clock, 'monotonic'))
        self._touched, self._closed = [], set()
        self._cleanup_attempts = set()

    def _remaining(self, cleanup=False):
        remaining = super()._remaining(cleanup)
        if not cleanup:
            self._race.check_deadline()
            race_deadline = self._race.snapshot()['race_deadline']
            remaining = min(remaining, race_deadline - self._tick())
            require(remaining > 0, 'Race transport deadline expired')
        return remaining

    def _identity(self, handle, cleanup=False):
        require(self._call('identity', handle, cleanup=cleanup) == handle,
                'Existing session PID or birth identity differs')

    def _body(self, number):
        return self._binding.entries[number][2]

    @step
    def begin(self):
        require(self._state == 'ready', 'Race begin is single-use')
        for role, number in (('holder', 0), ('waiter', 1)):
            self._race.check_deadline()
            handle = self._handles[role]
            self._identity(handle)
            getattr(self._race, 'register_' + role)(handle, self._binding.scenario_hash(SCENARIOS[number]))
            self._touched.append(handle)
            receipt = self._call('start', handle, self._body(number))
            require(isinstance(receipt, dict) and set(receipt) == {'identity', 'scenario_sha256', 'exit_code'} and
                    receipt['identity'] == handle and receipt['scenario_sha256'] == sha(self._body(number)) and
                    type(receipt['exit_code']) is int and receipt['exit_code'] == 0,
                    'Exact successful bound scenario start receipt required')
        self._state = 'waiting'

    @step
    def observe(self):
        require(self._state == 'waiting', 'Observation requires started waiting sessions')
        self._race.check_deadline()
        require(self._race.snapshot()['observations'] < MAX_OBSERVATIONS, 'Race observation budget exhausted')
        holder, waiter = self._handles['holder'], self._handles['waiter']
        self._identity(holder)
        self._identity(waiter)
        receipt = self._call('observe', holder, waiter, self._body(2))
        require(isinstance(receipt, dict) and set(receipt) == {'holder', 'waiter', 'blockers', 'holder_state',
                'waiter_event_type', 'observer_exit_code', 'scenario_sha256'}, 'Exact lock dependency observation required')
        blocked = self._race.observe_blocking(**receipt)
        if blocked:
            self._state = 'blocked'
        return blocked

    @step
    def complete(self):
        require(self._state == 'blocked' and self._race.commit_permitted,
                'Observed exact lock dependency required before commit')
        holder, waiter = self._handles['holder'], self._handles['waiter']
        self._race.commit_recipe()
        self._identity(holder)
        receipt = self._call('commit', holder)
        require(isinstance(receipt, dict) and set(receipt) == {'identity', 'command_tag', 'exit_code'},
                'Exact holder commit receipt required')
        self._race.observe_holder_commit(**receipt)
        self._identity(waiter)
        receipt = self._call('wait', waiter)
        require(isinstance(receipt, dict) and set(receipt) == {'identity', 'exit_code'},
                'Exact waiter completion receipt required')
        self._race.observe_waiter_exit(**receipt)
        self._race.check_deadline()
        receipt = self._call('assertion', self._body(3))
        require(isinstance(receipt, dict) and set(receipt) == {'scenario_sha256', 'exit_code'},
                'Exact source assertion receipt required')
        self._race.observe_assertion(**receipt)
        self._state = 'completed'
        return self.snapshot()

    def cleanup(self):
        for handle in self._touched:
            if handle in self._closed or ('close', handle) in self._cleanup_attempts:
                continue
            try:
                self._remaining(True)
                self._identity(handle, True)
            except Exception:
                self._cleanup_errors += 1
                continue
            for operation in ('rollback', 'close'):
                if (operation, handle) in self._cleanup_attempts:
                    continue
                try:
                    self._identity(handle, True)
                    self._cleanup_attempts.add((operation, handle))
                    receipt = self._call(operation, handle, cleanup=True)
                    require(isinstance(receipt, dict) and set(receipt) == {'identity', 'exit_code'} and
                            receipt['identity'] == handle and type(receipt['exit_code']) is int and
                            receipt['exit_code'] == 0, 'Exact owned session cleanup receipt required')
                    if operation == 'close':
                        self._closed.add(handle)
                except Exception:
                    self._cleanup_errors += 1
        if self._cleanup_errors and self._primary is None:
            self._primary = 'Owned session cleanup incomplete'
        self._state = 'failed' if self._primary else 'closed'
        return self.snapshot()


class RetainedAdapter(_Adapter):
    def __init__(self, contract, attempt, owner, database, resource, writers, *,
                 transport, clock, observation_clock):
        super().__init__(contract, transport, clock)
        text_identity(owner)
        text_identity(database)
        require(callable(observation_clock), 'Separate injected epoch observation clock required')
        retained_files.checked_binding({**resource, 'quiescence_id': '0' * 64})
        require(resource['attempt'] == attempt and resource['source_sha'] == self._contract['identity']['source_sha'] and
                resource['pairing_sha256'] == self._contract['pairing_sha256'], 'Registered retained source differs')
        inputs.writer_census(writers)
        self._resource, self._writers = copy.deepcopy(resource), copy.deepcopy(writers)
        self._owner, self._database = owner, database
        self._wall = observation_clock
        self._manifests, self._observations = {}, {}
        self._next = 'before'
        self._last_wall = None

    def _epoch(self):
        instant = read_clock(self._wall, 'observation')
        require(type(instant) is int and instant >= 0 and
                (self._last_wall is None or instant >= self._last_wall), 'Ordered integer epoch observation required')
        self._last_wall = instant
        return instant

    def _resource_observation(self):
        receipt = self._call('resource', self._resource)
        require(isinstance(receipt, dict) and set(receipt) == {'resource', 'owner_id', 'database_id', 'writers'} and
                receipt['resource'] == self._resource and receipt['owner_id'] == self._owner and
                receipt['database_id'] == self._database and
                inputs.writer_census(receipt['writers']) == inputs.writer_census(self._writers),
                'Registered root, owner, database or complete writers differ')

    @step
    def collect(self, phase, expected_paths):
        require(phase == self._next and phase in ('before', 'after'), 'Once-only ordered retained phase required')
        self._resource_observation()
        # Each collection owns a separate release window. Retain a late but
        # structurally owned lease before refusing progress so it can be released.
        self._cleanup_deadline = None
        quiet = self._call('quiesce', self._resource, self._writers, phase, check_after=False)
        require(isinstance(quiet, dict) and set(quiet) == {'binding', 'writers', 'quiescent_writers', 'quiescence_start'},
                'Exact quiescence observation required')
        binding = quiet['binding']
        retained_files.checked_binding(binding)
        require({key: binding[key] for key in self._resource} == self._resource,
                'Quiescence source or registered resource differs')
        descriptor = None
        failure = None
        try:
            self._remaining()
            require(type(quiet['quiescence_start']) is int and quiet['quiescence_start'] >= 0 and
                    inputs.writer_census(quiet['writers']) == inputs.writer_census(self._writers) and
                    inputs.writer_census(quiet['quiescent_writers']) == inputs.writer_census(self._writers),
                    'Quiescence time or complete writer identity differs')
            timeout = self._remaining()
            try:
                callback = getattr(self._transport, 'open_root', None)
            except Exception:
                raise Refused('Injected root opener lookup failed') from None
            require(callable(callback), 'Injected registered root opener absent')
            self._calls['open_root'] = self._calls.get('open_root', 0) + 1
            # Take ownership before checking the clock, so a late returned fd closes.
            try:
                opened = callback(copy.deepcopy(self._resource), timeout=timeout)
            except Exception:
                raise Refused('Injected root opener failed') from None
            require(type(opened) is int and opened >= 0, 'Transferred owned root descriptor required')
            descriptor = opened
            self._remaining()
            start = self._epoch()
            manifest = retained_files.snapshot(descriptor, binding, copy.deepcopy(expected_paths))
            end = self._epoch()
            self._resource_observation()
            observation = self._call('finish_collection', self._resource, self._writers, phase, start, end)
            times = ('quiescence_start', 'collection_start', 'collection_end', 'quiescence_end',
                     'observed_at', 'expires_at')
            fields = {'binding', 'phase', 'owner_id', 'database_id', 'writers', 'quiescent_writers',
                      'observer_id', 'artifact_sha256'} | set(times)
            now = self._epoch()
            require(isinstance(observation, dict) and set(observation) == fields and
                    observation['binding'] == binding and observation['phase'] == phase and
                    observation['owner_id'] == self._owner and observation['database_id'] == self._database and
                    inputs.writer_census(observation['writers']) == inputs.writer_census(self._writers) and
                    inputs.writer_census(observation['quiescent_writers']) == inputs.writer_census(self._writers) and
                    all(type(observation[key]) is int and observation[key] >= 0 for key in times),
                    'Complete retained observation differs')
            quiet_start, observed_start, observed_end, quiet_end, observed, expiry = (observation[key] for key in times)
            require(observed_start == start and observed_end == end and quiet_start == quiet['quiescence_start'] and
                    now - BUDGET['work_seconds'] <= quiet_start <= start <= end <= quiet_end <= observed <= now < expiry and
                    expiry <= self._contract['browser']['expires_at'] and expiry - quiet_start <= BUDGET['work_seconds'],
                    'Collection is outside the supplied enclosing quiescence window')
            text_identity(observation['observer_id'])
            digest(observation['artifact_sha256'])
            self._manifests[phase], self._observations[phase] = manifest, observation
            self._next = 'after' if phase == 'before' else 'compare'
        except Exception as error:
            failure = str(error) if isinstance(error, Refused) else 'Retained collection failed'
        finally:
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    failure = failure or 'Owned root descriptor close failed'
            if failure:
                try:
                    self._fail(failure)
                except Refused:
                    pass
            try:
                self._call('release', self._resource, self._writers, binding['quiescence_id'], cleanup=True)
            except Exception:
                self._cleanup_errors += 1
                failure = failure or 'Owned quiescence release failed'
        if failure:
            self._fail(failure)
        return {**self.snapshot(), 'manifest_sha256': manifest['manifest_sha256']}

    @step
    def compare(self, erased_paths=()):
        require(self._next == 'compare', 'Complete before and after collections required')
        result = inputs.retention_spec(self._contract, self._manifests['before'], self._manifests['after'],
            self._observations['before'], self._observations['after'], expected_owner=self._owner,
            expected_database=self._database, expected_resource=self._resource,
            expected_writers=self._writers, now=self._epoch(), erased_paths=erased_paths)
        self._next, self._state = 'done', 'completed'
        return {**self.snapshot(), 'retention_specification_sha256': result['specification_sha256']}

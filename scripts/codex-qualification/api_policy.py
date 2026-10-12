"""Task-owned Docker API admission policy; never contacts Docker by itself."""
import copy
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, quote, urlencode, urlsplit

class Refused(RuntimeError):
    pass

class MissingOwnedContainer(Refused):
    """A reserved name has no registered ID; answer 404 without consulting Docker."""
    pass

class Policy:
    def __init__(self, project, network, scratch, images, memory_budget=8 * 1024**3):
        self.project = project
        self.network = network
        self.scratch = Path(scratch).resolve()
        self.images = images  # reviewed tag or immutable ID -> immutable local config ID
        self.ids = set()
        self.name_ids = {}
        self.exec_ids = set()
        self.exec_containers = {}
        self.pending = {}
        self.failed_names = set()
        self.creation_names = set()
        self.memory = {}
        self.memory_budget = memory_budget
        self.job = 0
        self.network_id = None
        self.network_pending = False
        self.network_attempted = False
        self.volume_absent = set()
        self.volume_pending = set()
        self.volume_attempted = set()
        self.volume_receipts = {}
        self.volume_names = {'supabase_db_' + project, 'supabase_storage_' + project}
        self.names = {'supabase_' + role + '_' + project for role in
                      ('db', 'kong', 'auth', 'inbucket', 'rest', 'storage')}
        self.names.update({'codex9051-renderer-' + project + '-' + x for x in ('first', 'replacement')})

    def require(self, ok, message):
        if not ok:
            raise Refused(message)

    def own(self, value):
        if value in self.ids:
            return value
        identifier = self.name_ids.get(value)
        self.require(identifier is not None and identifier in self.ids,
                     'Container mutation/read requires a successfully created registered ID')
        return identifier

    def exec_config(self, data):
        self.require(set(data) <= {'Cmd','Env','Privileged','User','WorkingDir','Tty',
                     'AttachStdin','AttachStdout','AttachStderr','DetachKeys','ConsoleSize'},
                     'Unreviewed exec-create field refused')
        self.require(data.get('Privileged') is None or data.get('Privileged') is False,
                     'Privileged exec refused')
        self.require(data.get('User') in (None,''), 'Exec user override refused')
        self.require(data.get('Tty') is None or data.get('Tty') is False, 'Exec TTY refused')
        self.require(data.get('WorkingDir') in (None,'','/app','/tmp'), 'Exec working directory refused')
        command = data.get('Cmd')
        self.require(isinstance(command,list) and 0 < len(command) <= 32 and
                     all(isinstance(x,str) and '\x00' not in x for x in command) and
                     sum(len(x) for x in command) <= 8192, 'Bounded exec command required')
        environment = [] if data.get('Env') is None else data['Env']
        allowed = {'PATH': {'/usr/local/bin:/usr/bin:/bin','/usr/bin:/bin'},
                   'HOME': {'/tmp','/home/soleur'}, 'LANG': {'C','C.UTF-8'},
                   'NODE_ENV': {'production'}, 'NEXT_TELEMETRY_DISABLED': {'1'}}
        self.require(isinstance(environment,list) and len(environment) <= len(allowed),
                     'Unreviewed exec environment refused')
        seen = set()
        for setting in environment:
            self.require(isinstance(setting,str) and '=' in setting and '\x00' not in setting,
                         'Malformed exec environment refused')
            key,value = setting.split('=',1)
            self.require(key in allowed and value in allowed[key] and key not in seen,
                         'Exec credential or unreviewed environment refused')
            seen.add(key)
        for key in ('AttachStdin','AttachStdout','AttachStderr'):
            self.require(data.get(key) is None or type(data[key]) is bool, 'Malformed exec attach flag')
        self.require(data.get('DetachKeys') in (None,'','ctrl-p,ctrl-q'), 'Unreviewed detach keys refused')
        self.console_size(data)

    def console_size(self, data):
        size = data.get('ConsoleSize')
        self.require(size is None or (isinstance(size,list) and len(size)==2 and
                     all(type(x) is int and 0 <= x <= 512 for x in size)),
                     'Unreviewed console dimensions refused')

    def labels(self, data):
        labels = dict(data.get('Labels') or {})
        self.require(labels.get('com.supabase.cli.project') == self.project,
                     'Exact project label is required')
        self.require(labels.get('com.docker.compose.project', self.project) == self.project,
                     'Compose project label differs')
        labels['soleur.recovery.attempt'] = self.project
        data['Labels'] = labels

    def admit(self, method, path, payload=b''):
        split = urlsplit(path)
        self.require(not split.scheme and not split.netloc and not split.fragment,
                     'Only origin-form Docker API paths are admitted')
        route = re.sub(r'^/v[0-9.]+(?=/)', '', split.path)
        query = parse_qs(split.query, keep_blank_values=True)
        self.require(all(len(values) == 1 for values in query.values()), 'Duplicate query fields refused')
        data = json.loads(payload) if payload else {}
        self.require(isinstance(data,dict), 'Docker request must be a JSON object')
        prefix = split.path[:-len(route)] if split.path != route else ''
        if method in ('GET', 'HEAD') and route in ('/_ping', '/version', '/info'):
            return path, payload
        if method == 'GET' and route == '/containers/json':
            query['filters'] = [json.dumps({'label': ['com.supabase.cli.project=' + self.project]})]
            return prefix + route + '?' + urlencode(query, doseq=True), payload
        if method == 'GET' and route.startswith('/images/') and route.endswith('/json'):
            image = route[len('/images/'):-len('/json')]
            from urllib.parse import unquote
            image = unquote(image)
            self.require(image in self.images, 'Image inspection is outside immutable admission')
            return prefix + '/images/' + quote(self.images[image], safe=':') + '/json', payload
        if method == 'GET' and route in ('/volumes', '/networks'):
            query['filters'] = [json.dumps({'label': ['soleur.recovery.attempt=' + self.project]})]
            return prefix + route + '?' + urlencode(query, doseq=True), payload
        if method == 'POST' and route == '/networks/create':
            self.require(set(data) <= {'Name', 'Labels', 'Driver', 'Internal', 'EnableIPv6',
                         'Options', 'CheckDuplicate'}, 'Unreviewed network fields refused')
            self.require(data.get('Name') == self.network, 'Foreign network creation refused')
            self.require(not self.network_attempted, 'Network creation cannot be reused')
            self.labels(data)
            data['Internal'] = True
            data['Driver'] = 'bridge'
            data['EnableIPv6'] = False
            data['CheckDuplicate'] = True
            data['Options'] = {'com.docker.network.bridge.host_binding_ipv4': '127.0.0.1'}
            self.network_pending = True
            self.network_attempted = True
            return path, json.dumps(data).encode()
        if method == 'POST' and route == '/volumes/create':
            self.require(set(data) <= {'Name', 'Driver', 'DriverOpts', 'Labels'},
                         'Unreviewed volume fields refused')
            self.require(data.get('Name') in self.volume_names, 'Foreign volume creation refused')
            self.require(data['Name'] not in self.volume_attempted, 'Volume creation cannot be reused')
            self.require(not data.get('DriverOpts'), 'Volume driver options refused')
            self.labels(data)
            data['Driver'] = 'local'
            self.volume_pending.add(data['Name'])
            self.volume_attempted.add(data['Name'])
            return path, json.dumps(data).encode()
        if method == 'POST' and route == '/containers/create':
            self.require(self.network_id is not None, 'Container requires registered owned network')
            self.labels(data)
            name = query.get('name', [''])[0]
            if not name:
                self.job += 1
                self.require(self.job <= 8, 'Temporary migration-job bound exceeded')
                name = 'codex9051-job-' + self.project + '-' + str(self.job)
                self.names.add(name)
                query['name'] = [name]
            self.require(name in self.names, 'Foreign named container creation refused')
            self.require(name not in self.creation_names, 'Container creation attempt cannot be reused')
            self.require(data.get('Image') in self.images, 'Unadmitted image refused')
            data['Image'] = self.images[data['Image']]
            host = copy.deepcopy(data.get('HostConfig') or {})
            self.require(set(host) <= {'Privileged', 'CapAdd', 'Devices', 'DeviceRequests',
                         'NetworkMode', 'PidMode', 'IpcMode', 'UTSMode', 'CgroupnsMode',
                         'ExtraHosts', 'Binds', 'Mounts', 'PortBindings', 'Memory', 'MemorySwap',
                         'CpuPeriod', 'CpuQuota', 'PidsLimit', 'RestartPolicy', 'SecurityOpt',
                         'AutoRemove', 'ShmSize', 'ReadonlyRootfs', 'LogConfig'},
                         'Unreviewed container host fields refused')
            self.require(host.get('AutoRemove') in (None, False), 'Automatic removal loses provenance')
            self.require(not host.get('Privileged') and not host.get('CapAdd'),
                         'Privilege elevation refused')
            self.require(not host.get('Devices') and not host.get('DeviceRequests'),
                         'Device access refused')
            self.require(host.get('NetworkMode') in (None, '', self.network, self.network_id),
                         'Foreign/host/container network refused')
            for key in ('PidMode', 'IpcMode', 'UTSMode', 'CgroupnsMode'):
                self.require(host.get(key) in (None, '', 'private'), 'Shared namespace refused: ' + key)
            self.require(host.get('ExtraHosts') in (None, [], ['host.docker.internal:host-gateway']),
                         'Unreviewed host aliases refused')
            # CLI 2.84.2 adds this host escape by default on Linux. Remove it.
            host['ExtraHosts'] = []
            self.require(host.get('LogConfig') in (None, {}, {'Type': 'json-file', 'Config': {}}),
                         'Daemon logging override refused')
            host['LogConfig'] = {'Type': 'json-file', 'Config': {'max-size': '10m', 'max-file': '1'}}
            for binding in (host.get('Binds') or []):
                src = binding.split(':', 1)[0]
                if src.startswith('/'):
                    self.require(Path(src).resolve().is_relative_to(self.scratch),
                                 'Host bind is outside task scratch')
                else:
                    self.require(src in self.volume_receipts, 'Unowned named volume refused')
            self.require(not host.get('Mounts'), 'Unreviewed Mounts contract refused')
            for mappings in (host.get('PortBindings') or {}).values():
                for mapping in mappings:
                    self.require(mapping.get('HostIp') in (None, '', '127.0.0.1'),
                                 'Non-loopback port publication refused')
                    self.require(mapping.get('HostPort') in {str(x) for x in range(59051, 59061)},
                                 'Unadmitted host port refused')
                    mapping['HostIp'] = '127.0.0.1'
            endpoints = (data.get('NetworkingConfig') or {}).get('EndpointsConfig', {})
            self.require(set(endpoints) <= {self.network, self.network_id}, 'Foreign endpoint network refused')
            self.require(len(endpoints) <= 1, 'Duplicate network aliases refused')
            self.require(all(not e.get('IPAMConfig') for e in endpoints.values()), 'Static endpoint IP refused')
            self.require(all(set(e) <= {'Aliases'} for e in endpoints.values()),
                         'Unreviewed endpoint fields refused')
            data['NetworkingConfig'] = {'EndpointsConfig': {self.network_id: next(iter(endpoints.values()), {})}}
            for setting in data.get('Env') or []:
                key = setting.split('=', 1)[0]
                self.require(not key.startswith(('OPENAI_', 'ANTHROPIC_', 'CODEX_', 'DOPPLER_', 'FLAGS',
                             'SENTRY_', 'INNGEST_', 'LD_')) and key not in
                             {'DATABASE_URL_POOLER', 'SUPABASE_ACCESS_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY',
                              'ALL_PROXY', 'NODE_OPTIONS', 'NODE_PATH', 'DOCKER_HOST'},
                             'Account/provider environment refused')
            limit = 1024**3 if name == 'supabase_db_' + self.project else 512 * 1024**2
            if name.startswith('codex9051-renderer-'):
                limit = 2 * 1024**3
            self.require(sum(self.memory.values()) + sum(self.pending.values()) + limit <= self.memory_budget,
                         'Total admitted memory budget exceeded')
            host.update({'NetworkMode': self.network_id, 'Memory': limit, 'MemorySwap': limit,
                         'CpuPeriod': 100000,
                         'CpuQuota': 200000 if name.startswith('codex9051-renderer-') else 100000,
                         'PidsLimit': 256,
                         'RestartPolicy': {'Name': 'no'},
                         'SecurityOpt': ['no-new-privileges:true']})
            data['HostConfig'] = host
            self.pending[name] = limit
            self.creation_names.add(name)
            return prefix + route + '?' + urlencode(query, doseq=True), json.dumps(data).encode()
        match = re.fullmatch(r'/containers/([^/]+)(?:/(json|logs|start|stop|wait|kill|exec))?', route)
        if match:
            target, operation = match.groups()
            if method == 'GET' and operation == 'json' and target in self.names and target not in self.name_ids:
                raise MissingOwnedContainer('No registered container exists for reserved name')
            identifier = self.own(target)
            permitted = ((method == 'GET' and operation in ('json', 'logs')) or
                         (method == 'POST' and operation in ('start', 'stop', 'wait', 'kill', 'exec')) or
                         (method == 'DELETE' and operation is None))
            self.require(permitted, 'Container operation refused')
            if method == 'POST' and operation == 'exec':
                self.exec_config(data)
            suffix = '/' + operation if operation else ''
            rewritten = prefix + '/containers/' + identifier + suffix
            if split.query:
                rewritten += '?' + split.query
            return rewritten, payload
        match = re.fullmatch(r'/exec/([^/]+)/(start|json|resize)', route)
        if match:
            self.require(match[1] in self.exec_ids and self.exec_containers.get(match[1]) in self.ids,
                         'Exec parent is outside registered owned inventory')
            self.require((method == 'POST' and match[2] in ('start', 'resize')) or
                         (method == 'GET' and match[2] == 'json'), 'Exec operation refused')
            if method == 'POST' and match[2] == 'start':
                self.require(set(data) <= {'Detach','Tty','ConsoleSize'}, 'Unreviewed exec-start field refused')
                self.require(data.get('Detach') is None or data.get('Detach') is False, 'Detached exec refused')
                self.require(data.get('Tty') is None or data.get('Tty') is False, 'Exec-start TTY refused')
                self.console_size(data)
            return path, payload
        if method == 'DELETE' and route.startswith('/volumes/'):
            self.require(route[len('/volumes/'):] in self.volume_receipts,
                         'Volume removal requires successful owned creation')
            return path, payload
        if method in ('GET', 'DELETE') and route.startswith('/networks/'):
            target = route[len('/networks/'):]
            if method == 'GET' and target == self.network and self.network_id is None:
                raise MissingOwnedContainer('No registered network exists for reserved name')
            self.require(self.network_id is not None and target in (self.network, self.network_id),
                         'Network operation requires successful owned creation')
            return prefix + '/networks/' + self.network_id, payload
        raise Refused('Unsupported Docker API contract: ' + method + ' ' + route)

    def recorded_volume_absence(self, name):
        self.require(name in self.volume_names and name not in self.volume_attempted,
                     'Absence receipt is only valid before first create')
        self.volume_absent.add(name)

    def created_network(self, name, receipt):
        self.require(self.network_pending and name == self.network and
                     re.fullmatch(r'[0-9a-f]{64}', receipt.get('Id', '')),
                     'Network creation must return a fresh registered ID')
        self.network_id = receipt['Id']
        self.network_pending = False

    def verify_network(self, receipt):
        self.require(self.network_id is not None and receipt.get('Id') == self.network_id and
                     receipt.get('Name') == self.network and receipt.get('Driver') == 'bridge' and
                     receipt.get('Internal') is True and receipt.get('EnableIPv6') is False and
                     receipt.get('Labels', {}).get('soleur.recovery.attempt') == self.project,
                     'Live network identity or isolation differs')

    def removed_network(self, identifier):
        self.require(identifier == self.network_id and identifier is not None,
                     'Network removal is outside registered inventory')
        self.network_id = None

    def created_volume(self, name, receipt):
        self.require(name in self.volume_pending and name in self.volume_absent,
                     'Volume creation requires prior absence and pending create')
        self.require(receipt.get('Name') == name and receipt.get('Driver') == 'local' and
                     receipt.get('Scope') == 'local' and not receipt.get('Options') and
                     isinstance(receipt.get('CreatedAt'), str) and bool(receipt['CreatedAt']) and
                     receipt.get('Labels', {}).get('soleur.recovery.attempt') == self.project and
                     receipt.get('Labels', {}).get('com.supabase.cli.project') == self.project,
                     'Volume creation returned foreign or malformed provenance')
        self.volume_receipts[name] = copy.deepcopy(receipt)
        self.volume_pending.remove(name)
        self.volume_absent.remove(name)

    def verify_volume(self, name, receipt):
        self.require(name in self.volume_receipts, 'Volume has no successful creation receipt')
        original = self.volume_receipts[name]
        self.require(all(receipt.get(key) == original.get(key) for key in
                         ('Name', 'Driver', 'Scope', 'CreatedAt', 'Labels', 'Options', 'Mountpoint')),
                     'Live volume differs from its creation receipt')

    def removed_volume(self, name):
        self.require(name in self.volume_receipts, 'Volume removal is outside owned inventory')
        del self.volume_receipts[name]

    def created_container(self, name, image_id):
        self.require(name in self.pending and re.fullmatch(r'[0-9a-f]{64}', image_id),
                     'Unadmitted container creation response')
        self.ids.add(image_id)
        self.name_ids[name] = image_id
        self.memory[image_id] = self.pending.pop(name)

    def failed_container_creation(self, name):
        self.require(name in self.creation_names, 'Unregistered creation failure')
        self.pending.pop(name,None)
        self.failed_names.add(name)

    def removed_container(self, image_id):
        self.own(image_id)
        self.ids.discard(image_id)
        self.memory.pop(image_id, None)
        self.name_ids = {name: value for name, value in self.name_ids.items() if value != image_id}
        self.exec_containers = {key: value for key, value in self.exec_containers.items() if value != image_id}
        self.exec_ids = set(self.exec_containers)

    def created_exec(self, exec_id, container):
        self.require(re.fullmatch(r'[0-9a-f]{64}', exec_id), 'Malformed exec ID')
        identifier = self.own(container)
        self.exec_ids.add(exec_id)
        self.exec_containers[exec_id] = identifier


def self_test():
    tag = 'public.ecr.aws/supabase/postgres:17.6.1.095'
    immutable = 'sha256:' + 'a' * 64
    p = Policy('fixture', 'fixture-internal', '/tmp/fixture', {tag: immutable, immutable: immutable})
    p.admit('POST', '/networks/create', json.dumps({'Name': p.network,
            'Labels': {'com.supabase.cli.project': p.project}}).encode())
    p.created_network(p.network, {'Id': 'd' * 64})
    base = {'Image': tag, 'Labels': {'com.supabase.cli.project': 'fixture'},
            'HostConfig': {'PortBindings': {'5432/tcp': [{'HostPort': '59052'}]}}}
    route, body = p.admit('POST', '/v1.47/containers/create?name=supabase_db_fixture', json.dumps(base).encode())
    admitted = json.loads(body)
    assert admitted['Image'] == immutable and admitted['HostConfig']['Memory'] == 1024**3
    assert admitted['HostConfig']['PortBindings']['5432/tcp'][0]['HostIp'] == '127.0.0.1'
    p.created_container('supabase_db_fixture', 'b' * 64)
    checks = 1
    for key, value in [('Privileged', True), ('NetworkMode', 'host'),
                       ('Binds', ['/var/run/docker.sock:/var/run/docker.sock']),
                       ('CapAdd', ['NET_ADMIN']), ('Devices', [{'PathOnHost': '/dev/sda'}]),
                       ('ExtraHosts', ['foreign:host-gateway']),
                       ('Mounts', [{'Type': 'bind', 'Source': '/home'}])]:
        changed = copy.deepcopy(base)
        changed['HostConfig'][key] = value
        try:
            p.admit('POST', '/containers/create?name=supabase_storage_fixture', json.dumps(changed).encode())
            raise AssertionError('Unsafe create was admitted: ' + key)
        except Refused:
            checks += 1
    for method, route in [('POST', '/images/create?fromImage=ubuntu'),
                          ('POST', '/containers/foreign/start'),
                          ('DELETE', '/containers/foreign'),
                          ('POST', '/networks/foreign/connect'),
                          ('POST', '/build'), ('POST', '/system/prune'),
                          ('GET', '/containers/foreign/json')]:
        try:
            p.admit(method, route)
            raise AssertionError('Foreign mutation/read was admitted: ' + route)
        except Refused:
            checks += 1
    rewritten, _ = p.admit('GET', '/containers/json?all=true')
    assert 'com.supabase.cli.project' in rewritten and 'fixture' in rewritten
    checks += 1
    rewritten, _ = p.admit('GET', '/images/' + tag + '/json')
    assert immutable in rewritten
    checks += 1
    route, body = p.admit('POST', '/containers/create', json.dumps(base).encode())
    assert 'codex9051-job-fixture-1' in route
    checks += 1
    print(json.dumps({'policy_fixture_checks': checks, 'docker_calls': 0, 'status': 'pass'}))

if __name__ == '__main__':
    self_test()

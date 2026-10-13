"""Controller-supplied exact role profiles. No daemon, workload or CLI entrypoint.

Profiles are reviewed controller input, never accepted through the Docker API.
Immutable image Config snapshots must be observed again before creation. All
commands including inherited health checks and environments are bound.
"""
import copy
import re

FIELDS = {'Entrypoint', 'Cmd', 'Env', 'User', 'WorkingDir', 'Healthcheck', 'ExposedPorts'}
HOST_FIELDS = {'Binds', 'PortBindings', 'Dns', 'DnsSearch', 'DnsOptions', 'Sysctls'}
FORBIDDEN_PREFIXES = ('OPENAI_', 'ANTHROPIC_', 'CODEX_', 'DOPPLER_', 'FLAGS', 'SENTRY_', 'INNGEST_', 'LD_')
FORBIDDEN_KEYS = {'DATABASE_URL_POOLER', 'SUPABASE_ACCESS_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY',
                  'ALL_PROXY', 'NODE_OPTIONS', 'NODE_PATH', 'DOCKER_HOST', 'NODE_TLS_REJECT_UNAUTHORIZED'}

def environment(values, require):
    require(isinstance(values, list) and len(values) <= 128, 'Bounded role environment required')
    seen = set()
    for setting in values:
        require(isinstance(setting, str) and '=' in setting and '\x00' not in setting,
                'Malformed role environment refused')
        key, value = setting.split('=', 1)
        require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', key) and key not in seen,
                'Malformed or duplicate role environment key')
        require(not key.startswith(FORBIDDEN_PREFIXES) and key not in FORBIDDEN_KEYS,
                'Provider or loader role environment refused')
        require(len(value) <= 16384, 'Unbounded role environment value')
        seen.add(key)

class RoleProfiles:
    def __init__(self, profiles, require):
        require(profiles is None or isinstance(profiles, dict), 'Role profiles must be a controller map')
        self.profiles = copy.deepcopy(profiles or {})
        self.require = require
        for name, profile in self.profiles.items():
            require(isinstance(name, str) and isinstance(profile, dict) and
                    set(profile) == {'role', 'image', 'image_config', 'create', 'host', 'aliases', 'exec'},
                    'Complete exact role profile required')
            require(profile['role'] in {'db', 'kong', 'auth', 'inbucket', 'rest', 'storage',
                    'renderer', 'browser', 'tls', 'resolver', 'migration'}, 'Unknown role')
            require(isinstance(profile['image'], str) and
                    re.fullmatch(r'sha256:[0-9a-f]{64}', profile['image']), 'Immutable role image required')
            for config in (profile['image_config'], profile['create']):
                require(isinstance(config, dict), 'Image/create config snapshot required')
                environment([] if config.get('Env') is None else config['Env'], require)
                for field in ('Cmd', 'Entrypoint'):
                    command = config.get(field)
                    require(command is None or (isinstance(command, list) and len(command) <= 32 and
                            all(isinstance(x, str) and '\x00' not in x and len(x) <= 8192 for x in command)),
                            'Malformed role command')
            require(set(profile['create']) <= FIELDS, 'Unknown role create field')
            require(all(key in profile['create'] for key in ('Cmd', 'Entrypoint', 'Env', 'User', 'WorkingDir')),
                    'Effective role command/environment/user/directory required')
            require(not profile['image_config'].get('OnBuild'), 'Inherited build triggers refused')
            require(isinstance(profile['host'], dict) and set(profile['host']) <= HOST_FIELDS,
                    'Unknown role host recipe')
            volumes = profile['image_config'].get('Volumes')
            require(volumes is None or isinstance(volumes, dict), 'Malformed inherited volumes')
            binds = profile['host'].get('Binds', [])
            require(isinstance(binds, list), 'Exact role bind list required')
            destinations = set()
            for bind in binds:
                require(isinstance(bind, str) and '\x00' not in bind and
                        len(bind.split(':')) in (2, 3), 'Exact source/destination bind required')
                parts = bind.split(':')
                require(parts[1].startswith('/') and parts[1] not in destinations and
                        (len(parts) == 2 or parts[2] in ('ro', 'rw')), 'Ambiguous role bind destination')
                destinations.add(parts[1])
            require(all(destination in destinations for destination in (volumes or {})),
                    'Inherited anonymous volume is outside owned bind census')
            sysctls = profile['host'].get('Sysctls')
            require(not sysctls or (profile['role'] in ('tls', 'resolver') and
                    sysctls == {'net.ipv4.ip_unprivileged_port_start': '0'}), 'Unreviewed namespace sysctl')
            require(isinstance(profile['aliases'], list) and
                    all(isinstance(x, str) for x in profile['aliases']), 'Role aliases required')
            require(isinstance(profile['exec'], list), 'Exact exec recipes required')
            for recipe in profile['exec']:
                require(isinstance(recipe, dict) and set(recipe) == {'Cmd', 'Env', 'User', 'WorkingDir'},
                        'Exec recipe fields must be exact; interactive input is unavailable')
                environment(recipe['Env'], require)

    def profile(self, name):
        self.require(name in self.profiles, 'No reviewed executable role for container name')
        return self.profiles[name]

    def verify_image(self, name, receipt):
        profile = self.profile(name)
        self.require(isinstance(receipt, dict) and receipt.get('Id') == profile['image'] and
                     receipt.get('Config') == profile['image_config'], 'Observed inherited image config differs')

    def create(self, name, data):
        profile = self.profile(name)
        self.require(data.get('Image') == profile['image'], 'Cross-role image refused')
        self.require(set(data) <= FIELDS | {'Image', 'Labels', 'HostConfig', 'NetworkingConfig',
                     'AttachStdout', 'AttachStderr', 'AttachStdin', 'Tty', 'OpenStdin', 'StdinOnce'},
                     'Unreviewed top-level container field')
        for key in ('AttachStdin', 'OpenStdin', 'StdinOnce', 'Tty'):
            self.require(data.get(key) is None or data.get(key) is False, 'Interactive container refused')
        for key in ('AttachStdout', 'AttachStderr'):
            self.require(data.get(key) is None or type(data[key]) is bool, 'Malformed attach flag')
        effective = dict(profile['create'])
        # Docker merges image Env, so observe and bind image Config as well.
        effective.setdefault('Healthcheck', {'Test': ['NONE']})
        effective.setdefault('ExposedPorts', {})
        for field in FIELDS:
            self.require(field not in data or data[field] == effective[field], 'Unreviewed role ' + field)
            data[field] = copy.deepcopy(effective[field])
        host = data.get('HostConfig') or {}
        self.require(isinstance(host, dict), 'Malformed role host config')
        for field in HOST_FIELDS:
            expected = profile['host'].get(field, {} if field in ('PortBindings', 'Sysctls') else [])
            self.require(field not in host or host[field] == expected, 'Unreviewed role host ' + field)
            host[field] = copy.deepcopy(expected)
        data['HostConfig'] = host
        endpoints = (data.get('NetworkingConfig') or {}).get('EndpointsConfig', {})
        self.require(all(value.get('Aliases', []) == profile['aliases'] for value in endpoints.values()),
                     'Unreviewed role endpoint alias')
        return profile

    def exec(self, name, data):
        profile = self.profile(name)
        self.require(data.get('AttachStdin') is None or data.get('AttachStdin') is False,
                     'Exec stdin unavailable; use source-bound read-only mounted recipes')
        supplied = {key: data.get(key, [] if key == 'Env' else '' if key in ('User', 'WorkingDir') else None)
                    for key in ('Cmd', 'Env', 'User', 'WorkingDir')}
        self.require(supplied in profile['exec'], 'Unreviewed command/environment recipe for registered role')

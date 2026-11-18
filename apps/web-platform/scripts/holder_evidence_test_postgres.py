"""A local, uniquely owned disposable PostgreSQL container for synthetic tests.

Never fall back to an existing endpoint. The caller needs a local Docker daemon
and the postgres:17-alpine image already present; this fixture never pulls it.
"""
from contextlib import contextmanager
from dataclasses import dataclass
import json
import re
import secrets
import subprocess
import time

_ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent'}
_LABEL = 'soleur.holder-evidence-test'
_TMPFS = {'/var/lib/postgresql/data': 'rw,noexec,nosuid,size=256m,uid=70,gid=70,mode=0700',
          '/run/postgresql': 'rw,noexec,nosuid,size=16m,uid=70,gid=70,mode=0775',
          '/tmp': 'rw,noexec,nosuid,size=64m,mode=1777'}


@dataclass(frozen=True)
class Fixture:
    container_id: str
    marker: str
    image: str
    password: str

    def psql_command(self, database, user, password=None):
        if not re.fullmatch(r'[a-z_][a-z0-9_]{0,62}', database) or not re.fullmatch(r'[a-z_][a-z0-9_]{0,62}', user):
            raise RuntimeError('synthetic database target invalid')
        data = _owned(self.container_id, self.marker, self.image)
        if data['Id'] != self.container_id or not data.get('State', {}).get('Running'):
            raise RuntimeError('synthetic container not running')
        _postgres_isolated(data, self.password)
        _check_mounts(self.container_id)
        secret = self.password if password is None else password
        if not re.fullmatch(r'[0-9a-f]{48}', secret):
            raise RuntimeError('synthetic credential invalid')
        return ['/usr/bin/docker', '--host', 'unix:///var/run/docker.sock', 'exec', '-i',
                '-e', f'PGPASSWORD={secret}', self.container_id, 'psql', '-h', '127.0.0.1',
                '-U', user, '-d', database]


def _docker(*args, timeout=15):
    try:
        result = subprocess.run(['/usr/bin/docker', '--host', 'unix:///var/run/docker.sock', *args],
                                capture_output=True, text=True, env=_ENV, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError('synthetic Docker operation timed out') from None
    if result.returncode != 0:
        raise RuntimeError('synthetic Docker operation failed')
    return result.stdout.strip()


def _owned(name, marker, image):
    data = json.loads(_docker('inspect', '--format', '{{json .}}', name))
    identifier = data.get('Id')
    if not isinstance(identifier, str) or not re.fullmatch(r'[0-9a-f]{64}', identifier):
        raise RuntimeError('synthetic container identity unknown')
    if data.get('Image') != image or data.get('Config', {}).get('Labels', {}).get(_LABEL) != marker:
        raise RuntimeError('synthetic container ownership unknown')
    return data


def _postgres_isolated(data, password):
    host = data.get('HostConfig', {})
    mounts = data.get('Mounts')
    options = host.get('Tmpfs') or {}
    if (not isinstance(mounts, list) or any(mount.get('Type') != 'tmpfs' or mount.get('Destination') not in _TMPFS for mount in mounts) or
            host.get('Binds') not in (None, []) or host.get('PortBindings') not in (None, {}) or
            host.get('PublishAllPorts') not in (None, False) or host.get('Privileged') not in (None, False) or
            host.get('ReadonlyRootfs') is not True or not isinstance(host.get('CapDrop'), list) or 'ALL' not in host['CapDrop'] or
            not isinstance(host.get('SecurityOpt'), list) or 'no-new-privileges' not in host['SecurityOpt'] or
            options != _TMPFS or
            data.get('Config', {}).get('User') != '70:70' or
            f'POSTGRES_PASSWORD={password}' not in (data.get('Config', {}).get('Env') or [])):
        raise RuntimeError('synthetic storage isolation unknown')
    ports = data.get('NetworkSettings', {}).get('Ports')
    if (host.get('NetworkMode') != 'none' or not isinstance(ports, dict) or
            any(value not in (None, []) for value in ports.values())):
        raise RuntimeError('synthetic network identity unknown')


def mounts_verified(text):
    if not isinstance(text, str) or len(text) > 65536:
        return False
    seen = set()
    for line in text.splitlines():
        parts = line.split(' - ', 1)
        if len(parts) != 2:
            return False
        before, after = parts[0].split(), parts[1].split()
        if len(before) < 6 or not after:
            return False
        path = before[4]
        if path in _TMPFS:
            if path in seen or after[0] != 'tmpfs' or not {'rw', 'nosuid', 'noexec'}.issubset(set(before[5].split(','))):
                return False
            seen.add(path)
    return seen == set(_TMPFS)


def _check_mounts(identifier):
    if not mounts_verified(_docker('exec', identifier, 'busybox', 'cat', '/proc/self/mountinfo', timeout=3)):
        raise RuntimeError('synthetic actual mounts unknown')


@contextmanager
def temporary_postgres():
    marker = secrets.token_hex(16)
    password = secrets.token_hex(24)
    name = 'soleur-holder-test-' + marker
    image = _docker('image', 'inspect', 'postgres:17-alpine', '--format', '{{.Id}}')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image):
        raise RuntimeError('synthetic image identity unknown')
    attempted = False
    start_confirmed = False
    try:
        attempted = True
        identifier = _docker('run', '--detach', '--rm', '--pull=never', '--name', name,
                             '--label', f'{_LABEL}={marker}', '--env', f'POSTGRES_PASSWORD={password}',
                             '--network', 'none', '--user', '70:70', '--read-only', '--cap-drop', 'ALL',
                             '--security-opt', 'no-new-privileges', '--pids-limit', '128', '--memory', '512m',
                             '--tmpfs', '/var/lib/postgresql/data:rw,noexec,nosuid,size=256m,uid=70,gid=70,mode=0700',
                             '--tmpfs', '/run/postgresql:rw,noexec,nosuid,size=16m,uid=70,gid=70,mode=0775',
                             '--tmpfs', '/tmp:rw,noexec,nosuid,size=64m,mode=1777', image)
        start_confirmed = True
        data = _owned(name, marker, image)
        if identifier != data['Id'] or not data.get('State', {}).get('Running'):
            raise RuntimeError('synthetic container not running')
        _postgres_isolated(data, password)
        _check_mounts(identifier)
        deadline = time.monotonic() + 15
        while True:
            try:
                _docker('exec', identifier, 'pg_isready', '-U', 'postgres', '-d', 'postgres', timeout=2)
                break
            except RuntimeError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('synthetic database not ready')
                time.sleep(0.1)
        yield Fixture(identifier, marker, image, password)
    finally:
        if attempted:
            try:
                matches = _docker('ps', '--all', '--no-trunc', '--filter', f'label={_LABEL}={marker}', '--format', '{{.ID}}').splitlines()
                if len(matches) > 1:
                    raise RuntimeError('synthetic container cleanup ownership unknown')
                if matches:
                    data = _owned(name, marker, image)
                    if matches[0] != data['Id']:
                        raise RuntimeError('synthetic container cleanup ownership unknown')
                    _docker('rm', '--force', data['Id'])
                elif not start_confirmed:
                    raise RuntimeError('synthetic container startup and cleanup unknown')
                if _docker('ps', '--all', '--no-trunc', '--filter', f'label={_LABEL}={marker}', '--format', '{{.ID}}'):
                    raise RuntimeError('synthetic container cleanup unverified')
            except Exception:
                raise RuntimeError(f'synthetic container cleanup unknown: name={name} label={_LABEL}={marker} image={image}') from None

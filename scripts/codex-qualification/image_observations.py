"""Bounded, read-only image Config observations and a file-only GET manifest.

The collector has no daemon discovery or application wiring. Its result is
structural evidence only; it grants no profile, issuer, ownership, review or
execution authority. Tests use synthetic transports and never inspect a daemon.
"""
import copy
import hashlib
import math
import os
from pathlib import Path
import re
import time

import controller_inputs as inputs
import operational
from operational import BUDGET, ROLES
from prepare import Refused, canonical, require, sha

MAX_CONFIG_BYTES = 1024 * 1024
REQUIRED_CONFIG_FIELDS = {'Entrypoint', 'Cmd', 'Env', 'User', 'WorkingDir',
                          'Healthcheck', 'ExposedPorts', 'Volumes', 'OnBuild'}
MANIFEST_LIMIT = 64 * 1024


def _digest(value):
    require(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value),
            'SHA-256 observation binding required')


def _finite(value):
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except (OverflowError, TypeError, ValueError):
        return False


def action_manifest(image_ids, pairing_sha256, operational_sha256):
    """Return the exact finite GET plan; it cannot execute or authorize itself."""
    require(type(image_ids) is dict and set(image_ids) == set(ROLES),
            'Complete role-to-image observation map required')
    _digest(pairing_sha256)
    _digest(operational_sha256)
    by_image = {}
    for role in ROLES:
        image = image_ids[role]
        require(isinstance(image, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', image),
                'Immutable role image digest required')
        by_image.setdefault(image, []).append(role)
    actions = [{'method': 'GET', 'path': '/images/' + image + '/json', 'payload_sha256': None,
                'image_id': image, 'roles': by_image[image], 'read_only': True,
                'approval_required': True} for image in sorted(by_image)]
    return {'version': 1, 'pairing_sha256': pairing_sha256,
            'operational_sha256': operational_sha256, 'actions': actions,
            'execute_authorized': False, 'profile_admissible': False,
            'issuer_verification': 'pending', 'independent_review': 'pending'}


def write_action_manifest(path, manifest, *, pairing_sha256, operational_sha256):
    """Create one new private manifest file; never execute its listed requests."""
    require(isinstance(path, Path) and path.is_absolute() and '..' not in path.parts,
            'Explicit absolute manifest path required')
    require(path.parent.is_dir() and path.parent == path.parent.resolve(strict=True),
            'Manifest parent must be an existing direct path')
    _digest(pairing_sha256)
    _digest(operational_sha256)
    require(type(manifest) is dict and set(manifest) == {
        'version', 'pairing_sha256', 'operational_sha256', 'actions',
        'execute_authorized', 'profile_admissible', 'issuer_verification',
        'independent_review'} and type(manifest.get('actions')) is list,
        'Structured action manifest required')
    require(all(type(action) is dict and set(action) == {
        'method', 'path', 'payload_sha256', 'image_id', 'roles', 'read_only',
        'approval_required'} and type(action.get('roles')) is list
        for action in manifest['actions']), 'Exact GET action entries required')
    expected = action_manifest(
        {role: image for action in manifest.get('actions', [])
         for role in action.get('roles', []) for image in (action.get('image_id'),)},
        pairing_sha256, operational_sha256)
    require(manifest == expected and len(canonical(manifest)) <= MANIFEST_LIMIT,
            'Exact bounded GET-only action manifest required')
    payload = canonical(manifest) + b'\n'
    descriptor = None
    parent_descriptor = None
    created = None
    try:
        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        parent_descriptor = os.open('/', directory_flags)
        for component in path.parent.parts[1:]:
            next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor
        parent_stat = os.fstat(parent_descriptor)
        named_parent = os.stat(path.parent, follow_symlinks=False)
        require((parent_stat.st_dev, parent_stat.st_ino) ==
                (named_parent.st_dev, named_parent.st_ino), 'Manifest parent changed during open')
        descriptor = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=parent_descriptor)
        opened = os.fstat(descriptor)
        created = (opened.st_dev, opened.st_ino)
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            require(type(written) is int and written > 0, 'Manifest write made no progress')
            view = view[written:]
        os.fsync(descriptor)
        named_parent = os.stat(path.parent, follow_symlinks=False)
        require((parent_stat.st_dev, parent_stat.st_ino) ==
                (named_parent.st_dev, named_parent.st_ino), 'Manifest parent changed during write')
    except Exception:
        if descriptor is not None:
            os.close(descriptor)
            descriptor = None
        if created is not None:
            try:
                current = os.stat(path.name, dir_fd=parent_descriptor, follow_symlinks=False)
                if (current.st_dev, current.st_ino) == created:
                    os.unlink(path.name, dir_fd=parent_descriptor)
            except OSError:
                pass
        raise Refused('File-only action manifest write failed') from None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if parent_descriptor is not None:
            os.close(parent_descriptor)
    return hashlib.sha256(payload).hexdigest()


class ImageObservationCollector:
    """One bounded pass of exact GETs over caller-supplied immutable image IDs."""

    def __init__(self, contract, transport, image_ids, *, clock=time.monotonic):
        operational.checked_contract(contract)
        inputs.checked_inputs(contract)
        component = contract.get('source_references', {}).get(
            'scripts/codex-qualification/image_observations.py', {})
        require(component.get('sha256') == sha(Path(__file__).read_bytes()),
                'Executing image-observation component differs from source reference')
        require(callable(clock), 'Monotonic observation clock required')
        require(type(image_ids) is dict and set(image_ids) == set(ROLES),
                'Complete role-to-image observation map required')
        self._image_ids = copy.deepcopy(image_ids)
        self._contract = copy.deepcopy(contract)
        self._actions = action_manifest(self._image_ids, contract['pairing_sha256'],
                                        contract['operational_sha256'])['actions']
        try:
            request = getattr(transport, 'request', None)
        except Exception:
            raise Refused('Explicit read transport required') from None
        require(callable(request), 'Explicit read transport required')
        self._transport = transport
        self._request = request
        self._clock = clock
        self._last = self._tick()
        self._attempted = False

    def _tick(self):
        try:
            value = self._clock()
        except Exception:
            raise Refused('Image observation clock failed') from None
        require(_finite(value),
                'Finite monotonic image observation clock required')
        return value

    def _remaining(self, deadline):
        now = self._tick()
        require(now >= self._last, 'Image observation clock moved backwards')
        self._last = now
        remaining = deadline - now
        require(remaining > 0, 'Image observation deadline expired')
        return remaining

    def collect(self, *, timeout):
        require(not self._attempted, 'One image observation pass only')
        require(_finite(timeout) and
                0 < timeout <= BUDGET['work_seconds'],
                'Finite positive bounded image observation timeout required')
        self._attempted = True
        start = self._last
        deadline = start + timeout
        require(_finite(deadline) and deadline > start,
                'Finite advancing image observation deadline required')
        observations = {}
        for action in self._actions:
            remaining = self._remaining(deadline)
            try:
                receipt = self._request('GET', action['path'], b'', timeout=remaining)
            except Exception:
                raise Refused('Image Config observation request failed') from None
            self._remaining(deadline)
            require(type(receipt) is tuple and len(receipt) == 2,
                    'Exact image Config transport receipt required')
            status, response = receipt
            require(type(status) is int and status == 200 and type(response) is dict,
                    'Exact successful image Config response required')
            image = action['image_id']
            require(response.get('Id') == image and type(response.get('Config')) is dict,
                    'Observed immutable image identity or Config differs')
            try:
                config = copy.deepcopy(response['Config'])
                encoded_config = canonical(config)
            except Exception:
                raise Refused('Image Config observation parsing failed') from None
            require(REQUIRED_CONFIG_FIELDS <= set(config) and
                    len(encoded_config) <= MAX_CONFIG_BYTES,
                    'Complete bounded inherited image Config required')
            observations[image] = {'Config': config, 'config_sha256': sha(encoded_config)}
            self._remaining(deadline)
        role_results = {role: {'image_id': image,
                               'image_config': copy.deepcopy(observations[image]['Config']),
                               'image_config_sha256': observations[image]['config_sha256']}
                        for role, image in self._image_ids.items()}
        self._remaining(deadline)
        return {'roles': role_results, 'execute_authorized': False,
                'pairing_sha256': self._contract['pairing_sha256'],
                'operational_sha256': self._contract['operational_sha256'],
                'profile_admissible': False, 'authentication_established': False,
                'ownership_verified': False, 'quiescence_verified': False,
                'issuer_verification': 'pending', 'independent_review': 'pending',
                'runtime_evidence': 'untrusted-structural-image-observations'}
